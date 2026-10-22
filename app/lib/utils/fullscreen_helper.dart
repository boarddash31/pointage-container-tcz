import 'fullscreen_helper_stub.dart'
    if (dart.library.js_interop) 'fullscreen_helper_web.dart' as impl;

class FullscreenHelper {
  static void requestBrowserFullscreen() => impl.requestBrowserFullscreen();
  static void exitBrowserFullscreen() => impl.exitBrowserFullscreen();
  static void toggleBrowserFullscreen([bool? enable]) => impl.toggleBrowserFullscreen(enable);
  static bool isBrowserFullscreen() => impl.isBrowserFullscreen();
}
