// Internetsiz kiritilgan yozuvlar navbati: telefonda saqlanadi, internet qaytganda yuboriladi.
// Har yozuvda client_id (11-SQL) — ikki marta tushib qolmaydi.
const KALIT = 'lumant_navbat';

export const tarmoqXatosi = (e) => !navigator.onLine ||
  /Failed to fetch|NetworkError|Load failed|network|fetch failed/i.test(String(e?.message || e || ''));

export function navbat() {
  try { return JSON.parse(localStorage[KALIT] || '[]'); } catch { return []; }
}
function saqla(r) { try { localStorage[KALIT] = JSON.stringify(r); } catch {} }

export function navbatgaQosh(yozuv, nomi, buyurtma = null) {
  const r = navbat();
  r.push({ yozuv, nomi, buyurtma, vaqt: new Date().toISOString() });
  saqla(r);
  return r.length;
}

// Yuboradi. Qaytaradi: { yuborildi, qoldi, xatolar: [matn] }
let ishlayapti = false;
export async function navbatYubor(db) {
  if (ishlayapti || !navigator.onLine) return { yuborildi: 0, qoldi: navbat().length, xatolar: [] };
  ishlayapti = true;
  let yuborildi = 0;
  const xatolar = [];
  try {
    for (const n of navbat()) {
      let y = { ...n.yozuv };
      let { error } = await db.from('yozuvlar').insert(y);
      if (error && /client_id/.test(error.message || '') && (error.code === 'PGRST204' || error.code === '42703')) {
        delete y.client_id;                      // 11-SQL hali yo'q
        ({ error } = await db.from('yozuvlar').insert(y));
      }
      if (error && tarmoqXatosi(error)) break;   // internet yana uzildi — keyinroq
      if (!error || error.code === '23505') {   // 23505 — avval yetib borgan (client_id takrori)
        yuborildi++;
        if (n.buyurtma && y.client_id) {        // buyurtmadan kiritilgan bo'lsa — buyurtma bajarildi
          const { data: yz } = await db.from('yozuvlar').select('id').eq('client_id', y.client_id).maybeSingle();
          if (yz) await db.from('buyurtmalar').update({ holat: 'bajarildi', yozuv_id: yz.id }).eq('id', n.buyurtma).eq('holat', 'yangi');
        }
      } else xatolar.push(`${n.nomi}: ${error.message}`);
      saqla(navbat().filter(x => x.vaqt !== n.vaqt || x.nomi !== n.nomi));   // yuborilgan (yoki rad etilgan) olib tashlanadi
    }
  } finally { ishlayapti = false; }
  if (xatolar.length) { try { localStorage.lumant_navbat_xato = JSON.stringify(xatolar); } catch {} }
  return { yuborildi, qoldi: navbat().length, xatolar };
}
