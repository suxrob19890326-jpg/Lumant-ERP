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
