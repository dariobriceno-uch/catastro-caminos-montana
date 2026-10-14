# -*- coding: utf-8 -*-
"""
visor_check.py — abre docs/visor_tramos.html en un navegador headless y verifica
que arranca sin errores. Uso:
    python src/04_ensamblaje/visor_check.py [--shot salida.png] [--js "expresion"]
Devuelve exit 1 si hay errores de consola, excepciones o si #app no se muestra.
"""
import argparse
import json
import os
import sys

RAIZ = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HTML = os.path.join(RAIZ, "docs", "visor_tramos.html")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--shot")
    ap.add_argument("--html", default=HTML)
    ap.add_argument("--solo-arranque", action="store_true", dest="solo_arranque",
                    help="no exigir tabla ni mapa dibujados (para modulos a medio hacer)")
    ap.add_argument("--js", action="append", default=[])
    ap.add_argument("--ancho", type=int, default=1600)
    ap.add_argument("--alto", type=int, default=1000)
    ap.add_argument("--espera", type=int, default=45000)
    a = ap.parse_args()

    from playwright.sync_api import sync_playwright

    errores, logs = [], []
    with sync_playwright() as p:
        b = p.chromium.launch()
        pg = b.new_page(viewport={"width": a.ancho, "height": a.alto})
        pg.on("console", lambda m: (errores if m.type == "error" else logs).append(m.text))
        pg.on("pageerror", lambda e: errores.append("pageerror: %s" % e))
        pg.goto("file:///" + os.path.abspath(a.html).replace("\\", "/"))
        try:
            pg.wait_for_selector("#app:not([hidden])", timeout=a.espera)
            arranco = True
        except Exception as e:
            arranco = False
            err_txt = pg.eval_on_selector("#carga-err", "e => e.textContent") if pg.query_selector("#carga-err") else ""
            errores.append("no arranco: %s %s" % (e, err_txt))

        if arranco:
            pg.wait_for_timeout(2500)
            # Arrancar no basta: una pagina de stubs tambien muestra #app.
            if not a.solo_arranque:
                try:
                    nodos = pg.evaluate("document.querySelectorAll('#panel-tabla *').length")
                    if not nodos or nodos < 50:
                        errores.append("la tabla esta vacia: %s nodos en #panel-tabla" % nodos)
                except Exception as e:
                    errores.append("no se pudo medir la tabla: %s" % e)
                try:
                    pintados = pg.evaluate("""() => {
                      const c = document.querySelector('#panel-mapa canvas');
                      if (!c || !c.width) return -1;
                      const g = c.getContext('2d');
                      const d = g.getImageData(0, 0, c.width, c.height).data;
                      let n = 0;
                      for (let i = 3; i < d.length; i += 4) if (d[i] > 8) n++;
                      return n;
                    }""")
                    if pintados is None or pintados < 500:
                        errores.append("el lienzo del mapa tiene %s pixeles pintados "
                                       "(se esperan miles)" % pintados)
                    else:
                        print("mapa: %d pixeles pintados" % pintados)
                except Exception as e:
                    errores.append("no se pudo medir el mapa: %s" % e)
            for expr in a.js:
                try:
                    print("JS %s => %s" % (expr, json.dumps(pg.evaluate(expr), ensure_ascii=False, default=str)[:2000]))
                except Exception as e:
                    errores.append("js '%s': %s" % (expr, e))
            if a.shot:
                pg.screenshot(path=a.shot, full_page=False)
                print("captura: %s" % a.shot)
        b.close()

    for e in errores:
        print("ERROR %s" % e)
    print("consola: %d mensajes, %d errores" % (len(logs), len(errores)))
    return 1 if errores or not arranco else 0


if __name__ == "__main__":
    sys.exit(main())
