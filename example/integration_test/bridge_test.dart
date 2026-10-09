import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_maplibre_gpu/flutter_map_maplibre_gpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart' as gpu;

const _style =
    '{"version":8,"sources":{},"layers":['
    '{"id":"background","type":"background",'
    '"paint":{"background-color":"#eeeeee"}}]}';
const _replacementStyle =
    '{"version":8,"sources":{},"layers":['
    '{"id":"background","type":"background",'
    '"paint":{"background-color":"#ddddff"}}]}';
const _viewportKey = ValueKey('map-viewport');
const _markerKey = ValueKey('frame-marker');
const _markerPoint = LatLng(35.72, 139.82);
const _cameraTolerance = 0.0001;

bool _near(double actual, double expected) =>
    (actual - expected).abs() < _cameraTolerance;

bool _sameAngle(double actual, double expected) =>
    _near((actual - expected + 180) % 360, 180);

bool _matchesCamera(gpu.CameraPosition? actual, gpu.CameraPosition expected) =>
    actual != null &&
    _near(actual.target.latitude, expected.target.latitude) &&
    _near(actual.target.longitude, expected.target.longitude) &&
    _near(actual.zoom, expected.zoom) &&
    _sameAngle(actual.bearing, expected.bearing) &&
    _near(actual.tilt, expected.tilt);

bool _matchesFlutterMap(gpu.MapFrameState? frame, MapCamera camera) =>
    _matchesCamera(
      frame?.camera,
      gpu.CameraPosition(
        target: gpu.LatLng(camera.center.latitude, camera.center.longitude),
        zoom: camera.zoom - 1,
        bearing: -camera.rotation,
      ),
    );

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  required String reason,
  String Function()? describeState,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (!done() && DateTime.now().isBefore(deadline)) {
    await tester
        .pump(const Duration(milliseconds: 50))
        .timeout(
          const Duration(seconds: 20),
          onTimeout: () => throw TestFailure(
            'Frame pump timed out. $reason ${describeState?.call()}',
          ),
        );
    expect(tester.takeException(), isNull);
  }
  expect(
    done(),
    isTrue,
    reason: describeState == null ? reason : '$reason ${describeState()}',
  );
}

Future<void> _expectMarkerProjection(
  WidgetTester tester,
  gpu.MapLibreMapController controller, {
  double tolerance = 1,
}) async {
  final projected = await controller.toScreenLocation(
    const gpu.LatLng(35.72, 139.82),
  );
  final marker = find.byKey(_markerKey);
  expect(marker, findsOneWidget);
  final viewport = find.byKey(_viewportKey);
  final layoutSize = tester.getSize(viewport);
  final nativeSize = controller.frameState!.logicalSize;
  final actual = tester.getCenter(marker) - tester.getTopLeft(viewport);
  expect(
    actual.dx,
    closeTo(projected.x * layoutSize.width / nativeSize.width, tolerance),
  );
  expect(
    actual.dy,
    closeTo(projected.y * layoutSize.height / nativeSize.height, tolerance),
  );
}

Widget _marker(VoidCallback onTap) => MarkerLayer(
  markers: [
    Marker(
      point: _markerPoint,
      width: 24,
      height: 24,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: const ColoredBox(key: _markerKey, color: Color(0xFFDC2626)),
      ),
    ),
  ],
);

Future<void> _verifyFlutterMapDrivenLayer(WidgetTester tester) async {
  final mapController = MapController();
  gpu.MapLibreMapController? gpuController;
  gpu.MapFrameState? overlayFrame;
  var creationCount = 0;
  var loadedStyles = 0;
  var markerTaps = 0;
  var mapTaps = 0;
  var size = const Size(300, 260);
  var style = _style;
  late StateSetter rebuild;
  addTearDown(mapController.dispose);

  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: StatefulBuilder(
        builder: (context, setState) {
          rebuild = setState;

          return Center(
            child: SizedBox(
              key: _viewportKey,
              width: size.width,
              height: size.height,
              child: FlutterMap(
                mapController: mapController,
                options: MapOptions(
                  initialCenter: const LatLng(35.68, 139.76),
                  initialZoom: 8.25,
                  initialRotation: 27,
                  interactionOptions: const InteractionOptions(
                    flags: InteractiveFlag.drag,
                  ),
                  onTap: (position, point) => mapTaps++,
                ),
                children: [
                  MapLibreGpuLayer(
                    styleString: style,
                    compassEnabled: false,
                    attributionButtonEnabled: false,
                    onMapCreated: (controller) {
                      gpuController = controller;
                      creationCount++;
                    },
                    onStyleLoadedCallback: () => loadedStyles++,
                    onFrame: (frame) {
                      expectSync(gpuController!.frameState, same(frame));
                    },
                    overlayBuilder: (context, frame) {
                      overlayFrame = frame;

                      return FlutterMapGpuAdapter(
                        frame: frame,
                        child: _marker(() => markerTaps++),
                      );
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );

  String describeState() =>
      'loadedStyles=$loadedStyles, native=${gpuController?.frameState}, '
      'overlay=$overlayFrame, parentCenter=${mapController.camera.center}, '
      'parentZoom=${mapController.camera.zoom}, '
      'parentRotation=${mapController.camera.rotation}, layout=$size, '
      'lifecycle=${tester.binding.lifecycleState}, '
      'framesEnabled=${tester.binding.framesEnabled}';

  bool currentFrameIsDisplayed() =>
      _matchesFlutterMap(gpuController?.frameState, mapController.camera) &&
      gpuController?.frameState?.logicalSize ==
          Size(size.width.floorToDouble(), size.height.floorToDouble()) &&
      overlayFrame?.sequence == gpuController?.frameState?.sequence;

  await _pumpUntil(
    tester,
    () => loadedStyles == 1 && currentFrameIsDisplayed(),
    reason: 'Initial zoom and rotation must reach the native map.',
    describeState: describeState,
  );
  expect(gpuController!.frameState!.camera.zoom, closeTo(7.25, 0.0001));
  expect(_sameAngle(gpuController!.frameState!.camera.bearing, -27), isTrue);
  await _expectMarkerProjection(tester, gpuController!);
  await tester.tap(find.byKey(_markerKey));
  await tester.pump(const Duration(milliseconds: 350));
  expect(markerTaps, 1);
  expect(mapTaps, 0);

  final initialController = gpuController;
  final firstSequence = gpuController!.frameState!.sequence;
  mapController.moveAndRotate(const LatLng(35.70, 139.78), 9.5, -43);
  await _pumpUntil(
    tester,
    () =>
        currentFrameIsDisplayed() &&
        gpuController!.frameState!.sequence > firstSequence,
    reason: 'Programmatic camera movement must update the same native map.',
    describeState: describeState,
  );
  await _expectMarkerProjection(tester, gpuController!);

  final resizeSequence = gpuController!.frameState!.sequence;
  rebuild(() => size = const Size(260, 320));
  await _pumpUntil(
    tester,
    () =>
        currentFrameIsDisplayed() &&
        gpuController!.frameState!.sequence > resizeSequence,
    reason: 'Resizing must preserve camera alignment and update frame size.',
    describeState: describeState,
  );
  await _expectMarkerProjection(tester, gpuController!);

  final fractionalResizeSequence = gpuController!.frameState!.sequence;
  rebuild(() => size = const Size(261.75, 321.25));
  await _pumpUntil(
    tester,
    () =>
        currentFrameIsDisplayed() &&
        gpuController!.frameState!.sequence > fractionalResizeSequence,
    reason: 'Fractional layouts must scale the native frame and its overlay.',
    describeState: describeState,
  );
  await _expectMarkerProjection(tester, gpuController!, tolerance: 0.1);

  rebuild(() => style = _replacementStyle);
  await _pumpUntil(
    tester,
    () => loadedStyles == 2 && currentFrameIsDisplayed(),
    reason: 'Replacing the style must preserve the parent camera.',
    describeState: describeState,
  );
  await _expectMarkerProjection(tester, gpuController!);

  final previousCenter = mapController.camera.center;
  final mapOrigin = tester.getTopLeft(find.byKey(_viewportKey));
  await tester.dragFrom(mapOrigin + const Offset(40, 40), const Offset(32, 18));
  await _pumpUntil(
    tester,
    () =>
        mapController.camera.center != previousCenter &&
        currentFrameIsDisplayed(),
    reason: 'Pointer dragging must reach FlutterMap through the GPU layer.',
    describeState: describeState,
  );
  await _expectMarkerProjection(tester, gpuController!);
  await tester.tapAt(mapOrigin + const Offset(20, 20));
  await tester.pump(const Duration(milliseconds: 350));
  expect(mapTaps, 1);
  expect(creationCount, 1);
  expect(gpuController, same(initialController));
}

Future<void> _verifyNativeDrivenAdapter(WidgetTester tester) async {
  const initial = gpu.CameraPosition(
    target: gpu.LatLng(35.68, 139.76),
    zoom: 7.6,
    bearing: 48,
  );
  const latest = gpu.CameraPosition(
    target: gpu.LatLng(35.70, 139.77),
    zoom: 8,
    bearing: -32,
  );
  gpu.MapLibreMapController? controller;
  gpu.MapFrameState? overlayFrame;
  MapCamera? overlayCamera;
  var markerTaps = 0;
  var loaded = false;

  await tester
      .pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(
            child: SizedBox(
              key: _viewportKey,
              width: 300,
              height: 280,
              child: gpu.MapLibreMap(
                styleString: _style,
                initialCameraPosition: initial,
                cameraConstrainMode: gpu.CameraConstrainMode.none,
                minMaxTiltPreference: const gpu.MinMaxTiltPreference(0, 0),
                compassEnabled: false,
                logoEnabled: false,
                attributionButtonEnabled: false,
                loadingBuilder: null,
                onMapCreated: (value) => controller = value,
                onStyleLoadedCallback: () => loaded = true,
                overlayBuilder: (context, frame) {
                  overlayFrame = frame;

                  return FlutterMapGpuAdapter(
                    frame: frame,
                    child: Builder(
                      builder: (context) {
                        overlayCamera = MapCamera.of(context);

                        return _marker(() => markerTaps++);
                      },
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      )
      .timeout(
        const Duration(seconds: 20),
        onTimeout: () => throw TestFailure(
          'Standalone pumpWidget timed out. lifecycle=${tester.binding.lifecycleState} '
          'framesEnabled=${tester.binding.framesEnabled}',
        ),
      );

  bool overlayMatchesFrame() =>
      overlayCamera != null &&
      overlayFrame?.sequence == controller?.frameState?.sequence &&
      _matchesFlutterMap(controller?.frameState, overlayCamera!);

  String describeState() =>
      'loaded=$loaded, native=${controller?.frameState}, '
      'overlay=$overlayFrame, inheritedCenter=${overlayCamera?.center}, '
      'inheritedZoom=${overlayCamera?.zoom}, '
      'inheritedRotation=${overlayCamera?.rotation}, '
      'lifecycle=${tester.binding.lifecycleState}, framesEnabled=${tester.binding.framesEnabled}';

  await _pumpUntil(
    tester,
    () =>
        loaded &&
        _matchesCamera(controller?.frameState?.camera, initial) &&
        overlayMatchesFrame(),
    reason: 'A standalone adapter must inherit the adopted native frame.',
    describeState: describeState,
  );
  final firstFrame = controller!.frameState!;
  await _expectMarkerProjection(tester, controller!);

  await controller!.moveCamera(
    gpu.CameraUpdate.newCameraPosition(
      const gpu.CameraPosition(
        target: gpu.LatLng(35.69, 139.75),
        zoom: 7.8,
        bearing: 15,
      ),
    ),
  );
  await controller!.moveCamera(gpu.CameraUpdate.newCameraPosition(latest));
  await _pumpUntil(
    tester,
    () =>
        _matchesCamera(controller?.frameState?.camera, latest) &&
        controller!.frameState!.sequence > firstFrame.sequence &&
        overlayMatchesFrame(),
    reason: 'The overlay must follow the latest adopted camera and frame.',
    describeState: describeState,
  );
  expect(_matchesCamera(firstFrame.camera, initial), isTrue);
  expect(overlayFrame, same(controller!.frameState));
  await _expectMarkerProjection(tester, controller!);
  await tester.tap(find.byKey(_markerKey));
  await tester.pump(const Duration(milliseconds: 350));
  expect(markerTaps, 1);
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.onlyPumps;

  testWidgets('GPU bridge supports both camera owners across remounts', (
    tester,
  ) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    });
    await _verifyFlutterMapDrivenLayer(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await _verifyNativeDrivenAdapter(tester);
  });
}
