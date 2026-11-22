// Summani so'z bilan yozish (o'zbekcha, lotin): 1250000 → "bir million ikki yuz ellik ming so'm"
const BIR = ['', 'bir', 'ikki', 'uch', 'to\'rt', 'besh', 'olti', 'yetti', 'sakkiz', 'to\'qqiz'];
const ON = ['', 'o\'n', 'yigirma', 'o\'ttiz', 'qirq', 'ellik', 'oltmish', 'yetmish', 'sakson', 'to\'qson'];
const DARAJA = ['', 'ming', 'million', 'milliard', 'trillion'];

function uchXona(n) {
  const y = Math.floor(n / 100), o = Math.floor((n % 100) / 10), b = n % 10;
  return [y ? BIR[y] + ' yuz' : '', ON[o], BIR[b]].filter(Boolean).join(' ');
}

export function sonSoz(n) {
  n = Math.floor(Math.abs(Number(n) || 0));
  if (n === 0) return 'nol';
  const qism = [];
  for (let i = 0; n > 0 && i < DARAJA.length; i++, n = Math.floor(n / 1000)) {
    const u = n % 1000;
    if (u) qism.unshift(uchXona(u) + (DARAJA[i] ? ' ' + DARAJA[i] : ''));
  }
  return qism.join(' ');
}

// valyuta: 'UZS' → so'm/tiyin, 'USD' → dollar/sent
export function sozBilan(summa, valyuta = 'UZS') {
  const s = Math.abs(Number(summa) || 0);
  const butun = Math.floor(s), kasr = Math.round((s - butun) * 100);
  const [katta, kichik] = valyuta === 'USD' ? ['AQSh dollari', 'sent'] : ['so\'m', 'tiyin'];
  let m = `${sonSoz(butun)} ${katta}`;
  if (kasr) m += ` ${String(kasr).padStart(2, '0')} ${kichik}`;
  return m.charAt(0).toUpperCase() + m.slice(1);
}
