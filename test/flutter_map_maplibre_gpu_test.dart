import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_maplibre_gpu/flutter_map_maplibre_gpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart' as gpu;

void main() {
  Widget map({
    MapController? controller,
    MapOptions options = const MapOptions(
      initialCenter: LatLng(35, 139),
      initialZoom: 12.5,
      initialRotation: 32,
    ),
    MapLibreGpuLayer layer = const MapLibreGpuLayer(),
  }) => Directionality(
    textDirection: TextDirection.ltr,
    child: Center(
      child: SizedBox.shrink(
        child: FlutterMap(
          mapController: controller,
          options: options,
          children: [layer],
        ),
      ),
    ),
  );

  testWidgets('inherits camera and follows updates without remounting', (
    tester,
  ) async {
    final controller = MapController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(map(controller: controller));
    final nativeFinder = find.byType(gpu.MapLibreMap);
    final state = tester.state(nativeFinder);
    var native = tester.widget<gpu.MapLibreMap>(nativeFinder);
    expect(
      native.cameraPosition,
      const gpu.CameraPosition(
        target: gpu.LatLng(35, 139),
        zoom: 11.5,
        bearing: -32,
      ),
    );
    expect(native.cameraConstrainMode, gpu.CameraConstrainMode.none);
    expect(native.minMaxTiltPreference, const gpu.MinMaxTiltPreference(0, 0));
    expect(native.compassEnabled, isFalse);
    expect(native.attributionButtonEnabled, isTrue);

    controller.moveAndRotate(const LatLng(-20, -179.5), 1, -47);
    await tester.pump();
    native = tester.widget<gpu.MapLibreMap>(nativeFinder);
    expect(tester.state(nativeFinder), same(state));
    expect(
      native.cameraPosition,
      const gpu.CameraPosition(
        target: gpu.LatLng(-20, -179.5),
        zoom: 0,
        bearing: 47,
      ),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('passes changed styles to the same native map', (tester) async {
    await tester.pumpWidget(
      map(layer: const MapLibreGpuLayer(styleString: 'first.json')),
    );
    final state = tester.state(find.byType(gpu.MapLibreMap));
    await tester.pumpWidget(
      map(layer: const MapLibreGpuLayer(styleString: 'second.json')),
    );
    expect(tester.state(find.byType(gpu.MapLibreMap)), same(state));
    expect(
      tester.widget<gpu.MapLibreMap>(find.byType(gpu.MapLibreMap)).styleString,
      'second.json',
    );
  });

  testWidgets('forwards location updates and a custom builder', (tester) async {
    final first = gpu.MapUserLocation(
      position: const gpu.LatLng(35, 139),
      headingDegrees: 90,
      accuracyMeters: 20,
    );
    Widget? builder(context, gpu.MapUserLocationRenderState state) =>
        const SizedBox(width: 24, height: 24);

    await tester.pumpWidget(
      map(
        layer: MapLibreGpuLayer(
          userLocation: first,
          userLocationBuilder: builder,
        ),
      ),
    );
    final finder = find.byType(gpu.MapLibreMap);
    final state = tester.state(finder);
    var native = tester.widget<gpu.MapLibreMap>(finder);
    expect(native.userLocation, same(first));
    expect(native.userLocationBuilder, same(builder));

    final second = gpu.MapUserLocation(
      position: const gpu.LatLng(35.1, 139.2),
      accuracyMeters: 8,
    );
    await tester.pumpWidget(map(layer: MapLibreGpuLayer(userLocation: second)));
    native = tester.widget<gpu.MapLibreMap>(finder);
    expect(tester.state(finder), same(state));
    expect(native.userLocation, same(second));
    expect(
      native.userLocationBuilder,
      gpu.MapLibreMap.defaultUserLocationBuilder,
    );

    await tester.pumpWidget(
      map(
        layer: MapLibreGpuLayer(
          userLocation: second,
          userLocationBuilder: null,
        ),
      ),
    );
    native = tester.widget<gpu.MapLibreMap>(finder);
    expect(native.userLocation, same(second));
    expect(native.userLocationBuilder, isNull);

    await tester.pumpWidget(map());
    expect(tester.widget<gpu.MapLibreMap>(finder).userLocation, isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rejects unsupported projection instead of drifting', (
    tester,
  ) async {
    await tester.pumpWidget(map(options: const MapOptions(crs: Epsg4326())));
    expect(tester.takeException(), isA<UnsupportedError>());
  });

  for (final zoom in [0.0, 26.6]) {
    testWidgets('rejects unsupported zoom $zoom', (tester) async {
      await tester.pumpWidget(map(options: MapOptions(initialZoom: zoom)));
      expect(tester.takeException(), isA<ArgumentError>());
    });
  }

  testWidgets('rejects centers outside native projection', (tester) async {
    await tester.pumpWidget(
      map(options: const MapOptions(initialCenter: LatLng(89, 0))),
    );
    expect(tester.takeException(), isA<ArgumentError>());
  });
}
