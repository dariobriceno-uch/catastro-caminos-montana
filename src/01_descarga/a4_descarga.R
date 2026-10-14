# A4 — Descarga de insumos FT-05 (INE) y FT-06 (SERNATUR) + registro FT-03 (DIFROL, manual)
# Re-ejecutable desde la raíz: Rscript src/01_descarga/a4_descarga.R
# Regla 3: no sobreescribe archivos ya presentes en data/raw/.
suppressPackageStartupMessages({library(sf); library(jsonlite); library(httr2)})
options(timeout = 600)
ts_now <- function() format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
sha    <- function(f) digest::digest(f, algo = "sha256", file = TRUE)
dir.create("data/raw/ine", showWarnings = FALSE, recursive = TRUE)
dir.create("data/raw/sernatur", showWarnings = FALSE, recursive = TRUE)
dir.create("data/raw/manifest", showWarnings = FALSE, recursive = TRUE)
man <- list()
add <- function(fuente, archivo, url, ts, n, notas = "") {
  man[[length(man) + 1]] <<- list(fuente = fuente, archivo = archivo, url = url, timestamp_utc = ts,
                                  n_registros = n, sha256 = sha(archivo), agente = "A4", notas = notas)
}
dl <- function(url, dest) {
  if (file.exists(dest)) { message("ya existe, no se toca: ", dest); return(NA_character_) }
  ts <- ts_now()
  req_perform(req_timeout(request(url), 600), path = dest)
  ts
}
n_shp_zip <- function(zip) {
  td <- tempfile(); dir.create(td); unzip(zip, exdir = td)
  shp <- list.files(td, "[.]shp$", full.names = TRUE, recursive = TRUE)[1]
  nrow(st_read(shp, quiet = TRUE))
}

## ---- FT-03 DIFROL (descarga manual 2026-08-26) ----
difrol <- list(
  c("FT-03a", "data/raw/Pasos Fronterizos/Pasos fronterizos Descarga/pasos_fronterizos_19-02.shp", "capa de puntos; EPSG:5360"),
  c("FT-03b", "data/raw/Límite internacional/V4_limite_Internacional_Recuadro_CHS/V4_limite_internacional_50k.shp", "V4.0 límite internacional 1:50.000; EPSG:5360"),
  c("FT-03c", "data/raw/Zona fronteriza/ZF_limite_2024/zf_2024.shp", "zona fronteriza 2024; EPSG:4326"))
for (d in difrol) add(d[1], d[2], "https://www.difrol.cl/mapas/", "2026-08-26 (manual)",
                      nrow(st_read(d[2], quiet = TRUE)), paste0(d[3], "; sha256 del .shp; .dbf sha256=", sha(sub("[.]shp$", ".dbf", d[2]))))

## ---- FT-05 INE: entidades censo 2017 (shapefiles nacionales) ----
base <- "https://www.ine.gob.cl/docs/default-source/geodatos-abiertos/cartografia/censo-2017/ciudades-pueblos-aldeas-y-caser%C3%ADos/shp/"
for (n in c("ciudades", "pueblos", "aldeas", "caserios", "conurbaciones")) {
  url <- paste0(base, n, "_2017.zip"); dest <- paste0("data/raw/ine/", n, "_2017.zip")
  ts <- dl(url, dest); if (is.na(ts)) ts <- "2026-08-26T18:06Z (descarga inicial con curl, mismo URL)"
  add("FT-05", dest, url, ts, n_shp_zip(dest), "INE Geodatos Abiertos, entidades Censo 2017, polígonos EPSG:3857")
}

## ---- FT-05 INE: límites comunales y provinciales (REST INE, servicios Comunas_2017 / Provincias_2017) ----
rest <- "https://services5.arcgis.com/hUyD8u3TeZLKPe4T/arcgis/rest/services/"
dl_rest <- function(svc, dest) {
  if (file.exists(dest)) { message("ya existe: ", dest); return(NA_character_) }
  ts <- ts_now(); feats <- list(); off <- 0
  repeat {
    u <- paste0(rest, svc, "/FeatureServer/0/query?where=1%3D1&outFields=*&outSR=4326&f=geojson&resultOffset=", off, "&resultRecordCount=1000")
    j <- resp_body_string(req_perform(req_timeout(request(u), 600)))
    g <- fromJSON(j, simplifyVector = FALSE)
    feats <- c(feats, g$features)
    if (is.null(g$properties$exceededTransferLimit) || !isTRUE(g$properties$exceededTransferLimit)) break
    off <- off + 1000
  }
  writeLines(toJSON(list(type = "FeatureCollection", features = feats), auto_unbox = TRUE, digits = NA, null = "null"), dest, useBytes = TRUE)
  ts
}
for (s in c("Comunas_2017", "Provincias_2017")) {
  dest <- paste0("data/raw/ine/", tolower(s), ".geojson")
  ts <- dl_rest(s, dest); if (is.na(ts)) ts <- "ya presente"
  add("FT-05", dest, paste0(rest, s, "/FeatureServer/0/query?where=1%3D1&outFields=*&outSR=4326&f=geojson (paginado 1000)"),
      ts, nrow(st_read(dest, quiet = TRUE)), "INE (owner publicaciones_geodatos), límites DPA Censo 2017, GeoJSON EPSG:4326")
}

## ---- FT-06 SERNATUR: atractivos turísticos (Líneas de Base Públicas, MMA) ----
u6 <- "https://lineasdebasepublicas.mma.gob.cl/datos_abiertos/dataset/7aa4b072-c938-4c45-a31e-9d57c41c2713/resource/e1e6163d-90a5-470c-b5de-8df8b284a5ef/download/atractivos-turisticos.gpkg"
d6 <- "data/raw/sernatur/atractivos-turisticos.gpkg"
ts <- dl(u6, d6); if (is.na(ts)) ts <- "ya presente"
add("FT-06", d6, u6, ts, nrow(st_read(d6, quiet = TRUE)),
    "SERNATUR vía MMA Líneas de Base Públicas, CC0, EPSG:4326. Sin campo de cota base. Centros de esquí identificables por subtipo_at='Area Nevada' y/o nombre")

write_json(man, "data/raw/manifest/A4.json", pretty = TRUE, auto_unbox = TRUE)
message("manifest A4: ", length(man), " entradas")
