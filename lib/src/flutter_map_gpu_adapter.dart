import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart' as fm;
// flutter_map does not expose a public scope for an externally owned camera.
// ignore: implementation_imports
import 'package:flutter_map/src/map/inherited_model.dart' as fm;
import 'package:latlong2/latlong.dart';
import 'package:maplibre_flutter_gpu/maplibre_flutter_gpu.dart' as gpu;

/// Places flutter_map layers over the native frame supplied by [frame].
///
/// Use this widget from [gpu.MapLibreMap.overlayBuilder]. Configure the native
/// map with a zero maximum tilt because flutter_map layers use a flat Mercator
/// projection. Tilted frames throw [UnsupportedError].
///
/// Descendants can query [fm.MapCamera], [fm.MapOptions], and [fm.MapController].
/// The adapter owns the controller, which exposes the current frame camera and
/// rejects camera changes with [UnsupportedError]. Its event stream is empty.
/// Drive the native map through its own controller or camera input instead.
///
/// Layer content uses the frame's logical viewport, then scales to the current
/// layout to match the native map image during resizing and fractional layouts.
/// Interactive children can receive pointer events. Empty or unbounded layouts
/// do not build layer content.
class FlutterMapGpuAdapter extends StatefulWidget {
  /// Creates a frame-driven scope for flutter_map layers.
  const FlutterMapGpuAdapter({
    required this.frame,
    required this.child,
    super.key,
  });

  /// The adopted native frame whose projection the layers must follow.
  ///
  /// Its camera values must be finite. Its logical viewport must be finite
  /// and strictly positive in both dimensions.
  final gpu.MapFrameState frame;

  /// A flutter_map layer or a stack containing multiple layers.
  ///
  /// Layers apply their own map rotation. Do not wrap ordinary layers with
  /// another [fm.MobileLayerTransformer].
  final Widget child;

  @override
  State<FlutterMapGpuAdapter> createState() => _FlutterMapGpuAdapterState();
}

class _FlutterMapGpuAdapterState extends State<FlutterMapGpuAdapter> {
  static const _options = fm.MapOptions(
    interactionOptions: fm.InteractionOptions(flags: fm.InteractiveFlag.none),
  );

  late fm.MapCamera _camera;
  late final _FrameMapController _controller;

  @override
  void initState() {
    super.initState();
    _camera = _cameraForFrame(widget.frame);
    _controller = _FrameMapController(_camera);
  }

  @override
  void didUpdateWidget(FlutterMapGpuAdapter oldWidget) {
    super.didUpdateWidget(oldWidget);
    _camera = _cameraForFrame(widget.frame);
    _controller._camera = _camera;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(context) => LayoutBuilder(
    builder: (context, constraints) {
      final size = constraints.biggest;
      if (!size.width.isFinite ||
          !size.height.isFinite ||
          size.width <= 0 ||
          size.height <= 0) {
        return const SizedBox.shrink();
      }
      return ClipRect(
        child: SizedBox.fromSize(
          size: size,
          child: FittedBox(
            fit: BoxFit.fill,
            alignment: Alignment.topLeft,
            child: SizedBox.fromSize(
              size: _camera.nonRotatedSize,
              child: fm.MapInheritedModel(
                camera: _camera,
                options: _options,
                controller: _controller,
                child: widget.child,
              ),
            ),
          ),
        ),
      );
    },
  );
}

fm.MapCamera _cameraForFrame(gpu.MapFrameState frame) {
  final camera = frame.camera;
  final size = frame.logicalSize;
  if (!size.width.isFinite ||
      !size.height.isFinite ||
      size.width <= 0 ||
      size.height <= 0) {
    throw ArgumentError.value(
      size,
      'frame.logicalSize',
      'Must be positive and finite',
    );
  }
  if (!camera.target.latitude.isFinite ||
      !camera.target.longitude.isFinite ||
      !camera.zoom.isFinite ||
      !camera.bearing.isFinite ||
      !camera.tilt.isFinite) {
    throw ArgumentError.value(
      camera,
      'frame.camera',
      'Must contain finite values',
    );
  }
  if (camera.tilt != 0) {
    throw UnsupportedError(
      'FlutterMapGpuAdapter requires a camera tilt of zero.',
    );
  }
  return fm.MapCamera(
    crs: const fm.Epsg3857(),
    center: LatLng(camera.target.latitude, camera.target.longitude),
    zoom: camera.zoom + 1,
    rotation: -camera.bearing,
    nonRotatedSize: size,
  );
}

class _FrameMapController implements fm.MapController {
  _FrameMapController(this._camera);

  fm.MapCamera _camera;
  var _disposed = false;

  @override
  fm.MapCamera get camera {
    if (_disposed) throw StateError('The frame controller has been disposed.');

    return _camera;
  }

  @override
  Stream<fm.MapEvent> get mapEventStream => const Stream.empty();

  Never _rejectMutation() => throw UnsupportedError(
    'The frame controller is read-only. Move the MapLibreMap camera instead.',
  );

  @override
  bool move(
    LatLng center,
    double zoom, {
    Offset offset = Offset.zero,
    String? id,
  }) => _rejectMutation();

  @override
  bool rotate(double degree, {String? id}) => _rejectMutation();

  @override
  ({bool moveSuccess, bool rotateSuccess}) rotateAroundPoint(
    double degree, {
    Offset? offset,
    String? id,
  }) => _rejectMutation();

  @override
  ({bool moveSuccess, bool rotateSuccess}) moveAndRotate(
    LatLng center,
    double zoom,
    double degree, {
    String? id,
  }) => _rejectMutation();

  @override
  bool fitCamera(fm.CameraFit cameraFit) => _rejectMutation();

  @override
  void dispose() {
    _disposed = true;
  }
}
