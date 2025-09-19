// web_registry.dart
// Only for web
// ignore: avoid_web_libraries_in_flutter
import 'dart:ui' as ui;
import 'dart:html' as html;

void registerVideoElement(html.VideoElement videoElement, String viewType) {
  // ignore: undefined_prefixed_name
  ui.platformViewRegistry.registerViewFactory(viewType, (int viewId) => videoElement);
}
