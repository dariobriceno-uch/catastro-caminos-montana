# -*- coding: utf-8 -*-
"""
a7_nieve_drive.py — copia a data/raw/nieve/ los CSV que a7_nieve_ee.py exportó
a la carpeta FONDEF_nieve de Google Drive. Usa las mismas credenciales de
`earthengine authenticate` (incluyen el alcance de Drive). No modifica nada en
Drive ni en un archivo ya descargado: si el CSV local existe y su sha256 calza,
se salta.

Uso:  python src/01_descarga/a7_nieve_drive.py
"""
import hashlib
import io
import json
import os

RAIZ = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
DESTINO = os.path.join(RAIZ, "data", "raw", "nieve")
CARPETA = "FONDEF_nieve"


def credenciales():
    ruta = os.path.join(os.path.expanduser("~"), ".config", "earthengine", "credentials")
    d = json.load(open(ruta, encoding="utf-8"))
    from google.oauth2.credentials import Credentials
    import ee.oauth as eo   # el archivo guarda solo el refresh token; el cliente es el de la libreria
    return Credentials(None, refresh_token=d["refresh_token"], client_id=eo.CLIENT_ID,
                       client_secret=eo.CLIENT_SECRET, token_uri="https://oauth2.googleapis.com/token",
                       scopes=d.get("scopes"))


def main():
    from googleapiclient.discovery import build
    from googleapiclient.http import MediaIoBaseDownload
    drive = build("drive", "v3", credentials=credenciales(), cache_discovery=False)

    q = "name = '%s' and mimeType = 'application/vnd.google-apps.folder' and trashed = false" % CARPETA
    carpetas = drive.files().list(q=q, fields="files(id,name)").execute().get("files", [])
    if not carpetas:
        raise SystemExit("no existe la carpeta %s en Drive" % CARPETA)
    cid = carpetas[0]["id"]

    q = "'%s' in parents and name contains 'nieve_' and trashed = false" % cid
    archivos = drive.files().list(q=q, fields="files(id,name,size,modifiedTime)",
                                  orderBy="name").execute().get("files", [])
    os.makedirs(DESTINO, exist_ok=True)
    print("%d archivos en Drive/%s" % (len(archivos), CARPETA))
    for f in archivos:
        buf = io.BytesIO()
        dl = MediaIoBaseDownload(buf, drive.files().get_media(fileId=f["id"]))
        done = False
        while not done:
            _, done = dl.next_chunk()
        datos = buf.getvalue()
        sha = hashlib.sha256(datos).hexdigest()
        local = os.path.join(DESTINO, f["name"])
        if os.path.exists(local) and hashlib.sha256(open(local, "rb").read()).hexdigest() == sha:
            print("  = %-48s ya descargado" % f["name"])
            continue
        if os.path.exists(local):
            print("  ! %-48s existe con otro contenido; no se sobrescribe (Regla 3)" % f["name"])
            continue
        open(local, "wb").write(datos)
        print("  + %-48s %7.1f KB  %s  sha256 %s" % (f["name"], len(datos) / 1024, f["modifiedTime"][:19], sha[:12]))


if __name__ == "__main__":
    main()
