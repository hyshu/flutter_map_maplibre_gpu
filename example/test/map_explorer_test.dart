import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_maplibre_gpu/flutter_map_maplibre_gpu.dart';
import 'package:flutter_map_maplibre_gpu_example/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart' as gpu;

void main() {
  for (final viewport in [
    (name: 'small', size: const Size(240, 180)),
    (name: 'portrait', size: const Size(390, 844)),
    (name: 'landscape', size: const Size(1280, 720)),
    (name: 'fractional', size: const Size(799.5, 601.25)),
  ]) {
    testWidgets('initial minimum zoom fits ${viewport.name} viewport', (
      tester,
    ) async {
      final controller = await _pumpExplorer(tester, viewport.size);
      _expectMinimumUsable(tester, controller.camera);
      _expectVerticalCoverage(controller.camera);
    });
  }

  testWidgets('minimum zoom keeps rotated pole pans inside the world', (
    tester,
  ) async {
    final controller = await _pumpExplorer(tester, const Size(900, 600));
    for (final rotation in [0.0, 45.0, 90.0, 135.0, 225.0, 315.0]) {
      for (final latitude in [-85.0, 85.0]) {
        controller.moveAndRotate(LatLng(latitude, 30), 1, rotation);
        await tester.pump();
        expect(controller.camera.rotation, rotation);
        _expectMinimumUsable(tester, controller.camera);
        _expectVerticalCoverage(controller.camera);
      }
    }
  });

  testWidgets('latitude containment preserves horizontal world wrapping', (
    tester,
  ) async {
    final controller = await _pumpExplorer(tester, const Size(900, 600));
    for (final longitude in [-179.0, 179.0]) {
      controller.moveAndRotate(LatLng(0, longitude), 1, 45);
      await tester.pump();
      final camera = controller.camera;
      expect(camera.center.longitude, closeTo(longitude, 1e-6));
      _expectVerticalCoverage(camera);
      final west = camera.projectAtZoom(const LatLng(0, -180)).dx;
      final east = camera.projectAtZoom(const LatLng(0, 180)).dx;
      if (longitude < 0) {
        expect(camera.pixelBounds.left, lessThan(west));
      } else {
        expect(camera.pixelBounds.right, greaterThan(east));
      }
    }
  });

  testWidgets('resizing updates the minimum before further camera moves', (
    tester,
  ) async {
    final controller = await _pumpExplorer(tester, const Size(390, 844));
    controller.moveAndRotate(const LatLng(85, 179), 1, 45);
    await tester.pump();
    for (final size in [
      const Size(1600, 900),
      const Size(720, 1280),
      const Size(799.5, 601.25),
      const Size(240, 180),
    ]) {
      tester.view.physicalSize = size;
      await tester.pump();
      await tester.pump();
      expect(controller.camera.nonRotatedSize, size);
      _expectMinimumUsable(tester, controller.camera);
      controller.moveAndRotate(const LatLng(85, 179), 1, 45);
      await tester.pump();
      _expectVerticalCoverage(controller.camera);
    }
  });

  testWidgets('Show world uses the current minimum zoom after resizing', (
    tester,
  ) async {
    final controller = await _pumpExplorer(tester, const Size(390, 844));
    tester.view.physicalSize = const Size(1600, 900);
    await tester.pump();
    await tester.pump();
    final layer = tester.widget<MapLibreGpuLayer>(
      find.byType(MapLibreGpuLayer),
    );
    final camera = controller.camera;
    layer.onStyleLoadedCallback!();
    layer.onFrame!(
      gpu.MapFrameState(
        camera: gpu.CameraPosition(
          target: gpu.LatLng(camera.center.latitude, camera.center.longitude),
          zoom: camera.zoom - 1,
          bearing: -camera.rotation,
        ),
        logicalSize: camera.nonRotatedSize,
        physicalSize: camera.nonRotatedSize,
        devicePixelRatio: 1,
        sequence: 1,
      ),
    );
    await tester.pump();
    controller.moveAndRotate(const LatLng(65, 175), 8, 47);
    await tester.pump();
    await tester.tap(find.byTooltip('Show world'));
    await tester.pump();
    expect(controller.camera.center.latitude, closeTo(20, 1e-6));
    expect(controller.camera.center.longitude, closeTo(0, 1e-6));
    expect(controller.camera.rotation, 0);
    expect(
      controller.camera.zoom,
      tester.widget<FlutterMap>(find.byType(FlutterMap)).options.minZoom,
    );
    _expectVerticalCoverage(controller.camera);
  });
}

Future<MapController> _pumpExplorer(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  addTearDown(() async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
  await tester.pumpWidget(const MapExplorerApp());
  await tester.pump();
  expect(tester.takeException(), isNull);

  return tester.widget<FlutterMap>(find.byType(FlutterMap)).mapController!;
}

void _expectMinimumUsable(WidgetTester tester, MapCamera camera) {
  final options = tester.widget<FlutterMap>(find.byType(FlutterMap)).options;
  final minimum = options.minZoom!;
  expect(minimum, greaterThanOrEqualTo(MapLibreGpuLayer.minZoom));
  expect(camera.zoom, greaterThanOrEqualTo(minimum));
  final constrained = options.cameraConstraint.constrain(
    camera.withPosition(zoom: minimum),
  );
  expect(constrained, isNotNull);
  expect(constrained!.zoom, minimum);
  _expectVerticalCoverage(constrained);
}

void _expectVerticalCoverage(MapCamera camera) {
  final north = camera.projectAtZoom(
    const LatLng(MapLibreGpuLayer.maxLatitude, 0),
  );
  final south = camera.projectAtZoom(
    const LatLng(-MapLibreGpuLayer.maxLatitude, 0),
  );
  // MapCamera rounds the center of its culling rectangle to whole pixels.
  const roundingTolerance = 1.0;
  final reason =
      'size=${camera.nonRotatedSize}, rotation=${camera.rotation}, '
      'center=${camera.center}, zoom=${camera.zoom}';
  expect(
    camera.pixelBounds.top,
    greaterThanOrEqualTo(north.dy - roundingTolerance),
    reason: reason,
  );
  expect(
    camera.pixelBounds.bottom,
    lessThanOrEqualTo(south.dy + roundingTolerance),
    reason: reason,
  );
}
