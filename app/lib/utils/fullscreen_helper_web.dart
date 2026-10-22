// Web implementation of browser fullscreen using dart:js_interop
import 'dart:js_interop';

@JS('tczToggleFullscreen')
external void _tczToggleFullscreen([JSBoolean? enable]);

@JS('tczIsFullscreen')
external JSBoolean _tczIsFullscreen();

void requestBrowserFullscreen() {
  try {
    _tczToggleFullscreen(true.toJS);
  } catch (_) {}
}

void exitBrowserFullscreen() {
  try {
    _tczToggleFullscreen(false.toJS);
  } catch (_) {}
}

void toggleBrowserFullscreen([bool? enable]) {
  try {
    if (enable != null) {
      _tczToggleFullscreen(enable.toJS);
    } else {
      _tczToggleFullscreen();
    }
  } catch (_) {}
}

bool isBrowserFullscreen() {
  try {
    return _tczIsFullscreen().toDart;
  } catch (_) {
    return false;
  }
}
