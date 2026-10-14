"""Consolida data/raw/manifest/<agente>.json en data/raw/manifest.json (solo lectura de los parciales)."""
import json, glob, os
root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
entries = []
for f in sorted(glob.glob(os.path.join(root, "data/raw/manifest/*.json"))):
    with open(f, encoding="utf-8") as fh:
        d = json.load(fh)
    d = d if isinstance(d, list) else d.get("entradas", d.get("entries", [d]))
    entries.extend(d)
out = os.path.join(root, "data/raw/manifest.json")
with open(out, "w", encoding="utf-8") as fh:
    json.dump(entries, fh, ensure_ascii=False, indent=1)
from collections import Counter
print(len(entries), "entradas;", Counter(e.get("fuente") for e in entries))
