// Lotin ↔ kirill qidiruv.
// Har qanday matn (o'zbek lotin, o'zbek kirill, rus) bitta "kalit"ga aylantiriladi,
// keyin kalitlar solishtiriladi. Shuning uchun "graviy" → "гравий",
// "Anvar karyer" → "Анвар карьер", "sement" → "Цемент", "Qodir" → "Кодир" topiladi.

// 1) Kirill → lotin (o'zbek imlosiga yaqin)
const KIRILL = {
  а: 'a', б: 'b', в: 'v', г: 'g', д: 'd', е: 'e', ё: 'yo', ж: 'j', з: 'z', и: 'i', й: 'y',
  к: 'k', л: 'l', м: 'm', н: 'n', о: 'o', п: 'p', р: 'r', с: 's', т: 't', у: 'u', ф: 'f',
  х: 'x', ц: 's', ч: 'ch', ш: 'sh', щ: 'sh', ъ: '', ы: 'i', ь: '', э: 'e', ю: 'yu', я: 'ya',
  ў: 'o', қ: 'k', ғ: 'g', ҳ: 'x', і: 'i', ї: 'yi', є: 'e',
};

// 2) Bir xil tovushning turli yozilishlari bitta belgiga keltiriladi
//    (ikkala tomon ham shu yo'ldan o'tgani uchun "yo'qotish" xavfsiz)
const QOIDALAR = [
  [/['`ʻʼ‘’]/g, ''],     // o' g' tutuq belgilari
  [/sh/g, '§'],          // sh va ch ni h→x dan oldin himoyalaymiz
  [/ch/g, '¢'],
  [/kh/g, 'x'],          // rus lotinida "kh" = х
  [/h/g, 'x'],           // h va x (ҳ / х) farqlanmaydi
  [/ts/g, 's'],          // ц
  [/c/g, 's'],           // "cement" = "sement"
  [/q/g, 'k'],           // қ / к
  [/w/g, 'v'],
  [/y([aeiou])/g, '$1'], // я=ya, е=ye, ё=yo, ю=yu → a, e, o, u
  [/([aeiou])y(?![aeiou])/g, '$1i'], // "graviy" / "гравий" — oxirdagi y ≈ i
  [/([a-z§¢])\1+/g, '$1'], // ikkilangan harflar: "Ахмаддин" = "Axmadin" (raqamlarga tegmaydi)
];

const kesh = new Map();

export function kalit(matn) {
  const s = String(matn ?? '');
  let k = kesh.get(s);
  if (k !== undefined) return k;
  k = s.toLowerCase().normalize('NFC');
  let natija = '';
  for (const ch of k) natija += KIRILL[ch] ?? ch;
  for (const [re, yangi] of QOIDALAR) natija = natija.replace(re, yangi);
  natija = natija.replace(/\s+/g, ' ').trim();
  if (kesh.size > 5000) kesh.clear();
  kesh.set(s, natija);
  return natija;
}

// Matnda qidiruv so'zi bormi? Bir nechta so'z bo'lsa — hammasi bo'lishi kerak
// ("anvar kar" → "Анвар карьер" topiladi, so'zlar tartibi muhim emas).
export function mos(matn, soz) {
  const qism = kalit(soz).split(' ').filter(Boolean);
  if (!qism.length) return true;
  const k = kalit(matn);
  return qism.every(q => k.includes(q));
}

// Topilganlarni saralash: nomi so'z bilan boshlanadiganlar birinchi, keyin alifbo bo'yicha
export function saralash(royxat, soz, nomi = (x) => x.nomi) {
  const q = kalit(soz);
  return [...royxat].sort((a, b) => {
    const ba = kalit(nomi(a)).startsWith(q), bb = kalit(nomi(b)).startsWith(q);
    return ba === bb ? 0 : ba ? -1 : 1;   // barqaror saralash: qolgan tartib o'zgarmaydi
  });
}

// O'xshash nomli juftliklarni topish (takror mijozlarni birlashtirish uchun).
// - so'zlar bir xil (tartibi farq qilishi mumkin): "Миксер Рустам" ⟷ "Рустам миксер"
// - biri ikkinchisining ichida (kamida 2 so'z): "Жамшид Зокир" ⟷ "Жамшид Зокир гиж"
// Ikkalasida HAR XIL raqam bo'lsa (telefon / mashina) — har xil odam deb hisoblanadi.
const UNVON = new Set(['aka', 'ake', 'opa', 'uka', 'xola', 'amaki', 'ota', 'ona']);
export function oxshashJuftlar(royxat, nomi = (x) => x.nomi) {
  const T = royxat.map(x => {
    const n = nomi(x);
    const sozlar = [...new Set(kalit(n).replace(/[^a-z§¢ ]+/g, ' ').split(' ')
      .filter(t => t.length > 1 && !UNVON.has(t)))].sort();
    return { x, sozlar, kalit: sozlar.join(' '), raqam: (n.match(/\d+/g) || []).join('-') };
  }).filter(t => t.sozlar.length);

  const juftlar = [];
  // 1) so'zlari bir xil — guruhlab (tez)
  const guruh = new Map();
  for (const t of T) { if (!guruh.has(t.kalit)) guruh.set(t.kalit, []); guruh.get(t.kalit).push(t); }
  for (const g of guruh.values()) {
    for (let i = 0; i < g.length; i++) for (let j = i + 1; j < g.length; j++) {
      const a = g[i], b = g[j];
      if (a.raqam && b.raqam && a.raqam !== b.raqam) continue;
      juftlar.push({ a: a.x, b: b.x, kuch: a.sozlar.length > 1 ? 3 : 2 });
    }
  }
  // 2) biri ikkinchisining ichida (kamida 2 so'z)
  const kopSozli = T.filter(t => t.sozlar.length >= 2);
  for (const k of kopSozli) {
    for (const u of kopSozli) {
      if (u.sozlar.length <= k.sozlar.length) continue;
      if (k.raqam && u.raqam && k.raqam !== u.raqam) continue;
      if (k.sozlar.every(s => u.sozlar.includes(s))) juftlar.push({ a: k.x, b: u.x, kuch: 1 });
    }
  }
  return juftlar.sort((p, q) => q.kuch - p.kuch);
}
