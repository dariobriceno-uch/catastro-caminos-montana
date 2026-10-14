# -*- coding: utf-8 -*-
"""
visor_html.py — ensambla el visor HTML autocontenido de tramos.

Toma data/interim/visor_payload.json.gz (producido por visor_payload.R) y los
modulos de src/04_ensamblaje/visor/, y escribe un unico archivo HTML sin
ninguna dependencia externa: sin CDN, sin tiles, sin red.
"""
import base64
import gzip
import hashlib
import io
import json
import os
import sys
from datetime import datetime

RAIZ = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
VISOR = os.path.join(RAIZ, "src", "04_ensamblaje", "visor")
PAYLOAD = os.path.join(RAIZ, "data", "interim", "visor_payload.json.gz")
SALIDA = os.path.join(RAIZ, "docs", "visor_tramos.html")

CSS = ["estilo_base.css", "mapa.css", "tabla.css", "ficha.css"]
JS = ["nucleo.js", "mapa.js", "tabla.js", "ficha.js", "arranque.js"]


def leer(nombre, obligatorio=True):
    ruta = os.path.join(VISOR, nombre)
    if not os.path.exists(ruta):
        if obligatorio:
            sys.exit("falta el modulo %s" % ruta)
        return ""
    with io.open(ruta, encoding="utf-8") as f:
        return f.read()


def sin_columnas_vacias(crudo):
    """Quita del visor las columnas sin ningun valor en la base (100% NULL).

    El payload de data/interim/ queda intacto, porque test_visor.R lo contrasta
    columna a columna con el parquet; el recorte ocurre solo en lo que se
    incrusta en el HTML. Si una fuente llega a poblar una de estas columnas,
    vuelve a aparecer en el visor sin tocar este archivo.
    """
    P = json.loads(gzip.decompress(crudo).decode("utf-8"))
    n = P["meta"]["n_tramos"]
    vacias = [c["n"] for c in P["cols"] if c["nulos"] >= n]
    if not vacias:
        return crudo, []
    P["cols"] = [c for c in P["cols"] if c["n"] not in vacias]
    for clave in ("data", "dicts", "proc", "proc_var", "desc"):
        for col in vacias:
            (P.get(clave) or {}).pop(col, None)
    P["meta"]["columnas_omitidas"] = vacias
    txt = json.dumps(P, ensure_ascii=False, separators=(",", ":"), allow_nan=False)
    return gzip.compress(txt.encode("utf-8"), compresslevel=9, mtime=0), vacias


def main():
    salida = SALIDA
    if "--salida" in sys.argv:
        salida = os.path.abspath(sys.argv[sys.argv.index("--salida") + 1])
    if not os.path.exists(PAYLOAD):
        sys.exit("falta %s — corre primero src/04_ensamblaje/visor_payload.R" % PAYLOAD)

    crudo, omitidas = sin_columnas_vacias(open(PAYLOAD, "rb").read())
    b64 = base64.b64encode(crudo).decode("ascii")
    sha = hashlib.sha256(crudo).hexdigest()

    parquet = os.path.join(RAIZ, "data", "processed", "tramos.parquet")
    sha_parquet = ""
    if os.path.exists(parquet):
        h = hashlib.sha256()
        with open(parquet, "rb") as f:
            for bloque in iter(lambda: f.read(1 << 20), b""):
                h.update(bloque)
        sha_parquet = h.hexdigest()

    piezas_css = [(n, leer(n, n == "estilo_base.css")) for n in CSS]
    piezas_js = [(n, leer(n)) for n in JS]

    # Un stub inlineado produce una pagina que dice tener 18.368 tramos y no
    # muestra ninguno. Es la falla que REGLAS.md llama "publicar una tabla sin
    # geometria": el ensamblador no puede dejarla pasar en silencio.
    stubs = [n for n, t in piezas_css + piezas_js if "STUB de" in t or "stub */" in t]
    if stubs:
        sys.exit("los modulos %s siguen siendo stubs; no se ensambla el visor"
                 % ", ".join(stubs))

    css = "\n".join("/* === %s === */\n%s" % (n, t) for n, t in piezas_css)
    js = "\n".join("/* === %s === */\n%s" % (n, t) for n, t in piezas_js)
    armazon = leer("armazon.html")

    # el payload va en un <script type="application/octet-stream"> para que el
    # navegador no intente ejecutarlo ni parsearlo como HTML
    html = u"""<!doctype html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Catastro de caminos de montaña — visor de tramos</title>
<meta name="generator" content="src/04_ensamblaje/visor_html.py">
<meta name="fondef-payload-sha256" content="{sha}">
<meta name="fondef-parquet-sha256" content="{shap}">
<meta name="fondef-generado" content="{gen}">
<style>
{css}
</style>
</head>
<body>
{armazon}
<script id="payload" type="application/octet-stream">{b64}</script>
<script>
{js}
</script>
</body>
</html>
""".format(sha=sha, shap=sha_parquet, gen=datetime.now().strftime("%Y-%m-%dT%H:%M:%S"),
           css=css, armazon=armazon, b64=b64, js=js)

    os.makedirs(os.path.dirname(salida), exist_ok=True)
    with io.open(salida, "w", encoding="utf-8", newline="\n") as f:
        f.write(html)

    mb = os.path.getsize(salida) / 1e6
    print("escrito %s  %.2f MB" % (salida, mb))
    print("  payload gzip %.2f MB -> base64 %.2f MB" % (len(crudo) / 1e6, len(b64) / 1e6))
    print("  sha256 payload %s" % sha[:16])
    print("  sha256 parquet %s" % sha_parquet[:16])
    if omitidas:
        print("  columnas 100%% NULL omitidas del visor: %s" % ", ".join(omitidas))


if __name__ == "__main__":
    main()
