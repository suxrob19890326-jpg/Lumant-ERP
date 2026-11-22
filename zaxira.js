// To'liq zaxira nusxa: barcha jadvallar bitta Excel faylda (har biri alohida varaqda).
// Format — Excel 2003 XML (.xls): Excel, LibreOffice va Google Sheets ochadi.
import { db, hammasi, bugun, jadvalYoq } from './db.js';

const JADVALLAR = [
  ['mijozlar', 'Mijozlar', 'id'], ['mahsulotlar', 'Mahsulotlar', 'id'], ['yozuvlar', 'Yozuvlar', 'id'],
  ['kassa_yozuvlar', 'Kassa', 'id'], ['ombor_harakat', 'Ombor', 'id'], ['ishlab_chiqarish', 'Ishlab chiqarish', 'id'],
  ['retseptlar', 'Retseptlar', 'mahsulot_id'], ['buyurtmalar', 'Buyurtmalar', 'id'],
  ['mijoz_narx', 'Maxsus narxlar', 'mijoz_id'], ['xodimlar', 'Xodimlar', 'created_at'],
];
const xml = (s) => String(s).replace(/[<>&"]/g, c => ({ '<': '&lt;', '>': '&gt;', '&': '&amp;', '"': '&quot;' })[c])
  .replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F]/g, '');

function varaq(nom, qatorlar) {
  const ustun = [...new Set(qatorlar.flatMap(q => Object.keys(q)))];
  const katak = (v) => {
    if (v === null || v === undefined) return '<Cell/>';
    if (typeof v === 'number' || (typeof v === 'string' && /^-?(0|[1-9]\d*)(\.\d+)?$/.test(v) && v.length < 15))
      return `<Cell><Data ss:Type="Number">${v}</Data></Cell>`;
    if (typeof v === 'object') v = JSON.stringify(v);
    return `<Cell><Data ss:Type="String">${xml(v)}</Data></Cell>`;
  };
  return `<Worksheet ss:Name="${xml(nom)}"><Table>
<Row>${ustun.map(u => `<Cell ss:StyleID="b"><Data ss:Type="String">${xml(u)}</Data></Cell>`).join('')}</Row>
${qatorlar.map(q => `<Row>${ustun.map(u => katak(q[u])).join('')}</Row>`).join('\n')}
</Table></Worksheet>`;
}

// holat(matn) — jarayonni ko'rsatish uchun. Qaytaradi: { jami: qatorlar soni }
export async function zaxiraYukla(holat = () => {}) {
  const varaqlar = [];
  let jami = 0;
  for (const [jadval, nom, tartib] of JADVALLAR) {
    holat(`${nom} yuklanmoqda...`);
    const { data, error } = await hammasi(() => db.from(jadval).select('*').order(tartib));
    if (error) { if (jadvalYoq(error) || /permission/i.test(error.message)) continue; throw error; }
    varaqlar.push(varaq(nom, data));
    jami += data.length;
  }
  const matn = `<?xml version="1.0" encoding="UTF-8"?>
<?mso-application progid="Excel.Sheet"?>
<Workbook xmlns="urn:schemas-microsoft-com:office:spreadsheet" xmlns:ss="urn:schemas-microsoft-com:office:spreadsheet">
<Styles><Style ss:ID="b"><Font ss:Bold="1"/></Style></Styles>
${varaqlar.join('\n')}
</Workbook>`;
  const a = document.createElement('a');
  a.href = URL.createObjectURL(new Blob([matn], { type: 'application/vnd.ms-excel' }));
  a.download = `lumant-zaxira-${bugun()}.xls`;
  document.body.append(a);
  a.click();
  setTimeout(() => { URL.revokeObjectURL(a.href); a.remove(); }, 1000);
  try { localStorage.zaxira_kun = bugun(); } catch {}
  return { jami, varaq: varaqlar.length };
}
