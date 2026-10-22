// Stub for platforms that are not Web (tests, desktop, mobile native)

void requestBrowserFullscreen() {}
void exitBrowserFullscreen() {}
void toggleBrowserFullscreen([bool? enable]) {}
bool isBrowserFullscreen() => false;
