#!/usr/bin/env python3
import unicodedata

RANGES = [
    (0x1F300, 0x1FAFF),
    (0x2600, 0x27BF),
    (0x2190, 0x21FF),
    (0x2B00, 0x2BFF),
    (0x2900, 0x297F),
    (0x2200, 0x22FF),
    (0x2300, 0x23FF),
    (0x25A0, 0x25FF),
    (0x2500, 0x257F),
    (0x2460, 0x24FF),
    (0x2100, 0x214F),
    (0x20A0, 0x20C0),
    (0x2010, 0x205E),
    (0x00A1, 0x00FF),
]

for first, last in RANGES:
    for point in range(first, last + 1):
        char = chr(point)
        if unicodedata.category(char)[0] not in "SP" or 0x1F3FB <= point <= 0x1F3FF:
            continue
        name = unicodedata.name(char, "")
        if name:
            print(f"{char}\t{name.lower()}")
