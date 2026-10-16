import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_map_current_location_example/location_tracker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

void main() {
  late _FakeGeolocator platform;
  late LocationTracker tracker;
  var disposed = false;

  void trackerTest(String description, Future<void> Function() body) {
    test(description, () async {
      platform = _FakeGeolocator();
      tracker = LocationTracker(platform: platform);
      disposed = false;
      try {
        await body();
      } finally {
        if (!disposed) tracker.dispose();
        debugDefaultTargetPlatformOverride = null;
        await platform.close();
      }
    });
  }

  trackerTest('requests permission only after an explicit start', () async {
    platform.permission = LocationPermission.denied;
    await tracker.start();
    expect(tracker.status, LocationStatus.permissionDenied);
    expect(platform.permissionRequests, 0);
    expect(platform.positionSubscriptions, 0);

    await tracker.start(requestPermission: true);
    expect(platform.permissionRequests, 1);
    expect(platform.positionSubscriptions, 1);
    expect(tracker.status, LocationStatus.locating);
  });

  trackerTest(
    'does not subscribe after either kind of permission denial',
    () async {
      platform.permission = LocationPermission.denied;
      platform.requestResult = LocationPermission.denied;
      await tracker.start(requestPermission: true);
      expect(tracker.status, LocationStatus.permissionDenied);
      expect(platform.positionSubscriptions, 0);

      platform.permission = LocationPermission.deniedForever;
      await tracker.start(requestPermission: true);
      expect(tracker.status, LocationStatus.permissionDeniedForever);
      expect(platform.permissionRequests, 1);
      expect(platform.positionSubscriptions, 0);
    },
  );

  trackerTest(
    'resume shares a permission request interrupted by pause',
    () async {
      platform.permission = LocationPermission.denied;
      final permission = platform.pendingPermission = Completer();
      final starting = tracker.start(requestPermission: true);
      await Future<void>.delayed(Duration.zero);
      expect(platform.permissionRequests, 1);

      tracker.pause();
      final resuming = tracker.resume();
      await Future<void>.delayed(Duration.zero);
      permission.complete(LocationPermission.whileInUse);
      await Future.wait([starting, resuming]);
      expect(platform.permissionRequests, 1);
      expect(platform.positionSubscriptions, 1);
      expect(tracker.status, LocationStatus.locating);
    },
  );

  trackerTest('pause and dispose discard delayed permission results', () async {
    platform.permission = LocationPermission.denied;
    final permission = platform.pendingPermission = Completer();
    final starting = tracker.start(requestPermission: true);
    await Future<void>.delayed(Duration.zero);
    tracker.pause();
    permission.complete(LocationPermission.whileInUse);
    await starting;
    expect(tracker.status, LocationStatus.idle);
    expect(platform.positionSubscriptions, 0);

    final nextPermission = platform.pendingPermission = Completer();
    final resuming = tracker.resume();
    await Future<void>.delayed(Duration.zero);
    await resuming;
    final retrying = tracker.start(requestPermission: true);
    await Future<void>.delayed(Duration.zero);
    tracker.dispose();
    disposed = true;
    nextPermission.complete(LocationPermission.whileInUse);
    await retrying;
    expect(platform.positionSubscriptions, 0);
  });

  trackerTest(
    'disabled services and stream failures clear the visible fix',
    () async {
      platform.serviceEnabled = false;
      await tracker.start(requestPermission: true);
      expect(tracker.status, LocationStatus.serviceDisabled);
      expect(platform.permissionRequests, 0);
      expect(platform.positionSubscriptions, 0);

      platform.serviceEnabled = true;
      await tracker.start();
      platform.positions.add(_position());
      expect(tracker.position, isNotNull);
      platform.services.add(ServiceStatus.disabled);
      await Future<void>.delayed(Duration.zero);
      expect(tracker.status, LocationStatus.serviceDisabled);
      expect(tracker.position, isNull);
      expect(platform.positionCancellations, 1);

      await tracker.start();
      platform.positions.add(_position());
      platform.positions.addError(const PermissionDeniedException('Revoked'));
      await Future<void>.delayed(Duration.zero);
      expect(tracker.status, LocationStatus.permissionDenied);
      expect(tracker.position, isNull);
      expect(platform.positionCancellations, 2);
    },
  );

  trackerTest(
    'initial timeout releases sensors but a stationary fix stays valid',
    () async {
      tracker.dispose();
      tracker = LocationTracker(
        platform: platform,
        initialFixTimeout: const Duration(milliseconds: 20),
      );
      await tracker.start();
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(tracker.status, LocationStatus.failed);
      expect(platform.positionCancellations, 1);

      await tracker.start();
      final fix = _position();
      platform.positions.add(fix);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(tracker.position, same(fix));
      expect(tracker.status, LocationStatus.active);
      expect(platform.positionCancellations, 1);
      expect(platform.settings!.timeLimit, isNull);
    },
  );

  trackerTest(
    'ignores invalid coordinates while retaining the last valid fix',
    () async {
      await tracker.start();
      final fix = _position();
      platform.positions.add(fix);
      for (final invalid in [
        _position(latitude: double.nan),
        _position(longitude: double.infinity),
        _position(latitude: 91),
        _position(longitude: 181),
      ]) {
        platform.positions.add(invalid);
        expect(tracker.position, same(fix));
      }
    },
  );

  for (final target in [TargetPlatform.iOS, TargetPlatform.macOS]) {
    trackerTest('disables background updates on ${target.name}', () async {
      debugDefaultTargetPlatformOverride = target;
      await tracker.start();
      final settings = platform.settings! as AppleSettings;
      expect(settings.allowBackgroundLocationUpdates, isFalse);
      expect(settings.accuracy, LocationAccuracy.high);
      expect(settings.distanceFilter, 5);
    });
  }
}

Position _position({double latitude = 35, double longitude = 139}) => Position(
  latitude: latitude,
  longitude: longitude,
  timestamp: DateTime.utc(2026),
  accuracy: 8,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

class _FakeGeolocator extends GeolocatorPlatform {
  _FakeGeolocator() {
    positions = StreamController<Position>.broadcast(
      sync: true,
      onListen: () => positionSubscriptions++,
      onCancel: () => positionCancellations++,
    );
  }

  late final StreamController<Position> positions;
  final services = StreamController<ServiceStatus>.broadcast(sync: true);
  var serviceEnabled = true;
  var permission = LocationPermission.whileInUse;
  var requestResult = LocationPermission.whileInUse;
  Completer<LocationPermission>? pendingPermission;
  var permissionRequests = 0;
  var positionSubscriptions = 0;
  var positionCancellations = 0;
  LocationSettings? settings;

  @override
  Future<bool> isLocationServiceEnabled() async => serviceEnabled;

  @override
  Future<LocationPermission> checkPermission() async => permission;

  @override
  Future<LocationPermission> requestPermission() async {
    permissionRequests++;

    return pendingPermission?.future ?? requestResult;
  }

  @override
  Stream<ServiceStatus> getServiceStatusStream() => services.stream;

  @override
  Stream<Position> getPositionStream({locationSettings}) {
    settings = locationSettings;

    return positions.stream;
  }

  Future<void> close() async {
    await positions.close();
    await services.close();
  }
}
