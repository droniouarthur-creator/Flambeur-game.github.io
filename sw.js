// Change ce nom à chaque mise en ligne pour que les joueurs reçoivent la nouvelle version.
const CACHE = 'flambeur-v2';
const ASSETS = ['./', './index.html', './manifest.json', './questions.json'];

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(ASSETS)));
  self.skipWaiting();
});

self.addEventListener('activate', (e) => {
  e.waitUntil(caches.keys().then((keys) =>
    Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))));
  self.clients.claim();
});

// Réseau d'abord (version à jour), cache en secours (hors ligne).
// Les requêtes vers d'autres sites (Supabase, Stripe...) ne sont jamais mises en cache.
self.addEventListener('fetch', (e) => {
  if (e.request.method !== 'GET' || new URL(e.request.url).origin !== location.origin) return;
  e.respondWith(
    fetch(e.request)
      .then((r) => { const copy = r.clone(); caches.open(CACHE).then((c) => c.put(e.request, copy)); return r; })
      .catch(() => caches.match(e.request).then((r) => r || caches.match('./index.html')))
  );
});
