/* ═══════════════════════════════════════════════════════════════════════
   UNKI GEOTECH · SERVICE WORKER

   The app shell, and nothing else. Its one job is that a technician who
   opens the app underground, with no signal, gets the app — rather than
   the browser's offline page.

   THREE RULES, and the first two are from CLAUDE.md's hard rules:

     1. NEVER INTERCEPT A NON-GET REQUEST. Every write goes to the
        network or fails loudly so the offline queue can hold it. A
        service worker that quietly answered a POST would be a service
        worker that silently dropped a face measurement.

     2. NEVER INTERCEPT SUPABASE, or any other origin. Sign-in, the
        write path and the dashboard's reads all go straight past this
        file. A cached read is a stale read, and a stale over-break
        figure is worse than no figure.

     3. NEVER UPDATE UNDER THE TECHNICIAN. A new version installs and
        then WAITS. The page offers it and the person decides when to
        take it, because offsets being typed at that moment live in
        memory and a reload would lose them. `skipWaiting` is called on
        their say-so and never on ours.

   What is deliberately NOT cached: seed-demo.html, which is not part of
   the app, and anything from another origin.

   Bump CACHE when the shell changes; that is what makes the browser
   fetch this file afresh and offer the update.
   ═══════════════════════════════════════════════════════════════════════ */

const CACHE = 'unki-geotech-shell-v1';

/* Relative, so the app still works when it is served from a
   subdirectory rather than the root of a host. */
const SHELL = [
  './',
  './index.html',
  './review.html',
  './manifest.webmanifest',
  './icons/icon-192.png',
  './icons/icon-512.png',
  './icons/icon-maskable-512.png',
  './icons/apple-touch-icon.png',
];

self.addEventListener('install', event => {
  event.waitUntil((async () => {
    const cache = await caches.open(CACHE);
    /* addAll is all-or-nothing: one 404 and the whole install fails,
       leaving the previous shell in place. That is the behaviour we
       want — a half-cached app is worse than the old one. */
    await cache.addAll(SHELL);
    /* No skipWaiting here. Rule 3. */
  })());
});

self.addEventListener('activate', event => {
  event.waitUntil((async () => {
    const names = await caches.keys();
    await Promise.all(names
      .filter(n => n.startsWith('unki-geotech-') && n !== CACHE)
      .map(n => caches.delete(n)));
    await self.clients.claim();
  })());
});

/* The page asks for the waiting worker only when the person has said
   yes. Nothing else may trigger it. */
self.addEventListener('message', event => {
  if (event.data && event.data.type === 'SKIP_WAITING') self.skipWaiting();
});

self.addEventListener('fetch', event => {
  const req = event.request;

  /* Rule 1. Not answering means the browser does what it always would. */
  if (req.method !== 'GET') return;

  const url = new URL(req.url);

  /* Rule 2. Supabase, and anything else off-origin, is none of our
     business. */
  if (url.origin !== self.location.origin) return;

  /* The demo seeder is not part of the app and is never made available
     offline — it must not be reachable on a tablet that has lost its
     connection and its way. */
  if (url.pathname.endsWith('/seed-demo.html')) return;

  event.respondWith((async () => {
    const cache = await caches.open(CACHE);
    const hit = await cache.match(req, { ignoreSearch: true });
    if (hit) return hit;

    try {
      const res = await fetch(req);
      /* Cache same-origin successes so a page visited once is available
         the next time there is no signal. Opaque and error responses
         are left alone. */
      if (res && res.ok && res.type === 'basic') cache.put(req, res.clone());
      return res;
    } catch (err) {
      /* Offline and not cached. For a navigation, the app shell is a
         better answer than the browser's error page; for anything else,
         let the failure surface. */
      if (req.mode === 'navigate') {
        const shell = await cache.match('./index.html');
        if (shell) return shell;
      }
      throw err;
    }
  })());
});
