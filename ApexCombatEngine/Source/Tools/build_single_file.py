#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Apex Combat Engine - TEK DOSYA DERLEYICI (build script)

Amac: MetaEditor'da #include "..." (tirnakli goreli include) cozumlemesi
kullanicinin dosya yerlesimine gore degisir ve sik sik
   file 'Experts\\ApexTypes.mqh' not found
hatasi uretir. Bu script tum modulleri dogru bagimlilik sirasinda tek bir
.mq5 dosyasina gomer; boylece derleme HICBIR klasor yapisina bagimli olmaz.

Kullanim:
    python3 Tools/build_single_file.py

Cikti:
    ApexCombatEngine_SingleFile.mq5   <- MQL5/Experts/ icine atilip derlenir
                                         (tek dosya, baska dosya gerekmez)

Not: Standart kutuphane include'lari (#include <Trade/Trade.mqh>) KORUNUR;
     yalnizca tirnakli proje include'lari kaldirilir.
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # .../ApexCombatEngine
SRC = os.path.join(ROOT, "Source")
os.chdir(SRC)

MAIN = "ApexCombatEngine.mq5"
OUT = os.path.join(ROOT, "ApexCombatEngine_SingleFile.mq5")

# Bagimlilik sirasi: her modul yalnizca kendisinden oncekileri kullanir
MODULES = [
    "ApexTypes.mqh",        # katman 0
    "ApexTrade.mqh",        # katman 1 (CTrade + defter)
    "ApexSqueezeCore.mqh",  # katman 1 (LazyBear)
    "ApexAnalytics.mqh",    # katman 2
    "ApexRisk.mqh",         # katman 2
    "ApexGrid.mqh",         # katman 3
    "ApexScalp.mqh",        # katman 3
]

QUOTED_INCLUDE = re.compile(r'^\s*#include\s+"')


def read(path):
    with open(path, "r", encoding="utf-8") as fh:
        return fh.read()


def strip_quoted_includes(text):
    keep = []
    for line in text.split("\n"):
        if QUOTED_INCLUDE.match(line):
            continue
        keep.append(line)
    return "\n".join(keep)


def split_main(text):
    """Ana EA'yi include blogundan ikiye ayir: (ust kisim, govde).

    Ayrica `input` satirlari govdeden cikarilip ust kisma (property'lerin
    altina) tasinir: boylece tek dosya surumu de klasik EA duzenine
    (property -> input -> kod) uyar.
    """
    lines = text.split("\n")
    first = None
    last = None
    for i, line in enumerate(lines):
        if QUOTED_INCLUDE.match(line):
            if first is None:
                first = i
            last = i
    if first is None or last is None:
        raise SystemExit("HATA: ana EA dosyasinda quoted include blogu bulunamadi.")

    head = "\n".join(lines[:first]).rstrip()
    rest = lines[last + 1:]

    inputs = [l for l in rest if l.startswith("input ")]
    body_lines = [l for l in rest if not l.startswith("input ")]

    if inputs:
        head_lines = head.split("\n")
        # son #property satirindan sonra input'lari yerlestir
        idx = 0
        for i, l in enumerate(head_lines):
            if l.startswith("#property"):
                idx = i + 1
        head = "\n".join(head_lines[:idx] + [""] + inputs + head_lines[idx:])

    body = "\n".join(body_lines).strip()
    return head, body


def main():
    main_text = read(MAIN)
    head, body = split_main(main_text)

    banner_lines = [
        "",
        "  ***  DERLENECEK TEK DOSYA BUDUR  ***",
        "",
        "  Bu dosya KENDI KENDINE YETERLIDIR: hicbir .mqh dosyasina ihtiyac",
        "  duymaz (7 modul icine gomuludur). Tek dis bagimlilik standart",
        "  kutuphane olan  #include <Trade/Trade.mqh>  dir.",
        "",
        "  ONEMLI: MQL5\\Experts klasorunde ApexCombatEngine.mq5,",
        "  ApexCombatEngine (1).mq5, (2), (3) ... gibi ESKI KOPYALAR ile",
        "  ApexTypes.mqh / ApexTrade.mqh / ... gibi .mqh dosyalari varsa",
        "  SILIN. Onlar moduler kaynak surumudur ve yanlarinda .mqh",
        "  dosyalari olmadan DERLENMEZ ('file not found' hatasi verir).",
        "",
        "  Kaynak: Source/ klasorundedir (gelistirme icin).",
        "  Bu dosyayi duzenlemeyin; Source icindeki modulleri degistirip",
        "  `python3 Source/Tools/build_single_file.py` ile yeniden uretin.",
        "",
    ]
    banner = ("//" + "=" * 78)
    for bl in banner_lines:
        banner += "\n//|" + bl
    banner += "\n//" + "=" * 78
    parts = [banner, ""]
    parts.append("//" + "-" * 78)
    parts.append("//  Asagidaki kisim Source/ApexCombatEngine.mq5 basligidir.")
    parts.append("//" + "-" * 78)
    parts.append(head)
    parts.append("")

    for mod in MODULES:
        if not os.path.exists(mod):
            raise SystemExit("HATA: modul bulunamadi -> %s" % mod)
        parts.append("//" + "=" * 78)
        parts.append("//| MODUL: %s" % mod)
        parts.append("//" + "=" * 78)
        parts.append(strip_quoted_includes(read(mod)).strip())
        parts.append("")

    parts.append("//" + "=" * 78)
    parts.append("//| ANA EA GOVDE (ApexCombatEngine.mq5)")
    parts.append("//" + "=" * 78)
    parts.append(body)

    out = "\n".join(parts)
    with open(OUT, "w", encoding="utf-8") as fh:
        fh.write(out)

    # --- dogrulama ---
    problems = []
    if out.count("int OnInit()") != 1:
        problems.append("OnInit sayisi != 1")
    if out.count("void OnTick()") != 1:
        problems.append("OnTick sayisi != 1")
    for sym in ("g_exec", "g_risk", "g_grid", "g_scalp", "g_analytics",
                "g_sqz_main", "g_sqz_ctx", "g_sqz_scalp"):
        if out.count("CApexExecution g_exec") if sym == "g_exec" else False:
            pass
    # global ornekler tam olarak bir kez tanimlanmali
    for decl in ("CApexExecution g_exec;", "CApexSqueeze g_sqz_main;",
                 "CApexAnalytics g_analytics;", "CApexRisk g_risk;",
                 "CApexGrid g_grid;", "CApexScalp g_scalp;"):
        if out.count(decl) != 1:
            problems.append("global ornek tanimi hatali: %s (%d)" % (decl, out.count(decl)))
    # her sinif yalnizca bir kez tanimlanmali
    for cls in ("CApexExecution", "CApexSqueeze", "CApexAnalytics",
                "CApexRisk", "CApexGrid", "CApexScalp"):
        n = len(re.findall(r'\bclass\s+%s\b' % cls, out))
        if n != 1:
            problems.append("sinif tanimi %d kez: %s" % (n, cls))
    # parantez dengesi
    chk = re.sub(r'//[^\n]*', '', out)
    chk = re.sub(r'/\*.*?\*/', '', chk, flags=re.S)
    chk = re.sub(r'"(\\.|[^"\\])*"', '""', chk)
    stack = []
    pairs = {'{': '}', '(': ')', '[': ']'}
    for ch in chk:
        if ch in pairs:
            stack.append(ch)
        elif ch in pairs.values():
            if not stack or pairs[stack.pop()] != ch:
                problems.append("parantez dengesi bozuk")
                break
    if stack:
        problems.append("kapatilmamis %d parantez" % len(stack))

    # ---- Proje ici TANIMSIZ tanimlayici avi (undeclared identifier) ----
    # 'chk' = yorum/string temizlenmis kaynak (yukarida hesaplandi).
    nc = chk

    # Daha once APX_SQZ_ON -> APX_SQZST_ON donusumunde bir kullanim gozden
    # kacmis ve derleyici "undeclared identifier" vermisti. Bir daha olmasin.
    PREFIX = (r'APX_', r'APEX_', r'E_APEX_', r'REGIME_', r'GRID_', r'POSTURE_',
              r'ROLE_', r'PERSIST_', r'VOLBAND_', r'VP_', r'LEG_', r'TIER_', r'SQZ_')
    decl = set()
    for mm in re.finditer(r'enum\s+(\w+)\s*\{([^}]*)\}', nc):
        decl.add(mm.group(1))
        for line in mm.group(2).split(','):
            nm = re.match(r'\s*(\w+)', line)
            if nm: decl.add(nm.group(1))
    decl |= set(re.findall(r'#define\s+(\w+)', nc))
    decl |= set(re.findall(r'^\s*(?:const\s+)?(?:input\s+)?\w+\s+(\w+)\s*(?:\[[^]]*\])?\s*[=;]', nc, re.M))
    decl |= set(re.findall(r'\b(?:void|bool|int|double|string|ulong|long|uint|datetime|float|char|short|uchar)\s+(\w+)\s*\(', nc))
    decl |= set(re.findall(r'^(?:class|struct)\s+(\w+)', nc, re.M))
    used = set()
    for px in PREFIX:
        used |= set(re.findall(r'\b' + px + r'[A-Z0-9_]*\b', nc))
    # struct/class uyeleri (kucuk harfli) da tanimlidir
    undeclared = sorted(u for u in used if u not in decl)
    if undeclared:
        problems.append("TANIMSIZ proje tanimlayicilari: %s" % ", ".join(undeclared))

    # MQL5'te enum uyeleri GLOBAL isim uzayinda yasar: ayni isim iki farkli
    # enumda gecerse "identifier already used" hatasi verir.
    enum_members = {}
    for m in re.finditer(r'enum\s+(\w+)\s*\{([^}]*)\}', nc):
        for line in m.group(2).split(','):
            name = re.match(r'\s*(\w+)', line)
            if name:
                enum_members.setdefault(name.group(1), []).append(m.group(1))
    for name, enums in enum_members.items():
        if len(enums) > 1:
            problems.append("enum uyesi %s birden fazla enumda tanimli: %s" % (name, enums))

    # uretilen dosyada yorum-disinda kalan "banner artigi" satir var mi?
    # (ornegin //| ile baslamayan "|  TEK DOSYA SURUM ..." satiri derleyiciyi
    #  raydan cikarip onlarca zincirleme hata uretir)
    for i, l in enumerate(out.split("\n"), 1):
        st = l.strip()
        if not st:
            continue
        if st.startswith("//") or st.startswith("#"):
            continue
        if st[0] == "|":   # yalnizca banner artiklari (| ile baslayan satir)
            problems.append("yorum degil gibi gorunen satir %d: %s" % (i, st[:60]))

    lines = out.count("\n") + 1
    if problems:
        print("URETILDI AMA SORUN VAR:")
        for p in problems:
            print("  -", p)
        sys.exit(1)
    print("OK: %s uretildi (%d satir, %d modul gomulu)" % (OUT, lines, len(MODULES)))


if __name__ == "__main__":
    main()
