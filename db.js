// Barcha sahifalar uchun umumiy: bazaga ulanish va login tekshiruvi.
import { SUPABASE_URL, SUPABASE_KEY } from './config.js';

// Kutubxona sahifadagi <script src="vendor/supabase-..."> orqali yuklanadi.
// Versiyani yangilash: vendor/ ga yangi faylni qo'yib, 3 ta sahifadagi nomini almashtiring.
const { createClient } = window.supabase;
export const db = createClient(SUPABASE_URL, SUPABASE_KEY);

// Login qilinmagan bo'lsa, bosh sahifaga (login formasiga) qaytaradi
export async function loginShart() {
  const { data } = await db.auth.getSession();
  if (!data.session) {
    location.replace('index.html');
    return new Promise(() => {});   // sahifa kodi shu yerda to'xtaydi
  }
  return data.session.user;
}

// Lotin ↔ kirill qidiruv (qidiruv.js)
export { kalit, mos, saralash } from './qidiruv.js';

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
