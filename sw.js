// Internetsiz ishlash: sayt fayllari telefonda saqlanadi.
// Avval internetdan (yangi versiya), 4 soniyada javob bo'lmasa yoki internet yo'q bo'lsa — saqlangandan.
// Baza so'rovlari (supabase.co) bu yerdan o'tmaydi.
const KESH = 'lumant-v1';
const FAYLLAR = [
  './', 'index.html', 'yozuv.html', 'sverka.html', 'kassa.html', 'ombor.html', 'ishlab.html', 'hisobot.html',
  'spravochnik.html', 'xodimlar.html', 'tarix.html', 'buyurtma.html', 'reyslar.html', 'sozlamalar.html',
  'nakladnoy.html', 'foyda.html', 'ishhaqi.html', 'kabinet.html',
  'style.css', 'db.js', 'config.js', 'qidiruv.js', 'sozbilan.js', 'zaxira.js', 'navbat.js',
  'vendor/supabase-2.119.2.js', 'logo.png', 'icon-180.png', 'icon-192.png', 'manifest.json',
];

self.addEventListener('install', (e) => {
  e.waitUntil(caches.open(KESH).then(c => Promise.allSettled(FAYLLAR.map(f => c.add(f)))).then(() => self.skipWaiting()));
});
self.addEventListener('activate', (e) => {
  e.waitUntil(caches.keys().then(k => Promise.all(k.filter(x => x !== KESH).map(x => caches.delete(x))))
    .then(() => self.clients.claim()));
});
self.addEventListener('fetch', (e) => {
  const url = new URL(e.request.url);
  if (e.request.method !== 'GET' || url.origin !== location.origin) return;
  e.respondWith((async () => {
    const kesh = await caches.open(KESH);
    try {
      const javob = await Promise.race([
        fetch(e.request),
        new Promise((_, rad) => setTimeout(() => rad(new Error('sekin')), 4000)),
      ]);
      if (javob.ok) kesh.put(e.request, javob.clone());
      return javob;
    } catch {
      return (await kesh.match(e.request, { ignoreSearch: true })) ||
             (await kesh.match('index.html')) || Response.error();
    }
  })());
});
