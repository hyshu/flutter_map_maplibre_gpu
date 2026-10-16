import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

/// Foreground location availability, including recoverable permission failures.
enum LocationStatus {
  idle,
  checking,
  locating,
  active,
  serviceDisabled,
  permissionDenied,
  permissionDeniedForever,
  failed,
}

/// Owns location subscriptions while the app is visible.
///
/// Only an explicit [start] with `requestPermission` can display a permission
/// prompt. Call [pause] when hidden, [resume] when visible, and [dispose] when
/// the map is removed. Delayed results from stopped sessions are discarded.
class LocationTracker extends ChangeNotifier {
  /// Creates a tracker using the registered platform location provider.
  LocationTracker({
    GeolocatorPlatform? platform,
    this.initialFixTimeout = const Duration(seconds: 30),
  }) : _platform = platform ?? GeolocatorPlatform.instance;

  /// The maximum wait for the first valid fix, independent of later updates.
  final Duration initialFixTimeout;
  final GeolocatorPlatform _platform;
  StreamSubscription<Position>? _positions;
  StreamSubscription<ServiceStatus>? _services;
  Future<void> _cancelling = Future<void>.value();
  Future<LocationPermission>? _permissionRequest;
  Timer? _firstFixTimeout;
  var _generation = 0;
  var _foreground = true;
  var _disposed = false;
  var _status = LocationStatus.idle;
  Position? _position;

  /// The current acquisition state or reason location is unavailable.
  LocationStatus get status => _status;

  /// The latest valid foreground fix, or null while location is unavailable.
  Position? get position => _position;

  /// Whether a permission check or the initial location fix is pending.
  bool get busy =>
      _status == LocationStatus.checking || _status == LocationStatus.locating;

  bool _isCurrent(int generation) =>
      !_disposed && _foreground && generation == _generation;

  /// Starts updates, optionally asking for foreground permission.
  Future<void> start({bool requestPermission = false}) async {
    if (_disposed || !_foreground || busy || _positions != null) return;
    final generation = ++_generation;
    _status = LocationStatus.checking;
    notifyListeners();
    try {
      await _cancelling;
      if (!_isCurrent(generation)) return;
      final serviceEnabled = await _platform.isLocationServiceEnabled();
      if (!_isCurrent(generation)) return;
      if (!serviceEnabled) {
        _stop(LocationStatus.serviceDisabled);

        return;
      }
      var permission = await _platform.checkPermission();
      if (!_isCurrent(generation)) return;
      if (_permissionRequest != null ||
          (requestPermission && permission == LocationPermission.denied)) {
        final request = _permissionRequest ??= _platform.requestPermission();
        try {
          permission = await request;
        } finally {
          if (identical(_permissionRequest, request)) _permissionRequest = null;
        }
      }
      if (!_isCurrent(generation)) return;
      if (permission != LocationPermission.whileInUse &&
          permission != LocationPermission.always) {
        _stop(
          permission == LocationPermission.deniedForever
              ? LocationStatus.permissionDeniedForever
              : LocationStatus.permissionDenied,
        );

        return;
      }
      _status = LocationStatus.locating;
      _firstFixTimeout = Timer(initialFixTimeout, () {
        if (_isCurrent(generation)) _stop(LocationStatus.failed);
      });
      _services = _platform.getServiceStatusStream().listen(
        (status) {
          if (_isCurrent(generation) && status == ServiceStatus.disabled) {
            _stop(LocationStatus.serviceDisabled);
          }
        },
        onError: (Object error) {
          if (_isCurrent(generation)) _handleError(error);
        },
      );
      _positions = _platform
          .getPositionStream(
            locationSettings:
                defaultTargetPlatform == TargetPlatform.iOS ||
                    defaultTargetPlatform == TargetPlatform.macOS
                ? AppleSettings(
                    accuracy: LocationAccuracy.high,
                    distanceFilter: 5,
                    allowBackgroundLocationUpdates: false,
                  )
                : const LocationSettings(
                    accuracy: LocationAccuracy.high,
                    distanceFilter: 5,
                  ),
          )
          .listen(
            (position) {
              if (!_isCurrent(generation) ||
                  !position.latitude.isFinite ||
                  !position.longitude.isFinite ||
                  position.latitude.abs() > 90 ||
                  position.longitude.abs() > 180) {
                return;
              }
              _firstFixTimeout?.cancel();
              _position = position;
              _status = LocationStatus.active;
              notifyListeners();
            },
            onError: (Object error) {
              if (_isCurrent(generation)) _handleError(error);
            },
            onDone: () {
              if (_isCurrent(generation)) _stop(LocationStatus.failed);
            },
          );
      notifyListeners();
    } catch (error) {
      if (_isCurrent(generation)) _handleError(error);
    }
  }

  /// Releases location services and clears the fix while the app is hidden.
  void pause() {
    _foreground = false;
    _stop(LocationStatus.idle);
  }

  /// Restarts updates without displaying another permission prompt.
  Future<void> resume() async {
    if (_foreground || _disposed) return;
    _foreground = true;
    await start();
  }

  /// Opens the system page that can resolve the current location failure.
  Future<bool> openSettings() => _status == LocationStatus.serviceDisabled
      ? _platform.openLocationSettings()
      : _platform.openAppSettings();

  void _handleError(Object error) => _stop(switch (error) {
    LocationServiceDisabledException() => LocationStatus.serviceDisabled,
    PermissionDeniedException() => LocationStatus.permissionDenied,
    _ => LocationStatus.failed,
  });

  void _stop(LocationStatus status) {
    ++_generation;
    _cancelSubscriptions();
    _position = null;
    _status = status;
    if (!_disposed) notifyListeners();
  }

  void _cancelSubscriptions() {
    _firstFixTimeout?.cancel();
    _firstFixTimeout = null;
    final positions = _positions;
    final services = _services;
    _positions = null;
    _services = null;
    // Native providers must finish stopping before a new session starts.
    _cancelling = _cancelling
        .then((_) async {
          try {
            await positions?.cancel();
          } finally {
            await services?.cancel();
          }
        })
        .catchError((Object _) {});
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _cancelSubscriptions();
    super.dispose();
  }
}
