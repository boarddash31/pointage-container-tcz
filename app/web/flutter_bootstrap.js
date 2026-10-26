{{flutter_js}}
{{flutter_build_config}}

// Finish removing an older Flutter worker before requesting the new program/assets.
// Supabase's persisted session is in localStorage and is retained.
window.tczBootReady = (async function () {
  const release = 'marsa-bons-v1';
  try {
    if ('serviceWorker' in navigator) {
      const registrations = await navigator.serviceWorker.getRegistrations();
      await Promise.all(registrations.filter(registration =>
        document.baseURI.startsWith(registration.scope) &&
        [registration.active, registration.waiting, registration.installing].some(worker =>
          worker && new URL(worker.scriptURL).pathname.endsWith('/flutter_service_worker.js'))
      ).map(registration => registration.unregister()));
    }
    if ('caches' in window) {
      const flutterCaches = new Set(['flutter-app-cache', 'flutter-temp-cache', 'flutter-app-manifest']);
      const names = await caches.keys();
      await Promise.all(names.filter(name => flutterCaches.has(name)).map(name => caches.delete(name)));
    }
  } catch (error) {
    console.warn('Flutter cache cleanup unavailable; loading the current release.', error);
  }
  for (const build of _flutter.buildConfig.builds) {
    if (build.mainJsPath) build.mainJsPath += '?tcz_release=' + release;
  }
  return _flutter.loader.load();
})();
