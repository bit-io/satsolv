#!/usr/bin/env python3
"""Pilnuje kolizji nazw w satsolv (ten sam blad, ktory psul kompilacje LLVM).

Funkcja `fn f` w module `m` ma po spłaszczeniu nazwe `m_f`. Jesli ta nazwa jest
rowna symbolowi z bloku `extern` albo eksportowi libsolv, wrapper nadpisuje
extern (nieskonczona rekurencja / "Incorrect number of arguments"). Stale
(`pub const`) sa globalne — nazwy musza byc unikalne w calym projekcie.

Uzycie:
  scripts/check-symbols.py                         # sprawdza src/
  scripts/check-symbols.py --ver DIR               # + eksporty z DIR/libsolv.ver, libsolvext.ver
  scripts/check-symbols.py --archives DIR          # + czy kazdy extern istnieje w DIR/libsolv.a, libsolvext.a (nm)
Kod wyjscia != 0 gdy cos jest nie tak.
"""
import argparse, collections, pathlib, re, subprocess, sys

ap = argparse.ArgumentParser()
ap.add_argument('--src', default=str(pathlib.Path(__file__).resolve().parent.parent / 'src'))
ap.add_argument('--ver'); ap.add_argument('--archives')
a = ap.parse_args()
src = pathlib.Path(a.src)

LIBC = {'tmpfile', 'fopen', 'fputs', 'fclose', 'rewind'}
ffi = (src / 'ffi.h#').read_text(encoding='utf-8')
externs = set(re.findall(r'^    fn (\w+)\(', ffi, re.M))
fns = collections.defaultdict(list); consts = collections.defaultdict(list)
for f in sorted(src.glob('*.h#')):
    if f.stem in ('lib', 'ffi'): continue
    for l in f.read_text(encoding='utf-8').split('\n'):
        m = re.match(r'^(?:pub )?fn (\w+)\(', l)
        if m: fns[f'{f.stem}_{m.group(1)}'].append(f'{f.stem}::{m.group(1)}')
        c = re.match(r'^pub const (\w+)\s*:', l)
        if c: consts[c.group(1)].append(f.stem)

exports = set()
if a.ver:
    for n in ('libsolv.ver', 'libsolvext.ver'):
        p = pathlib.Path(a.ver) / n
        if p.exists(): exports |= set(re.findall(r'^\s+(\w+);', p.read_text(), re.M))

bad = 0
for n, w in fns.items():
    if n in externs: print(f'KOLIZJA z extern: {w} -> {n}'); bad += 1
    if n in exports: print(f'KOLIZJA z eksportem libsolv: {w} -> {n}'); bad += 1
    if len(w) > 1: print(f'DUPLIKAT funkcji: {n} {w}'); bad += 1
for n, w in consts.items():
    if len(w) > 1: print(f'DUPLIKAT stalej {n}: {w}'); bad += 1
    if n in fns or n in externs or n in exports: print(f'stala {n} koliduje z funkcja/symbolem'); bad += 1

if a.archives:
    out = subprocess.run(['nm', '-g', '--defined-only', *[str(p) for p in pathlib.Path(a.archives).glob('libsolv*.a')]],
                         capture_output=True, text=True).stdout
    defs = set(re.findall(r'\bT (\w+)$', out, re.M))
    for e in sorted(externs - LIBC):
        if e not in defs: print(f'extern {e} nie istnieje w archiwach'); bad += 1

print(f'{len(fns)} funkcji, {len(consts)} stalych, {len(externs)} externow -> {bad} problemow')
sys.exit(1 if bad else 0)
