# -*- coding: utf-8 -*-
"""
a4_descarga_osm_esqui.py — descarga desde OpenStreetMap (Overpass API) las
áreas y centros de esquí de Chile. Fuente FT-12, licencia ODbL.

Guarda la respuesta cruda en data/raw/osm_esqui/ (Regla 3) y registra la
descarga en data/raw/manifest/A4_osm.json con la consulta exacta, la URL,
el timestamp y el sha256. No transforma nada.

Qué se pide a OSM (todo dentro del área ISO3166-1 = CL):
  landuse=winter_sports          polígonos/relaciones de dominio esquiable
  sport=skiing + name            puntos o áreas con nombre
  aerialway=station              estaciones de andarivel (para ubicar la base)
"""
import hashlib
import json
import os
from datetime import datetime, timezone

import requests

RAIZ = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DESTINO = os.path.join(RAIZ, "data", "raw", "osm_esqui")
URL = "https://overpass-api.de/api/interpreter"
CONSULTA = """
[out:json][timeout:180];
area["ISO3166-1"="CL"][admin_level=2]->.cl;
(
  way["landuse"="winter_sports"](area.cl);
  relation["landuse"="winter_sports"](area.cl);
  node["sport"="skiing"]["name"](area.cl);
  way["sport"="skiing"]["name"](area.cl);
  relation["sport"="skiing"]["name"](area.cl);
  node["aerialway"="station"](area.cl);
);
out body center tags;
"""


def main():
    os.makedirs(DESTINO, exist_ok=True)
    ts = datetime.now(timezone.utc)
    r = requests.post(URL, data={"data": CONSULTA}, timeout=300,
                      headers={"User-Agent": "catastro-caminos-montana-FONDEF (dario.briceno@ug.uchile.cl)"})
    r.raise_for_status()
    crudo = r.content
    nombre = "osm_esqui_chile_%s.json" % ts.strftime("%Y%m%dT%H%M%SZ")
    ruta = os.path.join(DESTINO, nombre)
    open(ruta, "wb").write(crudo)
    d = json.loads(crudo)
    n = len(d.get("elements", []))
    sha = hashlib.sha256(crudo).hexdigest()

    man = [{
        "fuente": "FT-12",
        "archivo": os.path.relpath(ruta, RAIZ).replace("\\", "/"),
        "url": URL,
        "consulta_overpass": CONSULTA.strip(),
        "timestamp_utc": ts.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "n_registros": n,
        "sha256": sha,
        "agente": "A4",
        "notas": "OpenStreetMap vía Overpass; licencia ODbL 1.0 (© colaboradores de OpenStreetMap); "
                 "osm3s timestamp=%s" % d.get("osm3s", {}).get("timestamp_osm_base", ""),
    }]
    with open(os.path.join(RAIZ, "data", "raw", "manifest", "A4_osm.json"), "w", encoding="utf-8") as f:
        json.dump(man, f, ensure_ascii=False, indent=1)
    print("guardado", ruta, "%d elementos, %.0f KB, sha256 %s" % (n, len(crudo) / 1024, sha[:12]))

    # resumen informativo (no escribe nada en la base)
    from collections import Counter
    c = Counter()
    for e in d["elements"]:
        t = e.get("tags", {})
        if t.get("landuse") == "winter_sports": c["landuse=winter_sports"] += 1
        elif t.get("sport") == "skiing": c["sport=skiing con nombre"] += 1
        elif t.get("aerialway") == "station": c["aerialway=station"] += 1
    print(dict(c))
    print("\nnombres de dominios / centros:")
    vistos = set()
    for e in d["elements"]:
        t = e.get("tags", {})
        if (t.get("landuse") == "winter_sports" or t.get("sport") == "skiing") and t.get("name"):
            if t["name"] in vistos: continue
            vistos.add(t["name"])
            c0 = e.get("center", e)
            print("  %-45s %s  %.4f %.4f  %s" % (t["name"][:45], e["type"], c0.get("lat", 0), c0.get("lon", 0),
                                                 t.get("ele", "")))


if __name__ == "__main__":
    main()
