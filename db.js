// Barcha sahifalar uchun umumiy: bazaga ulanish va login tekshiruvi.
import { SUPABASE_URL, SUPABASE_KEY } from './config.js';

// Kutubxona sahifadagi <script src="vendor/supabase-..."> orqali yuklanadi.
// Versiyani yangilash: vendor/ ga yangi faylni qo'yib, 3 ta sahifadagi nomini almashtiring.
const { createClient } = window.supabase;
export const db = createClient(SUPABASE_URL, SUPABASE_KEY);

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
  if (error) rolKesh = /xodimlar|schema cache|does not exist/i.test(error.message) ? 'admin' : null;
  else rolKesh = data && data.faol ? data.rol : null;
  return rolKesh;
}
export const ruxsat = (rol, sahifa) => !!rol && (SAHIFA_ROLLAR[sahifa] || []).includes(rol);

// Login qilinmagan bo'lsa — bosh sahifaga; sahifaga ruxsat bo'lmasa — xabar.
// Qaytaradi: foydalanuvchi (user.rol bilan).
export async function loginShart(sahifa) {
  const { data } = await db.auth.getSession();
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
