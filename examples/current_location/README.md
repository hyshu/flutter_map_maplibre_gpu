# Current location

A full-screen OpenFreeMap map with a location marker, accuracy area, and one
current-location button. Uses [Geolocator](https://pub.dev/packages/geolocator)
to supply fixes to `MapLibreGpuLayer.userLocation`.

## Run

Requires Flutter 3.47+, Android API 29+, iOS 15+, or macOS 14.3+.
Apple builds use CocoaPods for Geolocator's foreground-only configuration.

```sh
cd examples/current_location
flutter pub get
flutter run -d macos
```

Tap the current-location button to grant permission. When permission already
exists, location updates start automatically. The map follows your position
until you move the map by hand. Tap the button to recenter and resume following.

Location acquisition stops when the app loses focus and resumes without another
permission prompt. If location services are disabled or permission is permanently
denied, the button opens the corresponding system settings.

Only foreground location permission is requested. Approximate location is
accepted. The map's attribution button remains visible. Each platform uses a
single 1024 × 1024 app icon.
