import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_maplibre_gpu/flutter_map_maplibre_gpu.dart';
import 'package:latlong2/latlong.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart' as gpu;

import 'location_tracker.dart';

void main() => runApp(const CurrentLocationApp());

/// A map with a foreground location marker and a single recenter button.
class CurrentLocationApp extends StatelessWidget {
  /// Creates the standalone current-location example.
  const CurrentLocationApp({super.key});

  @override
  Widget build(context) => MaterialApp(
    title: 'Current Location',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorSchemeSeed: const Color(0xFF1A73E8)),
    home: const _LocationMap(),
  );
}

class _LocationMap extends StatefulWidget {
  const _LocationMap();

  @override
  State<_LocationMap> createState() => _LocationMapState();
}

class _LocationMapState extends State<_LocationMap>
    with WidgetsBindingObserver {
  final _mapController = MapController();
  final _location = LocationTracker();
  var _minZoom = MapLibreGpuLayer.minZoom;
  var _mapReady = false;
  var _following = true;
  var _zoomOnNextFix = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _location.addListener(_onLocationChanged);
  }

  @override
  void didChangeAppLifecycleState(state) {
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(_location.resume());
      case AppLifecycleState.hidden ||
          AppLifecycleState.paused ||
          AppLifecycleState.detached ||
          AppLifecycleState.inactive:
        _location.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _location.removeListener(_onLocationChanged);
    _location.dispose();
    _mapController.dispose();
    super.dispose();
  }

  void _onLocationChanged() {
    if (!mounted) return;
    if (_following) _centerOnLocation();
    setState(() {});
  }

  void _centerOnLocation() {
    final position = _location.position;
    if (!_mapReady || position == null) return;
    final zoom = _zoomOnNextFix
        ? math.max(_mapController.camera.zoom, 16.0)
        : _mapController.camera.zoom;
    _zoomOnNextFix = false;
    _mapController.move(
      LatLng(
        position.latitude
            .clamp(-MapLibreGpuLayer.maxLatitude, MapLibreGpuLayer.maxLatitude)
            .toDouble(),
        position.longitude,
      ),
      zoom,
    );
  }

  Future<void> _locate() async {
    setState(() {
      _following = true;
      _zoomOnNextFix = true;
    });
    if (_location.status == LocationStatus.serviceDisabled ||
        _location.status == LocationStatus.permissionDeniedForever) {
      await _location.openSettings();

      return;
    }
    if (_location.position != null) {
      _centerOnLocation();
    } else {
      await _location.start(requestPermission: true);
    }
  }

  void _onMapEvent(MapEvent event) {
    if (event is! MapEventNonRotatedSizeChange) return;
    final size = _mapController.camera.nonRotatedSize;
    // The diagonal keeps rotated viewports within Web Mercator's latitude range.
    final diagonal = math.sqrt(
      size.width * size.width + size.height * size.height,
    );
    final minZoom = math.max(
      MapLibreGpuLayer.minZoom,
      math.log(diagonal / 256) / math.ln2 + 1e-6,
    );
    _mapController.move(
      _mapController.camera.center,
      math.max(_mapController.camera.zoom, minZoom),
    );
    setState(() => _minZoom = minZoom);
  }

  @override
  Widget build(context) {
    final position = _location.position;
    final unavailable =
        _location.status == LocationStatus.serviceDisabled ||
        _location.status == LocationStatus.permissionDenied ||
        _location.status == LocationStatus.permissionDeniedForever;
    final tooltip = switch (_location.status) {
      LocationStatus.serviceDisabled => 'Enable location services',
      LocationStatus.permissionDeniedForever => 'Allow location in Settings',
      _ => 'Show current location',
    };

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: const LatLng(35.6812, 139.7671),
              initialZoom: 13,
              minZoom: _minZoom,
              maxZoom: MapLibreGpuLayer.maxZoom,
              cameraConstraint: const CameraConstraint.containLatitude(
                -MapLibreGpuLayer.maxLatitude,
                MapLibreGpuLayer.maxLatitude,
              ),
              onMapReady: () {
                _mapReady = true;
                unawaited(_location.start());
              },
              onMapEvent: _onMapEvent,
              onPositionChanged: (_, hasGesture) {
                if (hasGesture && _following) {
                  setState(() => _following = false);
                }
              },
            ),
            children: [
              MapLibreGpuLayer(
                styleString: gpu.MapLibreStyles.openfreemapLiberty,
                userLocation: position == null
                    ? null
                    : gpu.MapUserLocation(
                        position: gpu.LatLng(
                          position.latitude,
                          position.longitude,
                        ),
                        accuracyMeters:
                            position.accuracy.isFinite && position.accuracy >= 0
                            ? position.accuracy
                            : null,
                      ),
              ),
            ],
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.bottomRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 60),
                child: Material(
                  color: Colors.white,
                  elevation: 3,
                  shape: const CircleBorder(),
                  clipBehavior: Clip.antiAlias,
                  child: IconButton(
                    tooltip: tooltip,
                    onPressed: _location.busy ? null : _locate,
                    constraints: const BoxConstraints.tightFor(
                      width: 48,
                      height: 48,
                    ),
                    color: _following && position != null
                        ? const Color(0xFF1A73E8)
                        : const Color(0xFF5F6368),
                    icon: _location.busy
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            unavailable
                                ? Icons.location_disabled
                                : _following && position != null
                                ? Icons.my_location
                                : Icons.location_searching,
                          ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
