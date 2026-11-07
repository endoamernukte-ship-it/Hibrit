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

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
os.chdir(HERE)

MAIN = "ApexCombatEngine.mq5"
OUT = "ApexCombatEngine_SingleFile.mq5"

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

    parts = [head, ""]
    banner = ("//+------------------------------------------------------------------+\n"
              "|  TEK DOSYA SURUM - otomatik uretildi (Tools/build_single_file.py) |\n"
              "|  Kaynak: ApexCombatEngine.mqh moduler seti                        |\n"
              "|  BU DOSYAYI DUZENLEMEYIN; modulleri duzenleyip yeniden uretin.    |\n"
              "+------------------------------------------------------------------+")
    parts.append(banner)
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

    lines = out.count("\n") + 1
    if problems:
        print("URETILDI AMA SORUN VAR:")
        for p in problems:
            print("  -", p)
        sys.exit(1)
    print("OK: %s uretildi (%d satir, %d modul gomulu)" % (OUT, lines, len(MODULES)))


if __name__ == "__main__":
    main()
