import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart' as gpu;

/// A GPU-rendered map whose camera follows its [FlutterMap] ancestor.
///
/// The parent handles camera gestures. Configure it with [Epsg3857], zoom
/// limits of [minZoom] and [maxZoom], and a center within [maxLatitude].
/// MapLibre uses 512-pixel worlds at zoom zero, while Flutter Map uses 256.
/// The native camera therefore receives the parent's zoom minus one and
/// the opposite rotation angle. The layer must fill the parent viewport.
///
/// Sibling layers follow the requested camera and can lead native frames
/// during asynchronous rendering. Use [overlayBuilder] with
/// `FlutterMapGpuAdapter` for overlays that follow the adopted frame.
class MapLibreGpuLayer extends StatelessWidget {
  /// Creates a layer controlled by the nearest [FlutterMap].
  const MapLibreGpuLayer({
    super.key,
    this.styleString = gpu.MapLibreStyles.demo,
    this.onMapCreated,
    this.onStyleLoadedCallback,
    this.onFrame,
    this.overlayBuilder,
    this.userLocation,
    this.userLocationBuilder = gpu.MapLibreMap.defaultUserLocationBuilder,
    this.compassEnabled = false,
    this.attributionButtonEnabled = true,
    this.onAttributionLinkTap,
    this.loadingBuilder = gpu.MapLibreMap.defaultLoadingBuilder,
    this.errorBuilder = gpu.MapLibreMap.defaultErrorBuilder,
  });

  /// The lowest Flutter Map zoom supported by the native camera.
  static const minZoom = 1.0;

  /// The highest Flutter Map zoom supported by the native camera.
  static const maxZoom = 26.5;

  /// The absolute latitude limit of the Web Mercator projection, in degrees.
  static const maxLatitude = 85.0511287798066;

  /// A style URL, raw JSON document, local file, or Flutter asset path.
  final String styleString;

  /// Receives the controller owned by the GPU map.
  ///
  /// Use it for style operations and queries. Camera mutations throw because
  /// [FlutterMap] owns the camera. Do not dispose this controller.
  final gpu.MapCreatedCallback? onMapCreated;

  /// Runs after the initial style loads and after each style replacement.
  final gpu.OnStyleLoadedCallback? onStyleLoadedCallback;

  /// Reports the camera and viewport adopted for native frame rendering.
  ///
  /// This does not confirm GPU submission or presentation on screen.
  final gpu.OnMapFrameCallback? onFrame;

  /// Builds overlays from the adopted frame above symbols and below controls.
  ///
  /// Wrap Flutter Map layers in `FlutterMapGpuAdapter` here so their camera
  /// matches the map frame. Returning null hides the overlay.
  final gpu.MapOverlayWidgetBuilder? overlayBuilder;

  /// The location displayed above map symbols.
  ///
  /// The application owns location acquisition. Null hides the marker.
  final gpu.MapUserLocation? userLocation;

  /// Builds the location marker using the adopted map frame.
  ///
  /// Null hides the location marker.
  final gpu.MapUserLocationWidgetBuilder? userLocationBuilder;

  /// Whether to display a compass indicating the adopted camera bearing.
  ///
  /// Its reset action is disabled because the parent owns the camera.
  final bool compassEnabled;

  /// Whether to show the native style's attribution button.
  ///
  /// When disabled, the application must provide the required attribution.
  final bool attributionButtonEnabled;

  /// Handles links selected from the attribution dialog.
  final gpu.AttributionLinkCallback? onAttributionLinkTap;

  /// Builds a loading indicator while the style is loading.
  ///
  /// Null hides the indicator.
  final gpu.MapLoadingWidgetBuilder? loadingBuilder;

  /// Builds the view shown when native initialization fails.
  ///
  /// Null hides the error view.
  final gpu.MapErrorWidgetBuilder? errorBuilder;

  @override
  Widget build(context) {
    final camera = MapCamera.of(context);
    if (camera.crs.runtimeType != Epsg3857) {
      throw UnsupportedError('MapLibreGpuLayer requires the Epsg3857 CRS.');
    }
    if (!camera.zoom.isFinite ||
        camera.zoom < minZoom ||
        camera.zoom > maxZoom) {
      throw ArgumentError.value(
        camera.zoom,
        'zoom',
        'Set FlutterMap zoom limits within $minZoom and $maxZoom.',
      );
    }
    if (!camera.center.latitude.isFinite ||
        camera.center.latitude.abs() > maxLatitude ||
        !camera.center.longitude.isFinite ||
        !camera.rotation.isFinite) {
      throw ArgumentError(
        'MapLibreGpuLayer requires a finite Web Mercator camera with '
        'latitude between -$maxLatitude and $maxLatitude.',
      );
    }
    return gpu.MapLibreMap(
      cameraPosition: gpu.CameraPosition(
        target: gpu.LatLng(camera.center.latitude, camera.center.longitude),
        zoom: camera.zoom - 1,
        bearing: -camera.rotation,
      ),
      cameraConstrainMode: gpu.CameraConstrainMode.none,
      minMaxTiltPreference: const gpu.MinMaxTiltPreference(0, 0),
      styleString: styleString,
      onMapCreated: onMapCreated,
      onStyleLoadedCallback: onStyleLoadedCallback,
      onFrame: onFrame,
      overlayBuilder: overlayBuilder,
      userLocation: userLocation,
      userLocationBuilder: userLocationBuilder,
      compassEnabled: compassEnabled,
      attributionButtonEnabled: attributionButtonEnabled,
      onAttributionLinkTap: onAttributionLinkTap,
      loadingBuilder: loadingBuilder,
      errorBuilder: errorBuilder,
    );
  }
}
