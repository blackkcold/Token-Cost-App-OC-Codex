const CACHE_NAME = 'token-cost-terminal-shell-__BUILD_HASH__';
const APP_SHELL = [
  './',
  'index.html',
  'flutter_bootstrap.js',
  'register_service_worker.js',
  'main.dart.js',
  'manifest.json',
  'favicon.png',
  'icons/Icon-192.png',
  'icons/Icon-512.png',
  'icons/Icon-maskable-192.png',
  'icons/Icon-maskable-512.png',
  'barcode/zxing-0.23.0.min.js',
  'canvaskit/canvaskit.js',
  'canvaskit/canvaskit.wasm',
  'canvaskit/chromium/canvaskit.js',
  'canvaskit/chromium/canvaskit.wasm',
  'assets/AssetManifest.bin',
  'assets/FontManifest.json',
  'assets/fonts/MaterialIcons-Regular.otf',
  'assets/assets/fonts/JetBrainsMono-Regular.ttf',
  'assets/assets/fonts/JetBrainsMono-Medium.ttf',
  'assets/assets/fonts/JetBrainsMono-Bold.ttf',
  'assets/shaders/ink_sparkle.frag',
  'assets/shaders/stretch_effect.frag',
  'font-fallback/roboto/v32/KFOmCnqEu92Fr1Me4GZLCzYlKw.woff2'
];

self.addEventListener('install', (event) => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE_NAME);
    await cache.addAll(APP_SHELL);
    await self.skipWaiting();
  })());
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const names = await caches.keys();
    await Promise.all(names.filter((name) => name !== CACHE_NAME).map((name) => caches.delete(name)));
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  if (request.mode === 'navigate') {
    event.respondWith((async () => {
      try {
        return await fetch(request);
      } catch (_) {
        const cache = await caches.open(CACHE_NAME);
        return (await cache.match('index.html')) || Response.error();
      }
    })());
    return;
  }

  const relativePath = url.pathname.replace(new URL('./', self.location.href).pathname, '');
  if (!APP_SHELL.includes(relativePath)) return;
  const cachePromise = caches.open(CACHE_NAME);
  const update = cachePromise.then((cache) => fetch(request).then(async (response) => {
      if (response.ok) {
        await cache.put(request, response.clone());
      }
      return response;
    }));
  event.waitUntil(update.then(() => undefined, () => undefined));
  event.respondWith(
    cachePromise
      .then((cache) => cache.match(request))
      .then((cached) => cached || update),
  );
});
