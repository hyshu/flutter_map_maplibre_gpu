# flutter_map_maplibre_gpu

MapLibre vector maps for `flutter_map`, with markers and routes that stay aligned
as you drag, zoom, and rotate. Powered by
[maplibre_flutter_gpu](https://pub.dev/packages/maplibre_flutter_gpu).

Reuse your Flutter Map markers, polylines, polygons, and circles. Flutter
renders the map and your widgets together.

## Getting started

```sh
flutter pub add flutter_map_maplibre_gpu flutter_map latlong2
```

Requires Flutter 3.47 or later and Flutter Map 8.3.2 or a compatible 8.x release.
Follow the [GPU setup](https://pub.dev/packages/maplibre_flutter_gpu#getting-started)
to enable Flutter GPU in your app.

Android, iOS, macOS, Windows, and Linux are supported.
Web is unsupported because Flutter GPU is unavailable on the web.
Windows and Linux currently support debug/profile builds only.

## Keep your layers with the map

Flutter Map handles gestures. Put your layers inside `FlutterMapGpuAdapter` in
`overlayBuilder` so they follow the map together.

```dart
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_maplibre_gpu/flutter_map_maplibre_gpu.dart';
import 'package:latlong2/latlong.dart';

FlutterMap(
  options: MapOptions(
    initialCenter: const LatLng(35.6812, 139.7671),
    initialZoom: 14,
    minZoom: MapLibreGpuLayer.minZoom,
    maxZoom: MapLibreGpuLayer.maxZoom,
    cameraConstraint: CameraConstraint.containCenter(
      bounds: LatLngBounds(
        const LatLng(-MapLibreGpuLayer.maxLatitude, -180),
        const LatLng(MapLibreGpuLayer.maxLatitude, 180),
      ),
    ),
  ),
  children: [
    MapLibreGpuLayer(
      styleString: 'https://tiles.openfreemap.org/styles/liberty',
      overlayBuilder: (context, frame) => FlutterMapGpuAdapter(
        frame: frame,
        child: const MarkerLayer(
          markers: [
            Marker(
              point: LatLng(35.6812, 139.7671),
              width: 32,
              height: 32,
              child: Icon(Icons.location_on, color: Colors.red),
            ),
          ],
        ),
      ),
    ),
  ],
);
```

Use a `Stack(fit: StackFit.expand, children: [...])` inside the adapter for
multiple layers. Use the parent Flutter Map controller for camera changes.
Layers placed beside `MapLibreGpuLayer` can move ahead of the map while it renders.

To let MapLibre handle gestures, use the same adapter in
`MapLibreMap.overlayBuilder` with `tiltGesturesEnabled: false` and
`minMaxTiltPreference: MinMaxTiltPreference(0, 0)`.
See the [example app](example/lib/main.dart) for an interactive world map.

## A few limits

- Use a flat `Epsg3857` map. Keep the zoom and center limits shown above, and let
  the GPU layer fill the map viewport.
- The adapter's controller is read-only and emits no map events. Plugins that
  move it or listen to its events need their own integration.
- Map data attribution stays visible by default. If you hide it, provide it
  yourself.

For a current-location marker, pass `userLocation` to `MapLibreGpuLayer`.
Your app supplies the location and handles permissions.
