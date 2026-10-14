# A5 - Manifest de FT-02 (planillas + REST + ficha). Ejecutar desde la raiz: python src/01_descarga/a5_manifest_censo.py
# Requiere data/interim/a5_prep_resumen_planillas.csv (lo escribe src/03_derivacion/a5_prep_planillas.R).
import hashlib, json, os, re
root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
os.chdir(root)

def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()

# URLs exactas de las planillas, tomadas de la ficha guardada
ficha = open("data/raw/censo_rest/ficha_plan_nacional_censo_vial.html", encoding="utf-8", errors="replace").read()
links = re.findall(r'href="([^"]+\.xls)"', ficha, flags=re.I)
url_by_name = {os.path.basename(u): u for u in links}

entries = []
xls_dir = "data/raw/Censo Nacional"
for fn in sorted(os.listdir(xls_dir)):
    if not fn.lower().endswith(".xls"):
        continue
    p = os.path.join(xls_dir, fn)
    entries.append({
        "fuente": "FT-02",
        "archivo": p.replace("\\", "/"),
        "url": url_by_name.get(fn, "https://vialidad.mop.gob.cl/plan-nacional-de-censo-vial/ (enlace no localizado en la ficha)"),
        "timestamp_utc": "2026-08-26 (manual)",
        "n_registros": None,
        "sha256": sha(p),
        "agente": "A5",
        "notas": "Planilla regional FT-02, descargada a mano; n_registros se completa abajo desde la normalizacion" ,
    })

# conteo de filas de muestra por planilla, desde el parquet normalizado si existe
import csv
cnt = {}
with open("data/interim/a5_prep_resumen_planillas.csv", encoding="utf-8") as f:
    for r in csv.DictReader(f):
        cnt[r["archivo_origen"]] = cnt.get(r["archivo_origen"], 0) + int(r["n_filas"])
for e in entries:
    n = cnt.get(os.path.basename(e["archivo"]))
    if n is not None:
        e["n_registros"] = n
        e["notas"] = "Planilla regional FT-02, descargada a mano desde la ficha. n_registros = filas estacion-rama x muestra normalizadas."

base = "https://rest-sit.mop.gob.cl/arcgis/rest/services/VIALIDAD/Plan_Nacional_de_Censos/MapServer"
entries.append({
    "fuente": "FT-02", "archivo": "data/raw/censo_rest/service.pjson", "url": base + "?f=pjson",
    "timestamp_utc": "2026-08-26T18:05:00Z", "n_registros": 7, "sha256": sha("data/raw/censo_rest/service.pjson"),
    "agente": "A5", "notas": "Metadatos del servicio REST de respaldo; 7 capas de puntos (2014-2025)."})
for i in range(7):
    meta = json.load(open(f"data/raw/censo_rest/layer_{i}_meta.pjson", encoding="utf-8"))
    entries.append({
        "fuente": "FT-02", "archivo": f"data/raw/censo_rest/layer_{i}_meta.pjson", "url": f"{base}/{i}?f=pjson",
        "timestamp_utc": "2026-08-26T18:05:00Z", "n_registros": len(meta.get("fields", [])),
        "sha256": sha(f"data/raw/censo_rest/layer_{i}_meta.pjson"), "agente": "A5",
        "notas": f"Metadatos capa {i} '{meta.get('name')}'; n_registros = numero de campos."})
    fp = f"data/raw/censo_rest/layer_{i}_p0.json"
    d = json.load(open(fp, encoding="utf-8"))
    entries.append({
        "fuente": "FT-02", "archivo": fp,
        "url": f"{base}/{i}/query?where=1%3D1&outFields=*&outSR=4326&f=json&resultOffset=0&resultRecordCount=1000",
        "timestamp_utc": "2026-08-26T18:05:47Z", "n_registros": len(d["features"]),
        "sha256": sha(fp), "agente": "A5",
        "notas": f"Capa {i} '{meta.get('name')}' completa en una pagina (exceededTransferLimit ausente). Esri JSON, puntos, outSR=4326."})
entries.append({
    "fuente": "FT-02", "archivo": "data/raw/censo_rest/ficha_plan_nacional_censo_vial.html",
    "url": "https://vialidad.mop.gob.cl/plan-nacional-de-censo-vial/",
    "timestamp_utc": "2026-08-26T18:08:08Z", "n_registros": len(links),
    "sha256": sha("data/raw/censo_rest/ficha_plan_nacional_censo_vial.html"), "agente": "A5",
    "notas": "Ficha oficial; evidencia de la leyenda de muestras (febrero=verano, junio=invierno, octubre=primavera) y de las URL de las 16 planillas. n_registros = enlaces .xls."})

os.makedirs("data/raw/manifest", exist_ok=True)
with open("data/raw/manifest/A5.json", "w", encoding="utf-8") as f:
    json.dump(entries, f, ensure_ascii=False, indent=2)
print("entradas:", len(entries), "| sin url:", sum("no localizado" in e["url"] for e in entries))
