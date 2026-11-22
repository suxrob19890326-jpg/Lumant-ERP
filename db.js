// Barcha sahifalar uchun umumiy: bazaga ulanish va login tekshiruvi.
import { SUPABASE_URL, SUPABASE_KEY } from './config.js';
import { navbat, navbatYubor, tarmoqXatosi } from './navbat.js';

// Kutubxona sahifadagi <script src="vendor/supabase-..."> orqali yuklanadi.
// Versiyani yangilash: vendor/ ga yangi faylni qo'yib, 3 ta sahifadagi nomini almashtiring.
const { createClient } = window.supabase;
export const db = createClient(SUPABASE_URL, SUPABASE_KEY);

// Internetsiz ishlash: sayt fayllari telefonda saqlanadi (sw.js);
// internetsiz kiritilgan yozuvlar internet qaytganda o'zi yuboriladi (navbat.js)
if ('serviceWorker' in navigator && location.protocol === 'https:') navigator.serviceWorker.register('sw.js').catch(() => {});
async function navbatniYubor() {
  if (!navbat().length || !navigator.onLine) return;
  const n = await navbatYubor(db);
  if (n.yuborildi || n.xatolar.length) window.dispatchEvent(new CustomEvent('navbat', { detail: n }));
}
window.addEventListener('online', navbatniYubor);
setTimeout(navbatniYubor, 1500);
export { navbat, navbatYubor };

// ---------- Rollar ----------
// Qaysi sahifa qaysi rollarga ochiq (bazadagi RLS qoidalari bilan bir xil)
export const SAHIFA_ROLLAR = {
  yozuv:       ['admin', 'rahbar', 'sotuvchi', 'kassir'],
  sverka:      ['admin', 'rahbar', 'sotuvchi', 'kassir'],
  kassa:       ['admin', 'rahbar', 'kassir'],
  ombor:       ['admin', 'rahbar', 'omborchi', 'sotuvchi'],
  ishlab:      ['admin', 'rahbar', 'omborchi'],
  hisobot:     ['admin', 'rahbar'],
  spravochnik: ['admin', 'rahbar', 'sotuvchi', 'kassir', 'omborchi'],
  xodimlar:    ['admin', 'rahbar'],
  tarix:       ['admin', 'rahbar'],
  nakladnoy:   ['admin', 'rahbar', 'sotuvchi', 'kassir'],
  buyurtma:    ['admin', 'rahbar', 'sotuvchi', 'omborchi'],
  reyslar:     ['admin', 'rahbar'],
  sozlamalar:  ['admin', 'rahbar'],
  foyda:       ['admin', 'rahbar'],
  ishhaqi:     ['admin', 'rahbar', 'kassir'],
};
export const ROL_NOMI = {
  admin: 'Admin', rahbar: 'Rahbar', sotuvchi: 'Sotuvchi', kassir: 'Kassir', omborchi: 'Omborchi',
};

// Joriy foydalanuvchining roli. 07_rollar_tarix.sql hali ishga tushirilmagan bo'lsa —
// avvalgidek hamma narsaga ruxsat ('admin'). Rol berilmagan / o'chirilgan bo'lsa — null.
let rolKesh;
export async function rolim(user) {
  if (rolKesh !== undefined) return rolKesh;
  const { data, error } = await db.from('xodimlar').select('rol, faol').eq('user_id', user.id).maybeSingle();
  const saqlangan = 'lumant_rol_' + user.id;
  if (error && tarmoqXatosi(error)) {   // internetsiz — oxirgi ma'lum rol
    try { rolKesh = localStorage[saqlangan] || null; } catch { rolKesh = null; }
    return rolKesh;
  }
  if (error) rolKesh = /xodimlar|schema cache|does not exist/i.test(error.message) ? 'admin' : null;
  else rolKesh = data && data.faol ? data.rol : null;
  try { if (rolKesh) localStorage[saqlangan] = rolKesh; else delete localStorage[saqlangan]; } catch {}
  return rolKesh;
}
export const ruxsat = (rol, sahifa) => !!rol && (SAHIFA_ROLLAR[sahifa] || []).includes(rol);

// Login qilinmagan bo'lsa — bosh sahifaga; sahifaga ruxsat bo'lmasa — xabar.
// Qaytaradi: foydalanuvchi (user.rol bilan).
export async function loginShart(sahifa) {
  const { data, error } = await db.auth.getSession();
  if (!data.session && (!navigator.onLine || tarmoqXatosi(error))) {
    // Internetsiz: token yangilanmagan bo'lsa ham, telefondagi oxirgi kirish bilan ishlaymiz
    const u = saqlanganFoydalanuvchi();
    if (u) data.session = { user: u };
  }
  if (!data.session) {
    location.replace('index.html');
    return new Promise(() => {});   // sahifa kodi shu yerda to'xtaydi
  }
  const user = data.session.user;
  user.rol = await rolim(user);
  if (sahifa && !ruxsat(user.rol, sahifa)) {
    document.body.innerHTML = `<header class="kichik"><a href="index.html" class="orqaga">‹ Menyu</a><h1>Ruxsat yo'q</h1></header>
      <section class="panel"><p>${user.rol
        ? 'Bu bo\'limga sizning rolingiz (' + (ROL_NOMI[user.rol] || user.rol) + ') bilan kirib bo\'lmaydi.'
        : 'Sizga hali rol berilmagan. Admin\'ga murojaat qiling.'}</p>
      <a class="tugma-ikkinchi" href="index.html">Menyuga qaytish</a></section>`;
    return new Promise(() => {});
  }
  return user;
}

function saqlanganFoydalanuvchi() {
  try {
    const k = Object.keys(localStorage).find(k => /^sb-.*-auth-token$/.test(k));
    return k ? JSON.parse(localStorage[k])?.user || null : null;
  } catch { return null; }
}

// Lotin ↔ kirill qidiruv (qidiruv.js)
export { kalit, mos, saralash, oxshashJuftlar } from './qidiruv.js';

// 1250000 → "1 250 000"
export function pul(n) {
  if (n === null || n === undefined || n === '') return '';
  let x = Number(n);
  if (Math.abs(x) < 0.005) x = 0;   // "-0" ko'rinmasin
  return x.toLocaleString('ru-RU', { maximumFractionDigits: 2 });
}

// 2026-11-19 → 19.11.2026
export function sana(s) {
  if (!s) return '';
  const [y, m, d] = s.split('-');
  return `${d}.${m}.${y}`;
}

// Bazadan kelgan matnni HTML'ga xavfsiz qo'yish uchun: "<b>" → "&lt;b&gt;"
export function toza(s) {
  return String(s ?? '').replace(/[&<>"']/g, c =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[c]);
}

// Baza bir so'rovda ko'pi bilan 1000 qator beradi — hammasini bo'laklab olamiz.
// soro: har safar YANGI so'rov qaytaradigan funksiya, masalan:
//   await hammasi(() => db.from('yozuvlar').select('id, summa').order('id'))
export async function hammasi(soro) {
  const natija = [];
  for (let dan = 0; ; dan += 1000) {
    const { data, error } = await soro().range(dan, dan + 999);
    if (error) return { data: null, error };
    natija.push(...data);
    if (data.length < 1000) return { data: natija, error: null };
  }
}

// Jadvalni Excel ochadigan CSV faylga yuklab berish.
// BOM — Excel o'zbek/rus harflarini to'g'ri ko'rsatishi uchun; ";" — ruscha Excel ajratgichi.
export function csvYukla(fayl, sarlavhalar, qatorlar) {
  const katak = (v) => {
    if (v === null || v === undefined) return '';
    const s = typeof v === 'number' ? String(v).replace('.', ',') : String(v);
    return /[;"\n\r]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
  };
  const matn = [sarlavhalar, ...qatorlar].map(q => q.map(katak).join(';')).join('\r\n');
  const blob = new Blob(['﻿' + matn], { type: 'text/csv;charset=utf-8' });
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = fayl.endsWith('.csv') ? fayl : fayl + '.csv';
  document.body.append(a);
  a.click();
  setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 1000);
}

// Sana yordamchilari (mahalliy vaqt bo'yicha YYYY-MM-DD)
export const bugun = () => new Date().toLocaleDateString('sv-SE');
export function kunQosh(s, n) {
  const d = new Date(s + 'T12:00:00');
  d.setDate(d.getDate() + n);
  return d.toLocaleDateString('sv-SE');
}
export function kunlarFarqi(a, b) {
  return Math.round((new Date(b + 'T12:00:00') - new Date(a + 'T12:00:00')) / 86400000);
}

// Mijoz hisobining valyutasi: 'UZS' (so'm) yoki 'USD'. 09-SQL'gacha hamma so'mda.
export const valyuta = (m) => (m && m.valyuta === 'USD') ? 'USD' : 'UZS';
export const belgi = (v) => v === 'USD' ? '$' : 'so\'m';
export const KASSA_NOMI = { naqd: '💵 Naqd', karta: '💳 Karta', bank: '🏦 Bank', dollar: '💲 Dollar' };

// Jadval bazada bormi (yangi SQL hali ishga tushirilmagan bo'lsa — yo'q)
export const jadvalYoq = (e) => !!e && (e.code === 'PGRST205' || e.code === '42P01' ||
  /schema cache|does not exist|Could not find the table/i.test(e.message || ''));

// Matnni telefon orqali yuborish: Telegram, SMS va h.k. (telefonda — "Ulashish" oynasi)
export async function ulash(matn) {
  if (navigator.share) {
    try { await navigator.share({ text: matn }); return true; } catch (e) { if (e.name === 'AbortError') return false; }
  }
  window.open('https://t.me/share/url?url=%20&text=' + encodeURIComponent(matn), '_blank');
  return true;
}

// Korxona ma'lumotlari (nakladnoy, dalolatnoma uchun). 09-SQL'gacha — standart.
let sozKesh;
export async function korxona() {
  if (sozKesh) return sozKesh;
  const { data } = await db.from('sozlamalar').select('*').eq('id', 1).maybeSingle();
  sozKesh = data || { korxona_nomi: 'Lumant Beton', manzil: 'Kogon tumani' };
  return sozKesh;
}
