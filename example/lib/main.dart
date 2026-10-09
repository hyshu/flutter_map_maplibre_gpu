import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_maplibre_gpu/flutter_map_maplibre_gpu.dart';
import 'package:latlong2/latlong.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart' as gpu;

import 'places.dart';

void main() => runApp(const MapExplorerApp());

/// Explores cities with Flutter Map markers over a vector map.
class MapExplorerApp extends StatelessWidget {
  const MapExplorerApp({super.key});

  @override
  Widget build(context) => MaterialApp(
    title: 'World map',
    debugShowCheckedModeBanner: false,
    home: const _MapExplorer(),
  );
}

const _worldCenter = LatLng(20, 0);
const _worldZoom = 2.0;

class _MapExplorer extends StatefulWidget {
  const _MapExplorer();

  @override
  State<_MapExplorer> createState() => _MapExplorerState();
}

class _MapExplorerState extends State<_MapExplorer> {
  final _mapController = MapController();
  var _minZoom = MapLibreGpuLayer.minZoom;
  var _layerKey = UniqueKey();
  var _styleLoaded = false;
  var _frameReady = false;
  var _ready = false;
  var _mapTimedOut = false;
  Timer? _mapTimeout;

  @override
  void initState() {
    super.initState();
    _startMapTimeout();
  }

  void _startMapTimeout() {
    _mapTimeout?.cancel();
    _mapTimeout = Timer(const Duration(seconds: 30), () {
      if (mounted && !_ready) setState(() => _mapTimedOut = true);
    });
  }

  @override
  void dispose() {
    _mapTimeout?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  void _reloadMap() {
    setState(() {
      _layerKey = UniqueKey();
      _styleLoaded = false;
      _frameReady = false;
      _ready = false;
      _mapTimedOut = false;
    });
    _startMapTimeout();
  }

  void _notifyReady() {
    if (_ready || !_styleLoaded || !_frameReady) return;
    _mapTimeout?.cancel();
    setState(() {
      _ready = true;
      _mapTimedOut = false;
    });
  }

  void _zoom(double delta) {
    final camera = _mapController.camera;
    _mapController.move(camera.center, camera.zoom + delta);
  }

  void _showCity(LatLng point) => _mapController.move(
    point,
    math
        .max(_mapController.camera.zoom + 2, 10)
        .clamp(MapLibreGpuLayer.minZoom, 19)
        .toDouble(),
  );

  void _showWorld() {
    _mapController.rotate(0);
    _mapController.move(_worldCenter, _worldZoom);
  }

  void _onMapEvent(MapEvent event) {
    if (event is! MapEventNonRotatedSizeChange) return;
    final camera = _mapController.camera;
    final size = camera.nonRotatedSize;
    // The viewport diagonal fits every rotation within the map's latitude range.
    final diagonal = math.sqrt(
      size.width * size.width + size.height * size.height,
    );
    final minZoom = math.max(
      MapLibreGpuLayer.minZoom,
      math.log(diagonal / 256) / math.ln2 + 1e-6,
    );
    _mapController.move(camera.center, math.max(camera.zoom, minZoom));
    setState(() => _minZoom = minZoom);
  }

  @override
  Widget build(context) {
    final key = _layerKey;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _worldCenter,
              initialZoom: _worldZoom,
              minZoom: _minZoom,
              maxZoom: MapLibreGpuLayer.maxZoom,
              cameraConstraint: const CameraConstraint.containLatitude(
                -MapLibreGpuLayer.maxLatitude,
                MapLibreGpuLayer.maxLatitude,
              ),
              onMapEvent: _onMapEvent,
            ),
            children: [
              MapLibreGpuLayer(
                key: key,
                styleString: gpu.MapLibreStyles.openfreemapLiberty,
                loadingBuilder: null,
                overlayBuilder: (context, frame) =>
                    _CityMarkers(frame: frame, onSelected: _showCity),
                onStyleLoadedCallback: () {
                  if (!mounted || key != _layerKey) return;
                  _styleLoaded = true;
                  _notifyReady();
                },
                onFrame: (_) {
                  if (!mounted || key != _layerKey) return;
                  _frameReady = true;
                  _notifyReady();
                },
              ),
            ],
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Stack(
                children: [
                  Align(
                    alignment: Alignment.topRight,
                    child: _MapButton(
                      tooltip: 'Show world',
                      icon: Icons.public,
                      onPressed: _ready ? _showWorld : null,
                    ),
                  ),
                  if (!_ready)
                    Center(
                      child: _mapTimedOut
                          ? FilledButton.icon(
                              onPressed: _reloadMap,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Retry map'),
                            )
                          : const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                    ),
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 44),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        spacing: 4.0,
                        children: [
                          _MapButton(
                            tooltip: 'Zoom in',
                            icon: Icons.add,
                            onPressed: _ready ? () => _zoom(1) : null,
                          ),
                          _MapButton(
                            tooltip: 'Zoom out',
                            icon: Icons.remove,
                            onPressed: _ready ? () => _zoom(-1) : null,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MapButton extends StatelessWidget {
  const _MapButton({required this.tooltip, required this.icon, this.onPressed});

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(context) => Card(
    margin: EdgeInsets.zero,
    color: Colors.white,
    child: IconButton(tooltip: tooltip, onPressed: onPressed, icon: Icon(icon)),
  );
}

class _CityMarkers extends StatelessWidget {
  const _CityMarkers({required this.frame, required this.onSelected});

  final gpu.MapFrameState frame;
  final ValueChanged<LatLng> onSelected;

  @override
  Widget build(context) {
    final size = (10 + frame.camera.zoom * 2).clamp(12, 32).toDouble();

    return FlutterMapGpuAdapter(
      frame: frame,
      child: MarkerLayer(
        markers: [
          for (final place in places)
            Marker(
              point: place.point,
              width: size,
              height: size,
              rotate: true,
              child: Tooltip(
                message: place.name,
                child: GestureDetector(
                  onTap: () => onSelected(place.point),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: size / 16),
                    ),
                    child: Icon(
                      Icons.location_city,
                      size: size * 0.65,
                      color: Colors.white,
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
