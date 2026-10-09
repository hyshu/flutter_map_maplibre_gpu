import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
import 'package:flutter_map_maplibre_gpu/src/flutter_map_gpu_adapter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart' as gpu;

gpu.MapFrameState frame({
  double latitude = 0,
  double longitude = 0,
  double zoom = 2,
  double bearing = 0,
  double tilt = 0,
  Size size = const Size(400, 300),
  int sequence = 1,
}) => gpu.MapFrameState(
  camera: gpu.CameraPosition(
    target: gpu.LatLng(latitude, longitude),
    zoom: zoom,
    bearing: bearing,
    tilt: tilt,
  ),
  logicalSize: size,
  physicalSize: const Size(1201, 899),
  devicePixelRatio: 3,
  sequence: sequence,
);

Widget host(Widget child, {Size size = const Size(400, 300)}) => Directionality(
  textDirection: TextDirection.ltr,
  child: Align(
    alignment: Alignment.topLeft,
    child: SizedBox.fromSize(size: size, child: child),
  ),
);

void main() {
  testWidgets('provides the frame camera instead of an outer map camera', (
    tester,
  ) async {
    fm.MapCamera? camera;
    fm.MapController? controller;
    fm.MapOptions? options;
    final snapshot = frame(
      latitude: 35.5,
      longitude: 139.75,
      zoom: 9.25,
      bearing: 37,
    );
    await tester.pumpWidget(
      host(
        fm.FlutterMap(
          options: const fm.MapOptions(initialZoom: 3),
          children: [
            FlutterMapGpuAdapter(
              frame: snapshot,
              child: Builder(
                builder: (context) {
                  camera = fm.MapCamera.of(context);
                  controller = fm.MapController.of(context);
                  options = fm.MapOptions.of(context);

                  return const SizedBox.expand();
                },
              ),
            ),
          ],
        ),
      ),
    );

    expect(camera!.center, const LatLng(35.5, 139.75));
    expect(camera!.zoom, 10.25);
    expect(camera!.rotation, -37);
    expect(camera!.nonRotatedSize, snapshot.logicalSize);
    expect(camera!.crs, isA<fm.Epsg3857>());
    expect(controller!.camera, same(camera));
    expect(options!.interactionOptions.flags, fm.InteractiveFlag.none);
  });

  testWidgets('updates the frame synchronously and retains child state', (
    tester,
  ) async {
    final childKey = GlobalKey<_CameraProbeState>();
    final child = _CameraProbe(key: childKey);
    await tester.pumpWidget(
      host(FlutterMapGpuAdapter(frame: frame(), child: child)),
    );
    final state = childKey.currentState!;
    final firstCamera = state.camera;
    final controller = state.controller;

    await tester.pumpWidget(
      host(
        FlutterMapGpuAdapter(
          frame: frame(
            latitude: 45,
            longitude: -120,
            zoom: 6,
            bearing: 135,
            sequence: 2,
          ),
          child: child,
        ),
      ),
    );

    expect(childKey.currentState, same(state));
    expect(state.controller, same(controller));
    expect(state.camera, same(controller.camera));
    expect(state.camera.center, const LatLng(45, -120));
    expect(state.camera.zoom, 7);
    expect(state.camera.rotation, -135);
    expect(firstCamera.center, const LatLng(0, 0));
    expect(firstCamera.zoom, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'scales the frame canvas with the native image while a resize is pending',
    (tester) async {
      const viewportKey = Key('viewport');
      const markerKey = Key('marker');
      const layer = fm.MarkerLayer(
        markers: [
          fm.Marker(
            point: LatLng(0, 0),
            width: 10,
            height: 10,
            child: SizedBox(key: markerKey),
          ),
        ],
      );
      final child = SizedBox.expand(key: viewportKey, child: layer);
      await tester.pumpWidget(
        host(
          FlutterMapGpuAdapter(
            frame: frame(size: const Size(320, 240)),
            child: child,
          ),
          size: const Size(600, 400),
        ),
      );

      expect(tester.getSize(find.byKey(viewportKey)), const Size(320, 240));
      expect(tester.getTopLeft(find.byKey(viewportKey)), Offset.zero);
      expect(
        (tester.getCenter(find.byKey(markerKey)) - const Offset(300, 200))
            .distance,
        closeTo(0, 0.000001),
      );
      expect(
        fm.MapCamera.of(tester.element(find.byKey(viewportKey))).nonRotatedSize,
        const Size(320, 240),
      );

      await tester.pumpWidget(
        host(
          FlutterMapGpuAdapter(
            frame: frame(size: const Size(320, 240)),
            child: child,
          ),
          size: const Size(250, 180),
        ),
      );
      expect(tester.getSize(find.byKey(viewportKey)), const Size(320, 240));
      expect(
        (tester.getCenter(find.byKey(markerKey)) - const Offset(125, 90))
            .distance,
        closeTo(0, 0.000001),
      );

      await tester.pumpWidget(
        host(
          FlutterMapGpuAdapter(
            frame: frame(size: const Size(250, 180), sequence: 2),
            child: child,
          ),
          size: const Size(250, 180),
        ),
      );
      expect(tester.getSize(find.byKey(viewportKey)), const Size(250, 180));
      expect(tester.getCenter(find.byKey(markerKey)), const Offset(125, 90));
    },
  );

  testWidgets(
    'scales projection and marker hit testing to a fractional layout',
    (tester) async {
      const markerKey = Key('fractional marker');
      const layoutSize = Size(600.75, 150.25);
      var taps = 0;
      fm.MapCamera? camera;
      await tester.pumpWidget(
        host(
          FlutterMapGpuAdapter(
            frame: frame(),
            child: Builder(
              builder: (context) {
                camera = fm.MapCamera.of(context);

                return fm.MarkerLayer(
                  markers: [
                    fm.Marker(
                      point: const LatLng(0, 11.25),
                      width: 40,
                      height: 40,
                      child: GestureDetector(
                        key: markerKey,
                        behavior: HitTestBehavior.opaque,
                        onTap: () => taps++,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          size: layoutSize,
        ),
      );

      expect(camera!.nonRotatedSize, const Size(400, 300));
      final center = tester.getCenter(find.byKey(markerKey));
      expect(center.dx, closeTo(264 * layoutSize.width / 400, 0.000001));
      expect(center.dy, closeTo(150 * layoutSize.height / 300, 0.000001));
      final topLeft = tester.getTopLeft(find.byKey(markerKey));
      final bottomRight = tester.getBottomRight(find.byKey(markerKey));
      expect(
        bottomRight.dx - topLeft.dx,
        closeTo(40 * layoutSize.width / 400, 0.000001),
      );
      expect(
        bottomRight.dy - topLeft.dy,
        closeTo(40 * layoutSize.height / 300, 0.000001),
      );

      await tester.tapAt(Offset(bottomRight.dx - 1, center.dy));
      expect(taps, 1);
      await tester.tapAt(Offset(bottomRight.dx + 1, center.dy));
      expect(taps, 1);
    },
  );

  testWidgets('does not build layer content in a zero viewport', (
    tester,
  ) async {
    var builds = 0;
    await tester.pumpWidget(
      host(
        FlutterMapGpuAdapter(
          frame: frame(),
          child: Builder(
            builder: (context) {
              builds++;

              return const SizedBox.expand();
            },
          ),
        ),
        size: Size.zero,
      ),
    );

    expect(builds, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('does not build layer content with unbounded constraints', (
    tester,
  ) async {
    var builds = 0;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: UnconstrainedBox(
          child: FlutterMapGpuAdapter(
            frame: frame(),
            child: Builder(
              builder: (context) {
                builds++;

                return const SizedBox.expand();
              },
            ),
          ),
        ),
      ),
    );

    expect(builds, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rotates marker geometry once with the native bearing', (
    tester,
  ) async {
    const markerKey = Key('rotated marker');
    await tester.pumpWidget(
      host(
        FlutterMapGpuAdapter(
          frame: frame(bearing: 90),
          child: const fm.MarkerLayer(
            markers: [
              fm.Marker(
                point: LatLng(0, 11.25),
                width: 10,
                height: 10,
                child: SizedBox(key: markerKey),
              ),
            ],
          ),
        ),
      ),
    );

    final position = tester.getCenter(find.byKey(markerKey));
    expect(position.dx, closeTo(200, 0.000001));
    expect(position.dy, closeTo(86, 0.000001));
  });

  testWidgets('keeps a marker next to the camera across the antimeridian', (
    tester,
  ) async {
    const markerKey = Key('wrapped marker');
    await tester.pumpWidget(
      host(
        FlutterMapGpuAdapter(
          frame: frame(longitude: 179),
          child: const fm.MarkerLayer(
            markers: [
              fm.Marker(
                point: LatLng(0, -179),
                width: 10,
                height: 10,
                child: SizedBox(key: markerKey),
              ),
            ],
          ),
        ),
      ),
    );

    final position = tester.getCenter(find.byKey(markerKey));
    expect(position.dx, closeTo(200 + 2048 * 2 / 360, 0.000001));
    expect(position.dy, closeTo(150, 0.000001));
  });

  testWidgets(
    'keeps tooltip inheritance valid through frame changes and remounts',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      const points = [
        LatLng(0, 0),
        LatLng(0, 179),
        LatLng(0, -179),
        LatLng(35.68, 139.69),
      ];
      var taps = 0;

      Future<void> show(
        gpu.MapFrameState snapshot, {
        Size layoutSize = const Size(1200, 500),
        Key adapterKey = const ValueKey('map'),
      }) async {
        final markerSize = (12 + snapshot.camera.zoom * 2)
            .clamp(12, 32)
            .toDouble();
        await tester.pumpWidget(
          MaterialApp(
            themeAnimationDuration: Duration.zero,
            theme: ThemeData(
              brightness: snapshot.sequence.isEven
                  ? Brightness.dark
                  : Brightness.light,
              colorSchemeSeed: snapshot.sequence.isEven
                  ? Colors.teal
                  : Colors.blue,
            ),
            home: Scaffold(
              body: host(
                FlutterMapGpuAdapter(
                  key: adapterKey,
                  frame: snapshot,
                  child: fm.MarkerLayer(
                    markers: [
                      for (final (index, point) in points.indexed)
                        fm.Marker(
                          point: point,
                          width: markerSize,
                          height: markerSize,
                          rotate: true,
                          child: Tooltip(
                            message: 'city $index',
                            child: Builder(
                              builder: (context) => GestureDetector(
                                onTap: () => taps++,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const SizedBox.expand(),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                size: layoutSize,
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
      }

      await show(frame(zoom: 0, size: const Size(1200, 400)));
      final centerTooltips = find.byWidgetPredicate(
        (widget) => widget is Tooltip && widget.message == 'city 0',
      );
      expect(centerTooltips.evaluate().length, greaterThan(1));
      expect(
        tester.state<TooltipState>(centerTooltips.first).ensureTooltipVisible(),
        isTrue,
      );
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('city 0'), findsOneWidget);

      await show(
        frame(
          longitude: 179,
          zoom: 1,
          bearing: 35,
          size: const Size(1200, 400),
          sequence: 2,
        ),
        layoutSize: const Size(600, 500),
      );
      await show(
        frame(
          latitude: 35.68,
          longitude: 139.69,
          zoom: 6,
          bearing: 120,
          size: const Size(600, 500),
          sequence: 3,
        ),
        layoutSize: const Size(900, 600),
      );
      final cityTooltip = find.byWidgetPredicate(
        (widget) => widget is Tooltip && widget.message == 'city 3',
      );
      expect(cityTooltip, findsOneWidget);
      await tester.tap(cityTooltip);
      expect(taps, 1);
      expect(
        tester.state<TooltipState>(cityTooltip).ensureTooltipVisible(),
        isTrue,
      );
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('city 3'), findsOneWidget);

      await show(
        frame(
          longitude: -179,
          zoom: 4,
          bearing: 270,
          size: const Size(900, 600),
          sequence: 4,
        ),
        layoutSize: const Size(500, 300),
      );
      await show(
        frame(
          latitude: 70,
          longitude: -40,
          zoom: 10,
          bearing: -45,
          sequence: 5,
        ),
      );
      expect(find.byType(Tooltip), findsNothing);
      await show(frame(zoom: 0, size: const Size(1200, 400), sequence: 6));
      expect(centerTooltips.evaluate().length, greaterThan(1));
      expect(
        tester.state<TooltipState>(centerTooltips.first).ensureTooltipVisible(),
        isTrue,
      );
      await tester.pump(const Duration(milliseconds: 250));
      await show(
        frame(zoom: 0, size: const Size(1200, 400), sequence: 7),
        adapterKey: const ValueKey('replacement map'),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('lets interactive markers receive taps and passes empty space', (
    tester,
  ) async {
    var markerTaps = 0;
    var backgroundTaps = 0;
    await tester.pumpWidget(
      host(
        Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => backgroundTaps++,
            ),
            FlutterMapGpuAdapter(
              frame: frame(),
              child: fm.MarkerLayer(
                markers: [
                  fm.Marker(
                    point: const LatLng(0, 0),
                    width: 40,
                    height: 40,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => markerTaps++,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    await tester.tapAt(const Offset(200, 150));
    expect(markerTaps, 1);
    expect(backgroundTaps, 0);

    await tester.tapAt(const Offset(20, 20));
    expect(markerTaps, 1);
    expect(backgroundTaps, 1);
  });

  testWidgets('owns a read-only controller with an empty stream', (
    tester,
  ) async {
    late fm.MapController controller;
    await tester.pumpWidget(
      host(
        FlutterMapGpuAdapter(
          frame: frame(),
          child: Builder(
            builder: (context) {
              controller = fm.MapController.of(context);

              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );

    expect(
      () => controller.move(const LatLng(0, 0), 4),
      throwsUnsupportedError,
    );
    expect(() => controller.rotate(45), throwsUnsupportedError);
    expect(() => controller.rotateAroundPoint(45), throwsUnsupportedError);
    expect(
      () => controller.moveAndRotate(const LatLng(0, 0), 4, 45),
      throwsUnsupportedError,
    );
    expect(
      () => controller.fitCamera(
        fm.CameraFit.bounds(
          bounds: fm.LatLngBounds(const LatLng(0, 0), const LatLng(1, 1)),
        ),
      ),
      throwsUnsupportedError,
    );
    await expectLater(controller.mapEventStream, emitsDone);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(() => controller.camera, throwsStateError);
  });

  for (final size in [
    Size.zero,
    const Size(-1, 10),
    const Size(10, double.infinity),
    const Size(double.nan, 10),
  ]) {
    testWidgets('rejects invalid native logical viewport $size', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          FlutterMapGpuAdapter(
            frame: frame(size: size),
            child: const SizedBox.shrink(),
          ),
        ),
      );
      expect(tester.takeException(), isArgumentError);
    });
  }

  testWidgets('rejects tilted frames instead of misprojecting flat layers', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(
        FlutterMapGpuAdapter(
          frame: frame(tilt: 20),
          child: const SizedBox.shrink(),
        ),
      ),
    );
    expect(tester.takeException(), isUnsupportedError);
  });

  testWidgets('rejects non-finite camera values', (tester) async {
    await tester.pumpWidget(
      host(
        FlutterMapGpuAdapter(
          frame: frame(bearing: double.nan),
          child: const SizedBox.shrink(),
        ),
      ),
    );
    expect(tester.takeException(), isArgumentError);
  });
}

class _CameraProbe extends StatefulWidget {
  const _CameraProbe({super.key});

  @override
  State<_CameraProbe> createState() => _CameraProbeState();
}

class _CameraProbeState extends State<_CameraProbe> {
  late fm.MapCamera camera;
  late fm.MapController controller;

  @override
  Widget build(context) {
    camera = fm.MapCamera.of(context);
    controller = fm.MapController.of(context);

    return const SizedBox.expand();
  }
}
