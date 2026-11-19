#!/usr/bin/env python3
"""
"DT KT Mamurjon" Excel faylidan Supabase uchun SQL import fayli yasaydi.

Ishlatish:
    python3 tools/excel_import.py DT_KT_Mamurjon.xlsx supabase/

Natija: supabase/03_malumotlar.sql va supabase/04_arxiv_N.sql fayllari.
Ularni tartib bilan Supabase → SQL Editor'da ishga tushiring
(01_jadvallar.sql va 02_qoshimcha_jadvallar.sql dan keyin).

Qiymatlar formulalar emas, Sheets hisoblagan (ko'rinib turgan) qiymatlar
olinadi — shuning uchun ERP'dagi summalar Sheets'dagi bilan bir xil bo'ladi.
"""
import datetime as dt
import os
import json
import re
import sys

import openpyxl


# ----------------------------------------------------------------- yordamchi
def q(v):
    """Python qiymatini SQL literalga aylantiradi."""
    if v is None:
        return "null"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return num(v)
    if isinstance(v, dt.datetime):
        return "'" + v.isoformat(sep=" ") + "'"
    if isinstance(v, dt.date):
        return "'" + v.isoformat() + "'"
    return "'" + str(v).replace("'", "''") + "'"


def num(v):
    if isinstance(v, float) and v.is_integer():
        return str(int(v))
    return repr(v)


def matn(v):
    """Bo'sh satrni None qiladi, raqamni chiroyli matnga aylantiradi."""
    if v is None:
        return None
    if isinstance(v, float):
        v = num(v)
    if isinstance(v, dt.datetime):
        v = v.strftime("%d.%m.%Y %H:%M") if (v.hour or v.minute) else v.strftime("%d.%m.%Y")
    v = str(v)
    return v if v.strip() != "" else None


def sana(v):
    return v.date() if isinstance(v, dt.datetime) else None


def vaqt(v):
    # Sheets vaqti Toshkent vaqti (+05)
    if not isinstance(v, dt.datetime):
        return "null"
    return "'" + v.isoformat(sep=" ") + "+05'"


def raqam(v):
    """(son, asl_matn) — son bo'lmasa son=None, matn saqlanadi."""
    if v is None or v == "":
        return None, None
    if isinstance(v, bool):
        return None, str(v)
    if isinstance(v, (int, float)):
        return v, None
    s = str(v).strip()
    try:
        return float(s.replace(" ", "").replace(",", ".")), None
    except ValueError:
        return None, s


def bor(row, n):
    return any(c not in (None, "") for c in row[:n])


# ------------------------------------------------------------------- asosiy
def main(xlsx, chiqish):
    wb = openpyxl.load_workbook(xlsx, data_only=True)
    out = []
    w = out.append

    w("-- =====================================================================")
    w("-- LUMANT ERP — 3-qadam: Excel'dagi ma'lumotlarni bazaga yuklash")
    w(f"-- Manba: {xlsx.split('/')[-1]}  (yaratildi: {dt.date.today():%d.%m.%Y})")
    w("-- 02_qoshimcha_jadvallar.sql dan KEYIN ishga tushiring. Faqat BIR marta!")
    w("-- =====================================================================")
    w("begin;")
    w("")
    w("do $$ begin")
    w("  if exists (select 1 from yozuvlar) then")
    w("    raise exception 'Bazada allaqachon yozuvlar bor — import ikkinchi marta ishga tushmaydi';")
    w("  end if;")
    w("end $$;")
    w("")

    # ---------------- O'lchovlar
    olchov = [r[0] for r in wb["Olchovlar"].iter_rows(min_row=2, values_only=True) if matn(r[0])]
    w("-- O'lchov birliklari")
    w("insert into olchovlar (nomi, tartib) values")
    w(",\n".join(f"  ({q(n)}, {i})" for i, n in enumerate(olchov, 1)) + ";\n")

    # ---------------- Mahsulotlar
    mahsulot = {}
    for i, r in enumerate(wb["Mahsulotlar"].iter_rows(min_row=2, values_only=True), 1):
        nomi = matn(r[0])
        if nomi and nomi not in mahsulot:
            mahsulot[nomi] = dict(turi=matn(r[1]), olchov=matn(r[2]),
                                  narx=r[3] if isinstance(r[3], (int, float)) else None, tartib=i)

    # ---------------- Mijozlar
    mijoz = {}
    for i, r in enumerate(wb["Mijozlar"].iter_rows(min_row=2, values_only=True), 1):
        nomi = matn(r[0])
        if not nomi or nomi in mijoz:
            continue
        kd = None
        m = re.search(r"(\d{1,2})\.(\d{1,2})\.(\d{4})", str(r[9] or ""))
        if m:
            kd = dt.date(int(m[3]), int(m[2]), int(m[1]))
        mijoz[nomi] = dict(telefon=matn(r[1]), bifoza=matn(r[5]), guruh=matn(r[8]),
                           kochirildi=kd, tartib=i, sheet_qoldiq=r[2])

    # ---------------- Asosiy (yozuvlar)
    asosiy = []
    for i, r in enumerate(wb["Asosiy"].iter_rows(min_row=2, values_only=True), 2):
        if bor(r, 9):
            asosiy.append((i, r))

    # Asosiy'da bor, lekin ro'yxatlarda yo'q nomlarni qo'shamiz (bir xillik uchun)
    for _, r in asosiy:
        if matn(r[1]) and matn(r[1]) not in mijoz:
            mijoz[matn(r[1])] = dict(telefon=None, bifoza=None, guruh=None, kochirildi=None,
                                     tartib=len(mijoz) + 10000, sheet_qoldiq=None)
        if matn(r[2]) and matn(r[2]) not in mahsulot:
            mahsulot[matn(r[2])] = dict(turi=None, olchov=matn(r[3]), narx=None,
                                        tartib=len(mahsulot) + 10000)

    w(f"-- Mahsulotlar ({len(mahsulot)} ta)")
    w("insert into mahsulotlar (nomi, turi, olchov, oxirgi_narx, tartib) values")
    w(",\n".join(f"  ({q(n)}, {q(d['turi'])}, {q(d['olchov'])}, {q(d['narx'])}, {d['tartib']})"
                 for n, d in mahsulot.items()) + ";\n")

    w(f"-- Mijozlar ({len(mijoz)} ta)")
    w("insert into mijozlar (nomi, telefon, bifoza_nomi, takror_guruh, kochirildi, tartib) values")
    w(",\n".join(f"  ({q(n)}, {q(d['telefon'])}, {q(d['bifoza'])}, {q(d['guruh'])}, "
                 f"{q(d['kochirildi'])}, {d['tartib']})" for n, d in mijoz.items()) + ";\n")

    # turi: + / − belgisi va pul/mahsulot ekaniga qarab
    def pulmi(prod, olch):
        p = mahsulot.get(prod or "", {})
        return (p.get("turi") == "Тулов" or p.get("olchov") in ("сум", "$")
                or olch in ("сум", "$") or (prod or "").lower() in ("касса", "накд", "переч"))

    w(f"-- Asosiy → yozuvlar ({len(asosiy)} ta)")
    w("insert into yozuvlar (sana, mijoz_id, turi, mahsulot_id, olchov, miqdor, narx, summa,"
      " avto_raqami, izoh, qulf, kiritgan_ismi, kiritilgan_vaqt, arxiv_no, tartib) values")
    qator = []
    for i, r in asosiy:
        summa = r[6] if isinstance(r[6], (int, float)) else None
        miqdor = r[4] if isinstance(r[4], (int, float)) else None
        belgi = summa if summa not in (None, 0) else (miqdor or 1)
        if pulmi(matn(r[2]), matn(r[3])):
            turi = "pul_berildi" if belgi > 0 else "tolov_keldi"
        else:
            turi = "yuk_berildi" if belgi > 0 else "mahsulot_olindi"
        qator.append(
            f"  ({q(sana(r[0]))}, (select id from mijozlar where nomi = {q(matn(r[1]))}), {q(turi)}, "
            f"(select id from mahsulotlar where nomi = {q(matn(r[2]))}), {q(matn(r[3]))}, "
            f"{q(miqdor)}, {q(r[5] if isinstance(r[5], (int, float)) else None)}, {q(summa if summa is not None else 0)}, "
            f"{q(matn(r[7]))}, {q(matn(r[8]))}, {q(bool(r[9]))}, {q(matn(r[10]))}, {vaqt(r[11])}, "
            f"{q(int(r[12]) if isinstance(r[12], (int, float)) else None)}, {i})")
    w(",\n".join(qator) + ";\n")

    # ---------------- Arxiv
    arxiv = []
    for i, r in enumerate(wb["Arxiv"].iter_rows(min_row=2, values_only=True), 2):
        if not bor(r, 9):
            continue
        asl = {}
        sana_matn = None
        if r[0] is not None and not isinstance(r[0], dt.datetime):
            sana_matn = matn(r[0])
        vals = []
        for k, col in (("miqdor", 4), ("narx", 5), ("summa", 6)):
            v, s = raqam(r[col])
            if s is not None:
                asl[k] = s
            vals.append(v)
        arxiv.append(
            f"  ({i}, {q(sana(r[0]))}, {q(sana_matn)}, {q(matn(r[1]))}, {q(matn(r[2]))}, {q(matn(r[3]))}, "
            f"{q(vals[0])}, {q(vals[1])}, {q(vals[2])}, {q(matn(r[7]))}, {q(matn(r[8]))}, "
            f"{q(bool(r[9]))}, {q(matn(r[10]))}, {vaqt(r[11])}, "
            f"{q(json.dumps(asl, ensure_ascii=False)) + '::jsonb' if asl else 'null'})")

    # ---------------- Bifoza
    bif = []
    for i, r in enumerate(wb["Bifoza sverka"].iter_rows(min_row=5, values_only=True), 5):
        if not matn(r[1]):
            continue
        bif.append(f"  ({q(matn(r[0]))}, {q(matn(r[1]))}, {q(matn(r[2]) if not isinstance(r[2], (int, float)) else str(int(r[2])))}, "
                   f"{q(sana(r[3]))}, {q(r[4] or 0)}, {q(r[5] or 0)}, {q(matn(r[8]))}, {i})")
    w(f"-- Bifoza qoldiq ({len(bif)} ta, 15.11.2026 holati)")
    w("insert into bifoza_qoldiq (turi, nomi, telefon, oxirgi_savdo, bizga_qarz, biz_qarz, izoh, tartib) values")
    w(",\n".join(bif) + ";\n")

    # ---------------- Sex
    sex = {}
    for i, r in enumerate(wb["Sex ostatka"].iter_rows(min_row=4, values_only=True), 4):
        if matn(r[0]) and matn(r[0]) not in sex:
            sex[matn(r[0])] = (r[1] if isinstance(r[1], (int, float)) else None, i)
    w(f"-- Sex mahsulotlari ({len(sex)} ta)")
    w("insert into sex_mahsulotlar (nomi, boshlangich_qoldiq, tartib) values")
    w(",\n".join(f"  ({q(n)}, {q(b)}, {t})" for n, (b, t) in sex.items()) + ";\n")

    kirim = [r for r in wb["Sex kirim"].iter_rows(min_row=2, values_only=True)
             if matn(r[1]) and isinstance(r[3], (int, float))]
    if kirim:
        w(f"-- Sex kirim ({len(kirim)} ta)")
        w("insert into sex_kirim (sana, mahsulot, olchov, soni, izoh) values")
        w(",\n".join(f"  ({q(sana(r[0]))}, {q(matn(r[1]))}, {q(matn(r[2]))}, {q(r[3])}, {q(matn(r[4]))})"
                     for r in kirim) + ";\n")

    # ---------------- O'zgarishlar jurnali
    oz = [r for r in wb["Ozgarishlar"].iter_rows(min_row=2, values_only=True) if bor(r, 4)]
    w(f"-- O'zgarishlar jurnali ({len(oz)} ta)")
    w("insert into ozgarishlar (qator, eski, yangi, sabab, tartib) values")
    w(",\n".join(f"  ({q(matn(r[0]))}, {q(matn(r[1]))}, {q(matn(r[2]))}, {q(matn(r[3]))}, {i})"
                 for i, r in enumerate(oz, 1)) + ";\n")

    w("commit;")
    w("")
    w("-- Tekshirish: Sheets'dagi Mijozlar → Колдик bilan solishtiring")
    w("-- select nomi, qoldiq, holat from mijoz_qoldiq where qoldiq <> 0 order by tartib;")


    os.makedirs(chiqish, exist_ok=True)
    with open(os.path.join(chiqish, "03_malumotlar.sql"), "w", encoding="utf-8") as f:
        f.write("\n".join(out) + "\n")

    # Arxiv katta — SQL Editor ko'tarishi uchun bir necha faylga bo'linadi
    BOLAK = 2000
    for n, k in enumerate(range(0, len(arxiv), BOLAK), 1):
        qism = arxiv[k:k + BOLAK]
        with open(os.path.join(chiqish, f"04_arxiv_{n}.sql"), "w", encoding="utf-8") as f:
            f.write(f"-- LUMANT ERP — Arxiv, {n}-qism ({len(qism)} ta qator). 03_malumotlar.sql dan keyin.\n")
            f.write("-- Takror ishga tushirsangiz, mavjud qatorlar o'tkazib yuboriladi.\n")
            f.write("insert into arxiv (qator, sana, sana_matn, nomi, mahsulot, olchov, miqdor, narx, summa,"
                    " avto_raqami, izoh, qulf, kiritgan_ismi, kiritilgan_vaqt, asl_matn) values\n")
            f.write(",\n".join(qism) + "\non conflict (qator) do nothing;\n")

    print(f"mahsulot={len(mahsulot)} mijoz={len(mijoz)} yozuv={len(asosiy)} arxiv={len(arxiv)} "
          f"bifoza={len(bif)} sex={len(sex)} kirim={len(kirim)} ozgarish={len(oz)}")


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    main(sys.argv[1], sys.argv[2])
