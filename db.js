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
    location.href = 'index.html';
    return null;
  }
  return data.session.user;
}

// 1250000 → "1 250 000"
export function pul(n) {
  if (n === null || n === undefined || n === '') return '';
  return Number(n).toLocaleString('ru-RU', { maximumFractionDigits: 2 });
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
