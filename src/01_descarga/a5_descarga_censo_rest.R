# A5 — Descarga del servicio REST de respaldo de FT-02 (Plan Nacional de Censos).
# Ejecutar desde la raíz:  Rscript src/01_descarga/a5_descarga_censo_rest.R
#
# Guarda en data/raw/censo_rest/: service.pjson, layer_<i>_meta.pjson y
# layer_<i>_p<k>.json (Esri JSON, outSR=4326, paginación de 1000).
# data/raw/ es de solo lectura una vez descargado: si la carpeta ya tiene
# archivos, el script no sobrescribe nada y se detiene (Regla 3).
# La descarga original se hizo el 2026-08-26 con curl con estos mismos
# parámetros; el manifest lo genera src/01_descarga/a5_manifest_censo.py.

suppressPackageStartupMessages({ library(httr2); library(jsonlite) })
if (!file.exists("REGLAS.md")) stop("Ejecutar desde la raíz del repositorio")
base <- "https://rest-sit.mop.gob.cl/arcgis/rest/services/VIALIDAD/Plan_Nacional_de_Censos/MapServer"
dir_out <- "data/raw/censo_rest"
if (dir.exists(dir_out) && length(list.files(dir_out, pattern = "\\.p?json$"))) {
  stop("data/raw/censo_rest ya contiene descargas; no se sobrescribe (Regla 3). ",
       "Para volver a descargar, usar otra carpeta y registrar en el manifest.")
}
dir.create(dir_out, showWarnings = FALSE, recursive = TRUE)

get_txt <- function(url) request(url) %>% req_user_agent("catastro-fondef-A5") %>%
  req_perform() %>% resp_body_string()
writeLines(get_txt(paste0(base, "?f=pjson")), file.path(dir_out, "service.pjson"), useBytes = TRUE)
svc <- fromJSON(file.path(dir_out, "service.pjson"))
cat("capas:", nrow(svc$layers), "\n")
for (i in svc$layers$id) {
  writeLines(get_txt(paste0(base, "/", i, "?f=pjson")), file.path(dir_out, sprintf("layer_%d_meta.pjson", i)), useBytes = TRUE)
  off <- 0; p <- 0
  repeat {
    url <- sprintf("%s/%d/query?where=1%%3D1&outFields=*&outSR=4326&f=json&resultOffset=%d&resultRecordCount=1000", base, i, off)
    txt <- get_txt(url)
    fp <- file.path(dir_out, sprintf("layer_%d_p%d.json", i, p))
    writeLines(txt, fp, useBytes = TRUE)
    j <- fromJSON(txt, simplifyVector = FALSE)
    n <- length(j$features)
    cat("capa", i, "pag", p, "->", n, "\n")
    if (!isTRUE(j$exceededTransferLimit) || n == 0) break
    off <- off + 1000; p <- p + 1
  }
}
# ficha oficial (leyenda de muestras y URLs de planillas)
writeLines(get_txt("https://vialidad.mop.gob.cl/plan-nacional-de-censo-vial/"),
           file.path(dir_out, "ficha_plan_nacional_censo_vial.html"), useBytes = TRUE)
cat("timestamp_utc:", format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"), "\n")
