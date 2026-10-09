# World map

Explore cities around the world with Flutter Map markers on an
[OpenFreeMap](https://openfreemap.org/) vector map.

- Tap a city to zoom in. Markers get smaller as you zoom out.
- Use the globe button to return to the world view.

## Run

Requires Flutter 3.47+, Android API 29+, iOS 15+, or macOS 14.3+.

```sh
flutter pub get
flutter run -d macos
```

The map's attribution button stays visible. City coordinates come from
[Natural Earth](https://www.naturalearthdata.com/), using a fixed list in
[places.dart](lib/places.dart).
