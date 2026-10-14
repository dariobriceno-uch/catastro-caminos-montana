# -*- coding: utf-8 -*-
"""
a7_nieve_ee.py — Bloque A7 (cobertura nival, FT-08): lanza en Google Earth Engine
el cálculo de días con nieve por tramo y lo exporta a Google Drive.

No escribe ningún valor en la base. Produce, por región, un CSV con los
conteos por tramo que luego se guardan INTACTOS en data/raw/nieve/ con su
entrada en manifest (Regla 3). a7_nieve.R los lee y arma las columnas A7.

Método (decidido 2026-08-27, docs/esquema.md bloque A7):
  producto      MODIS/061/MOD10A1, banda NDSI_Snow_Cover (Terra, diario, 500 m)
  serie         2010-01-01 .. 2024-12-31 (15 años completos)
  día con nieve NDSI_Snow_Cover >= 40 (umbral de la máscara binaria de NASA)
  válido        NDSI_Snow_Cover en 0..100 (los códigos 200..255 —nube, noche,
                agua, sin decisión, relleno— se excluyen)
  por píxel y año:  nieve = nº de días con nieve;  valido = nº de días válidos
  por píxel y mes:  lo mismo, para los 12 meses de cada año
  por tramo:    mediana de los píxeles dentro de un buffer de 500 m sobre la
                geometría del tramo (= 1 píxel MODIS a cada lado)
  escalado a 365 y estadísticos anuales: en a7_nieve.R, no aquí.

Uso:
  python src/01_descarga/a7_nieve_ee.py --proyecto ee-mi-proyecto [--region "Región de Atacama"] [--solo-listar]

Requiere `earthengine authenticate` hecho en esta máquina.
"""
import argparse
import json
import os
import sys
from datetime import datetime, timezone

RAIZ = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
GPKG = os.path.join(RAIZ, "data", "processed", "tramos.gpkg")
ESTADO = os.path.join(RAIZ, "data", "raw", "nieve", "tareas_ee.json")

PRODUCTO = "MODIS/061/MOD10A1"
BANDA = "NDSI_Snow_Cover"
ANIO_INI, ANIO_FIN = 2010, 2024
UMBRAL_NDSI = 40
BUFFER_M = 500
SIMPLIFICAR_M = 50          # la geometría viaja en la petición; 50 m basta para un píxel de 500 m
CARPETA_DRIVE = "FONDEF_nieve"
ESCALA_M = 500


def imagen_conteos(ee):
    """Una imagen con 2 bandas por año (nieve_YYYY, valido_YYYY) y 2 por mes
    (nieve_YYYY_MM, valido_YYYY_MM), calculadas píxel a píxel."""
    col = ee.ImageCollection(PRODUCTO).select(BANDA)
    bandas = []
    for a in range(ANIO_INI, ANIO_FIN + 1):
        anio = col.filterDate("%d-01-01" % a, "%d-01-01" % (a + 1))
        valido = anio.map(lambda im: im.lte(100)).sum().rename("valido_%d" % a)
        nieve = anio.map(lambda im: im.lte(100).And(im.gte(UMBRAL_NDSI))).sum().rename("nieve_%d" % a)
        bandas += [nieve, valido]
        for m in range(1, 13):
            ini = ee.Date.fromYMD(a, m, 1)
            mes = anio.filterDate(ini, ini.advance(1, "month"))
            bandas.append(mes.map(lambda im: im.lte(100)).sum().rename("valido_%d_%02d" % (a, m)))
            bandas.append(mes.map(lambda im: im.lte(100).And(im.gte(UMBRAL_NDSI))).sum()
                          .rename("nieve_%d_%02d" % (a, m)))
    return ee.Image.cat(bandas).toInt16()


def tramos_por_region():
    """Lee tramos.gpkg y devuelve {region: [(id_tramo, geojson_simplificado), ...]}."""
    import subprocess
    # R ya tiene sf; se delega ahí la simplificación para no depender de GDAL en Python
    script = r'''
suppressMessages(library(sf)); library(jsonlite)
g <- st_read("%s", "tramos", quiet=TRUE)
g <- st_zm(g); g <- g[, c("id_tramo","region")]
s <- st_simplify(g, dTolerance = %d, preserveTopology = TRUE)
vac <- st_is_empty(s); st_geometry(s)[vac] <- st_geometry(g)[vac]   # tramos cortos que colapsan: geometría original
s <- st_transform(s, 4326)
out <- split(seq_len(nrow(s)), s$region)
res <- lapply(out, function(ix) lapply(ix, function(i) list(id = s$id_tramo[i], g = st_as_text(st_geometry(s)[i]))))
cat(toJSON(res, auto_unbox = TRUE))
''' % (GPKG.replace("\\", "/"), SIMPLIFICAR_M)
    # caché: la extracción tarda ~2 min y la geometría no cambia entre lanzamientos
    cache = os.path.join(RAIZ, "data", "interim", "a7_tramos_region.json")
    if os.path.exists(cache) and os.path.getmtime(cache) > os.path.getmtime(GPKG):
        return json.load(open(cache, encoding="utf-8"))
    import tempfile
    tmp = os.path.join(tempfile.gettempdir(), "a7_tramos_region.R")
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(script)
    r = subprocess.run(["C:/Program Files/R/R-4.5.2/bin/Rscript.exe", tmp],
                       capture_output=True, text=True, encoding="utf-8", errors="replace")
    if r.returncode != 0:
        sys.exit("error leyendo tramos con R:\n" + r.stderr[-2000:])
    res = json.loads(r.stdout)
    json.dump(res, open(cache, "w", encoding="utf-8"), ensure_ascii=False)
    return res


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--proyecto", required=True, help="ID del proyecto de Google Cloud registrado en EE")
    ap.add_argument("--region", action="append", help="procesar solo esta(s) región(es)")
    ap.add_argument("--solo-listar", action="store_true", help="mostrar el estado de las tareas y salir")
    ap.add_argument("--lote", type=int, default=600, help="tramos por tarea (las regiones grandes se parten)")
    a = ap.parse_args()

    import ee
    ee.Initialize(project=a.proyecto)

    os.makedirs(os.path.dirname(ESTADO), exist_ok=True)
    estado = json.load(open(ESTADO, encoding="utf-8")) if os.path.exists(ESTADO) else {}

    if a.solo_listar:
        for t in ee.batch.Task.list()[:40]:
            print("%-40s %-12s %s" % (t.config.get("description", "")[:40], t.state, t.id))
        return

    img = imagen_conteos(ee)
    regiones = tramos_por_region()
    print("regiones:", len(regiones), " tramos:", sum(len(v) for v in regiones.values()))

    import unicodedata, re
    lotes = []
    for region, lista in sorted(regiones.items()):
        if a.region and region not in a.region:
            continue
        # EE solo admite a-z, 0-9 y . , : ; _ - en el nombre de la tarea: fuera tildes
        base = unicodedata.normalize("NFKD", region).encode("ascii", "ignore").decode()
        base = re.sub(r"[^A-Za-z0-9_.-]+", "_", base).strip("_")
        # una region entera en una peticion supera el limite de EE ("Computed
        # value is too large") desde ~2.000 tramos: se parte en lotes
        if len(lista) <= a.lote:
            lotes.append((region, base, lista))
        else:
            n = -(-len(lista) // a.lote)
            for k in range(n):
                lotes.append((region, "%s_p%d" % (base, k + 1), lista[k * a.lote:(k + 1) * a.lote]))

    for region, clave, lista in lotes:
        if estado.get(clave, {}).get("estado") in ("RUNNING", "READY", "COMPLETED"):
            print("salta", clave, "(ya lanzada:", estado[clave]["estado"] + ")")
            continue
        feats = [ee.Feature(ee.Geometry(json.loads(json.dumps(_wkt_a_geojson(t["g"])))), {"id_tramo": t["id"]})
                 for t in lista]
        fc = ee.FeatureCollection(feats).map(lambda f: f.buffer(BUFFER_M))
        red = img.reduceRegions(collection=fc, reducer=ee.Reducer.median(), scale=ESCALA_M,
                                tileScale=4)
        red = red.map(lambda f: f.setGeometry(None))
        desc = "nieve_" + clave[:80]
        tarea = ee.batch.Export.table.toDrive(collection=red, description=desc,
                                              folder=CARPETA_DRIVE, fileNamePrefix=desc,
                                              fileFormat="CSV")
        tarea.start()
        estado[clave] = {"region": region, "n_tramos": len(lista), "tarea": tarea.id,
                         "estado": "READY", "lanzada_utc": datetime.now(timezone.utc).isoformat(),
                         "producto": PRODUCTO, "serie": [ANIO_INI, ANIO_FIN],
                         "umbral_ndsi": UMBRAL_NDSI, "buffer_m": BUFFER_M,
                         "simplificacion_m": SIMPLIFICAR_M, "carpeta_drive": CARPETA_DRIVE}
        json.dump(estado, open(ESTADO, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
        print("lanzada", clave, "(%d tramos)" % len(lista), tarea.id)

    print("\nLas tareas corren en el servidor de EE. Cuando terminen, los CSV quedan en")
    print("Drive/%s. Descárgalos a data/raw/nieve/ y corre a7_nieve.R." % CARPETA_DRIVE)


def _wkt_a_geojson(wkt):
    """WKT (MULTI)LINESTRING -> GeoJSON, sin dependencias. Tolera los espacios
    que sf pone tras el tipo y entre partes: 'MULTILINESTRING ((..), (..))'."""
    import re
    tipo = wkt.strip().split("(", 1)[0].strip().upper()
    partes = [[[float(x) for x in par.split()] for par in grupo.split(",")]
              for grupo in re.findall(r"\(([^()]+)\)", wkt)]
    if tipo == "LINESTRING":
        return {"type": "LineString", "coordinates": partes[0]}
    if tipo == "MULTILINESTRING":
        return {"type": "MultiLineString", "coordinates": partes}
    raise ValueError("geometría no esperada: " + tipo)


if __name__ == "__main__":
    main()
