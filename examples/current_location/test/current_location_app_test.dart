import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_current_location_example/main.dart';
import 'package:flutter_map_maplibre_gpu/flutter_map_maplibre_gpu.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

void main() {
  late _FakeGeolocator platform;
  late GeolocatorPlatform originalPlatform;

  Future<MapController> pumpMap(WidgetTester tester) async {
    originalPlatform = GeolocatorPlatform.instance;
    platform = _FakeGeolocator();
    GeolocatorPlatform.instance = platform;
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      GeolocatorPlatform.instance = originalPlatform;
      await platform.close();
    });
    await tester.pumpWidget(const CurrentLocationApp());
    await tester.pump();

    return tester.widget<FlutterMap>(find.byType(FlutterMap)).mapController!;
  }

  testWidgets('shows one location button and forwards position and accuracy', (
    tester,
  ) async {
    final controller = await pumpMap(tester);
    platform.positions.add(_position());
    await tester.pump();
    final layer = tester.widget<MapLibreGpuLayer>(
      find.byType(MapLibreGpuLayer),
    );
    expect(layer.userLocation!.position.latitude, 35);
    expect(layer.userLocation!.position.longitude, 139);
    expect(layer.userLocation!.accuracyMeters, 12);
    expect(layer.userLocation!.headingDegrees, isNull);
    expect(layer.attributionButtonEnabled, isTrue);
    expect(controller.camera.center, const LatLng(35, 139));
    expect(controller.camera.zoom, 16);
    expect(
      find
          .byType(IconButton)
          .evaluate()
          .where(
            (element) =>
                element.findAncestorWidgetOfExactType<MapLibreGpuLayer>() ==
                null,
          ),
      hasLength(1),
    );
    expect(find.byTooltip('Show current location'), findsOneWidget);
    expect(find.byType(Text), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'manual pan stops following until the location button is pressed',
    (tester) async {
      final controller = await pumpMap(tester);
      platform.positions.add(_position());
      await tester.pump();
      final map = tester.widget<FlutterMap>(find.byType(FlutterMap));
      map.options.onPositionChanged!(controller.camera, true);
      controller.move(const LatLng(34, 135), 12);
      await tester.pump();

      platform.positions.add(_position(latitude: 36, longitude: 140));
      await tester.pump();
      expect(controller.camera.center, const LatLng(34, 135));
      final layer = tester.widget<MapLibreGpuLayer>(
        find.byType(MapLibreGpuLayer),
      );
      expect(layer.userLocation!.position.latitude, 36);
      expect(layer.userLocation!.position.longitude, 140);

      await tester.tap(find.byTooltip('Show current location'));
      await tester.pump();
      expect(controller.camera.center, const LatLng(36, 140));
      expect(controller.camera.zoom, 16);
      platform.positions.add(_position(latitude: 36.1, longitude: 140.1));
      await tester.pump();
      expect(controller.camera.center, const LatLng(36.1, 140.1));
    },
  );

  testWidgets(
    'inactive clears the marker and resume checks permission silently',
    (tester) async {
      await pumpMap(tester);
      platform.positions.add(_position());
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(
        tester
            .widget<MapLibreGpuLayer>(find.byType(MapLibreGpuLayer))
            .userLocation,
        isNull,
      );
      expect(platform.positionCancellations, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
      expect(platform.positionSubscriptions, 2);
      expect(platform.permissionRequests, 0);
      platform.positions.add(_position(latitude: 36));
      await tester.pump();
      expect(
        tester
            .widget<MapLibreGpuLayer>(find.byType(MapLibreGpuLayer))
            .userLocation!
            .position
            .latitude,
        36,
      );
    },
  );
}

Position _position({double latitude = 35, double longitude = 139}) => Position(
  latitude: latitude,
  longitude: longitude,
  timestamp: DateTime.utc(2026),
  accuracy: 12,
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
  var permissionRequests = 0;
  var positionSubscriptions = 0;
  var positionCancellations = 0;

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.whileInUse;

  @override
  Future<LocationPermission> requestPermission() async {
    permissionRequests++;

    return LocationPermission.whileInUse;
  }

  @override
  Stream<ServiceStatus> getServiceStatusStream() => services.stream;

  @override
  Stream<Position> getPositionStream({locationSettings}) => positions.stream;

  Future<void> close() async {
    await positions.close();
    await services.close();
  }
}
