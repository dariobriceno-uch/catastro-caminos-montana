# =============================================================================
# A1 — Red Vial (FT-01). Descarga capa 3 de Red_Vial_Chile/MapServer, registra
# manifest, construye data/interim/a1_red_vial.gpkg (capa `tramos`),
# procedencia_a1.parquet y pendientes_a1.csv.
#
# Re-ejecutable desde la raíz:  Rscript src/01_descarga/a1_red_vial.R
# Los archivos ya presentes en data/raw/red_vial/ NO se vuelven a descargar ni
# se modifican (Regla 3). Para una descarga limpia, borrar la carpeta a mano.
#
# NOTA DE PAGINACIÓN. El servicio corre ArcGIS Server 10.21 y NO soporta
# resultOffset/resultRecordCount (los ignora y devuelve todo hasta
# MaxRecordCount=1000). Se pagina por REGION + rangos de OBJECTID obtenidos con
# returnIdsOnly=true, en bloques de 1000, que sí respeta el servidor.
# =============================================================================

suppressPackageStartupMessages({
  library(httr2); library(jsonlite); library(sf); library(dplyr); library(arrow)
})
options(warn = 1, stringsAsFactors = FALSE)
sf_use_s2(FALSE)

# ---- rutas -----------------------------------------------------------------
ROOT     <- normalizePath(".", winslash = "/")
RAW_DIR  <- file.path(ROOT, "data/raw/red_vial")
MAN_DIR  <- file.path(ROOT, "data/raw/manifest")
INT_DIR  <- file.path(ROOT, "data/interim")
LOG_DIR  <- file.path(ROOT, "logs")
for (d in c(RAW_DIR, MAN_DIR, INT_DIR, LOG_DIR)) dir.create(d, recursive = TRUE, showWarnings = FALSE)
MANIFEST <- file.path(MAN_DIR, "A1.json")
LOG      <- file.path(LOG_DIR, "a1_red_vial.log")

BASE  <- "https://rest-sit.mop.gob.cl/arcgis/rest/services/VIALIDAD/Red_Vial_Chile/MapServer/3"
QUERY <- paste0(BASE, "/query")
FUENTE <- "FT-01"; AGENTE <- "A1"; PAGE <- 1000L
FECHA_DESCARGA <- format(Sys.time(), "%Y-%m-%d", tz = "UTC")

log_line <- function(...) {
  msg <- paste0(format(Sys.time(), "%Y-%m-%d %H:%M:%S", tz = "UTC"), " UTC | ", paste0(..., collapse = ""))
  cat(msg, "\n"); con <- file(LOG, open = "ab"); writeBin(charToRaw(enc2utf8(paste0(msg, "\n"))), con); close(con)
}
cat("", file = LOG)  # reinicia log
log_line("Inicio A1 — ", BASE)

# ---- manifest ---------------------------------------------------------------
manifest <- if (file.exists(MANIFEST)) fromJSON(MANIFEST, simplifyVector = FALSE) else list()
manifest_has <- function(archivo) any(vapply(manifest, function(e) identical(e$archivo, archivo), logical(1)))
sha256_file <- function(path) digest::digest(path, algo = "sha256", file = TRUE)
add_manifest <- function(archivo_abs, url, n, notas = "") {
  rel <- sub(paste0("^", ROOT, "/"), "", archivo_abs)
  manifest[[length(manifest) + 1]] <<- list(
    fuente = FUENTE, archivo = rel, url = url,
    timestamp_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
    n_registros = n, sha256 = sha256_file(archivo_abs), agente = AGENTE, notas = notas)
}
write_utf8 <- function(txt, path) { con <- file(path, open = "wb"); on.exit(close(con)); writeBin(charToRaw(enc2utf8(txt)), con) }
save_manifest <- function() write_utf8(as.character(toJSON(manifest, auto_unbox = TRUE, pretty = TRUE, null = "null")), MANIFEST)
# Revierte (mismo run) los archivos parciales de una región cuya descarga falló a medias.
rollback_region <- function(slug) {
  fs <- list.files(RAW_DIR, pattern = paste0("^", slug, "_p[0-9]+[.]json$"), full.names = TRUE)
  if (length(fs)) { unlink(fs); log_line("  rollback: eliminadas ", length(fs), " páginas parciales de ", slug) }
  keep <- !vapply(manifest, function(e) grepl(paste0("red_vial/", slug, "_p[0-9]+[.]json$"), e$archivo), logical(1))
  manifest <<- manifest[keep]; save_manifest()
}

# ---- descarga con reintentos -----------------------------------------------
# Devuelve la URL exacta y el cuerpo. Reintenta con backoff exponencial.
fetch <- function(url, params) {
  req <- request(url) |> req_url_query(!!!params) |>
    req_timeout(300) |>
    req_retry(max_tries = 6, backoff = function(i) min(60, 2^i),
              is_transient = function(r) resp_status(r) >= 500 || resp_status(r) == 429)
  resp <- req_perform(req)
  body <- resp_body_raw(resp)
  # ArcGIS devuelve 200 con {"error":...} cuando falla la consulta
  j <- tryCatch(fromJSON(rawToChar(body), simplifyVector = FALSE), error = function(e) NULL)
  if (!is.null(j$error)) stop("Error ArcGIS: ", toJSON(j$error, auto_unbox = TRUE))
  list(url = req$url, body = body, json = j)
}
# Descarga a archivo solo si no existe; registra en manifest si es nuevo.
download_raw <- function(archivo, url, params, n_fun, notas = "") {
  path <- file.path(RAW_DIR, archivo)
  if (file.exists(path)) {
    j <- fromJSON(path, simplifyVector = FALSE)
    log_line("  [existe] ", archivo, " (", n_fun(j), " reg.)")
    return(j)
  }
  for (k in 1:3) {
    r <- tryCatch(fetch(url, params), error = function(e) e)
    if (!inherits(r, "error")) break
    log_line("  reintento ", k, " por: ", conditionMessage(r)); Sys.sleep(5 * k)
  }
  if (inherits(r, "error")) stop("Fallo definitivo en ", archivo, ": ", conditionMessage(r))
  writeBin(r$body, path)
  n <- n_fun(r$json)
  add_manifest(path, r$url, n, notas); save_manifest()
  log_line("  [descargado] ", archivo, " (", n, " reg.)")
  r$json
}
slugify <- function(x) {
  x <- iconv(x, "UTF-8", "ASCII//TRANSLIT"); x <- gsub("[^A-Za-z0-9]+", "_", x)
  tolower(gsub("^_|_$", "", x))
}
sql_str <- function(x) paste0("'", gsub("'", "''", x), "'")

# ---- 1. metadata de la capa --------------------------------------------------
meta <- download_raw("layer3_metadata.json", BASE, list(f = "pjson"),
                     n_fun = function(j) length(j$fields), notas = "Metadata capa 3: campos y dominios codificados")
log_line("Capa: ", meta$name, " | geometría ", meta$geometryType, " | hasZ=", meta$hasZ, " hasM=", meta$hasM,
         " | MaxRecordCount=", meta$maxRecordCount, " | wkid=", meta$extent$spatialReference$wkid,
         " | versión ArcGIS ", meta$currentVersion, " | supportsPagination=", ifelse(is.null(meta$supportsPagination), "ausente", meta$supportsPagination))
campos_capa <- vapply(meta$fields, function(f) f$name, character(1))
for (f in meta$fields) if (!is.null(f$domain$codedValues))
  log_line("  dominio ", f$name, ": ", paste(vapply(f$domain$codedValues, function(c) c$code, character(1)), collapse = " | "))

# ---- 2. conteo total y regiones -----------------------------------------------
total <- download_raw("count_total.json", QUERY, list(where = "1=1", returnCountOnly = "true", f = "json"),
                      n_fun = function(j) j$count, notas = "Conteo total con where=1=1")$count
log_line("Total declarado por el servicio: ", total)

reg_json <- download_raw("regiones_distinct.json", QUERY,
                         list(where = "1=1", outFields = "REGION", returnDistinctValues = "true",
                              returnGeometry = "false", f = "json"),
                         n_fun = function(j) length(j$features), notas = "Valores distintos de REGION")
regiones <- vapply(reg_json$features, function(f) if (is.null(f$attributes$REGION)) NA_character_ else f$attributes$REGION, character(1))
log_line("Regiones distintas: ", length(regiones))

# ---- 3. descarga paginada por región + rango OBJECTID (tamaño adaptativo) ----
# Una región se baja en páginas de PAGE registros. Si el servidor falla con una
# página (HTTP 500 al serializar geometrías muy densas, p. ej. Magallanes con
# tramos de >280.000 vértices), se revierten las páginas parciales de esa región
# y se reintenta con bloques 4 veces más pequeños, hasta 1 registro por página.
descargar_region <- function(reg, slug, where, ids, size) {
  chunks <- split(ids, ceiling(seq_along(ids) / size))
  n_desc <- 0L; files <- character(0)
  for (p in seq_along(chunks)) {
    ch <- chunks[[p]]
    w  <- paste0(where, " AND OBJECTID BETWEEN ", min(ch), " AND ", max(ch))
    archivo <- sprintf("%s_p%03d.json", slug, p)
    j <- download_raw(archivo, QUERY,
                      list(where = w, outFields = "*", returnGeometry = "true", returnZ = "true", returnM = "true",
                           outSR = "5360", f = "json"),
                      n_fun = function(j) length(j$features),
                      notas = paste0("Página ", p, " de ", length(chunks), ", región ", reg, "; OBJECTID ", min(ch), "-", max(ch),
                                     "; tamaño de bloque ", size,
                                     ". Paginación por rango de OBJECTID (ArcGIS 10.21 ignora resultOffset)."))
    if (isTRUE(j$exceededTransferLimit)) stop("exceededTransferLimit en ", archivo)
    if (length(j$features) != length(ch)) log_line("  ADVERTENCIA: página ", p, " trae ", length(j$features), " y se esperaban ", length(ch))
    n_desc <- n_desc + length(j$features)
    files <- c(files, file.path(RAW_DIR, archivo))
  }
  list(n = n_desc, files = files, paginas = length(chunks), size = size)
}

page_files <- character(0); conteo_reg <- list(); regiones_fallidas <- character(0)
for (reg in regiones) {
  where <- if (is.na(reg)) "REGION IS NULL" else paste0("REGION=", sql_str(reg))
  slug  <- if (is.na(reg)) "sin_region" else slugify(reg)
  log_line("Región: ", ifelse(is.na(reg), "<NULL>", reg), " -> ", slug)
  n_reg <- download_raw(paste0(slug, "_count.json"), QUERY, list(where = where, returnCountOnly = "true", f = "json"),
                        n_fun = function(j) j$count, notas = paste0("Conteo región ", reg))$count
  ids <- download_raw(paste0(slug, "_ids.json"), QUERY, list(where = where, returnIdsOnly = "true", f = "json"),
                      n_fun = function(j) length(j$objectIds), notas = paste0("OBJECTIDs región ", reg))$objectIds
  ids <- sort(unlist(ids))
  if (length(ids) != n_reg) log_line("  ADVERTENCIA: ids=", length(ids), " vs count=", n_reg)
  # Si ya hay páginas de esta región de una corrida anterior, se respeta su tamaño de bloque (se leen tal cual).
  size <- PAGE; res <- NULL
  existentes <- list.files(RAW_DIR, pattern = paste0("^", slug, "_p[0-9]+[.]json$"), full.names = TRUE)
  if (length(existentes)) {
    n_ex <- sum(vapply(existentes, function(f) length(fromJSON(f, simplifyVector = FALSE)$features), integer(1)))
    if (n_ex == n_reg) {
      res <- list(n = n_ex, files = sort(existentes), paginas = length(existentes), size = NA)
      log_line("  [existe] región completa en ", length(existentes), " página(s) previas (", n_ex, " reg.)")
    } else {
      log_line("  páginas previas incompletas (", n_ex, " de ", n_reg, "): se revierten y se descarga de nuevo")
      rollback_region(slug)
    }
  }
  if (is.null(res)) repeat {
    res <- tryCatch(descargar_region(reg, slug, where, ids, size), error = function(e) e)
    if (!inherits(res, "error")) break
    log_line("  FALLO con bloque ", size, ": ", conditionMessage(res))
    rollback_region(slug)
    if (size <= 1) { res <- NULL; break }
    size <- max(1L, as.integer(size %/% 4)); log_line("  reintentando región con bloque ", size)
  }
  if (is.null(res)) { regiones_fallidas <- c(regiones_fallidas, reg); log_line("  REGIÓN NO DESCARGADA: ", reg); next }
  conteo_reg[[slug]] <- c(esperado = n_reg, descargado = res$n)
  page_files <- c(page_files, res$files)
  log_line("  región ", slug, ": esperado ", n_reg, ", descargado ", res$n, " en ", res$paginas, " página(s) de ", res$size)
}
suma <- sum(vapply(conteo_reg, function(x) x[["descargado"]], numeric(1)))
log_line("Suma por región = ", suma, " | total servicio = ", total,
         if (suma == total) " | OK" else paste0(" | DIFERENCIA ", total - suma))
if (length(regiones_fallidas)) log_line("REGIONES FALTANTES (no se completan): ", paste(regiones_fallidas, collapse = "; "))

# ---- 4. lectura Esri JSON -> sf (parser propio) -------------------------------------
# No se usa el driver ESRIJSON de GDAL: en archivos que contienen alguna feature
# multiparte (Arica, Atacama) lee toda la página como MULTILINESTRING XY y
# descarta el Z que el JSON sí trae. Acá se construye la geometría directamente
# desde `paths`: columnas 1-3 = X, Y, Z (la 4ª, M = kilometraje, se descarta).
leer_pagina <- function(f) {
  j <- fromJSON(f, simplifyVector = FALSE)
  attrs <- bind_rows(lapply(j$features, function(x) as_tibble(lapply(x$attributes, function(v) if (is.null(v)) NA else v))))
  stats <- list(n_multi = 0L, n_vacias = 0L, n_sin_z = 0L, z = list(), m_rng = c(Inf, -Inf))
  geoms <- lapply(j$features, function(x) {
    paths <- x$geometry$paths
    if (is.null(paths) || length(paths) == 0) { stats$n_vacias <<- stats$n_vacias + 1L; return(st_multilinestring(dim = "XYZ")) }
    if (length(paths) > 1) stats$n_multi <<- stats$n_multi + 1L
    # Algunos vértices traen null en M (55 features): unlist los descartaría y desalinearía X/Y/Z.
    mats <- lapply(paths, function(pt) {
      nc <- length(pt[[1]]); v <- unlist(pt)
      if (length(v) != nc * length(pt))
        v <- unlist(lapply(pt, function(vv) vapply(vv, function(a) if (is.null(a)) NA_real_ else as.numeric(a), numeric(1))))
      matrix(v, ncol = nc, byrow = TRUE)
    })
    nc <- ncol(mats[[1]])
    if (nc >= 4) { m <- unlist(lapply(mats, function(mm) mm[, 4])); stats$m_rng <<- range(c(stats$m_rng, m), na.rm = TRUE) }
    if (nc >= 3) {
      stats$z[[length(stats$z) + 1]] <<- unlist(lapply(mats, function(mm) mm[, 3]))
      st_multilinestring(lapply(mats, function(mm) mm[, 1:3, drop = FALSE]), dim = "XYZ")
    } else { stats$n_sin_z <<- stats$n_sin_z + 1L; st_multilinestring(lapply(mats, function(mm) mm[, 1:2, drop = FALSE]), dim = "XY") }
  })
  list(sf = st_sf(attrs, geometry = st_sfc(geoms, crs = 5360)), stats = stats)
}
log_line("Leyendo ", length(page_files), " páginas (parser propio de Esri JSON)")
lect <- lapply(page_files, leer_pagina)
raw_sf <- do.call(rbind, lapply(lect, `[[`, "sf"))
n_multi_orig <- sum(vapply(lect, function(l) l$stats$n_multi, integer(1)))
n_vacias     <- sum(vapply(lect, function(l) l$stats$n_vacias, integer(1)))
n_sin_z      <- sum(vapply(lect, function(l) l$stats$n_sin_z, integer(1)))
z_list       <- unlist(lapply(lect, function(l) l$stats$z), recursive = FALSE)
m_rng        <- range(unlist(lapply(lect, function(l) l$stats$m_rng)))
rm(lect); invisible(gc())
log_line("Filas leídas: ", nrow(raw_sf), " | CRS EPSG:", st_crs(raw_sf)$epsg, " | multiparte originales: ", n_multi_orig,
         " | geometrías vacías: ", n_vacias, " | features sin Z: ", n_sin_z)
esperados <- c(ROL = "rol", ROL_ID = "rol_id", CODIGO_CAMINO = "codigo_camino", NOMBRE_CAMINO = "nombre_camino",
               CLASIFICACION = "clasificacion", CARPETA = "carpeta", CALZADA = "calzada", ORIENTACION = "orientacion_ruta",
               KM_I = "km_inicio", KM_F = "km_fin", KM_TRAMO = "km_tramo", ENROLADO = "enrolado",
               CONCESIONADO = "concesionado", TUICION = "tuicion", REGION = "region")
faltan <- setdiff(names(esperados), names(raw_sf))
log_line("Campos del esquema ausentes en la capa: ", if (length(faltan)) paste(faltan, collapse = ", ") else "ninguno")
log_line("Campos de la capa no usados por A1: ", paste(setdiff(names(raw_sf), c(names(esperados), "OBJECTID", "geometry")), collapse = ", "))

# ---- estadísticas de Z (en EPSG:5360, antes de reproyectar) ------------------------
z <- unlist(z_list)
if (length(z)) {
  log_line(sprintf("Z: vértices con Z=%d | min=%.2f | max=%.2f | mediana=%.2f | %% ceros=%.2f%% | NA=%d",
                   length(z), min(z, na.rm = TRUE), max(z, na.rm = TRUE), median(z, na.rm = TRUE),
                   100 * mean(z == 0, na.rm = TRUE), sum(is.na(z))))
  z_fila_cero <- vapply(z_list, function(v) all(v == 0, na.rm = TRUE), logical(1))
  zmax_fila   <- vapply(z_list, function(v) max(v, na.rm = TRUE), numeric(1))
  log_line("Filas con Z íntegramente 0: ", sum(z_fila_cero), " de ", length(z_list), " con Z")
  log_line(sprintf("Z máx por fila: min=%.1f | mediana=%.1f | max=%.1f | filas con Zmax>1000: %d | >2000: %d | >3000: %d",
                   min(zmax_fila), median(zmax_fila), max(zmax_fila), sum(zmax_fila > 1000), sum(zmax_fila > 2000), sum(zmax_fila > 3000)))
} else log_line("Z: la geometría NO trae Z")
if (is.finite(m_rng[1])) log_line(sprintf("M: min=%.2f max=%.2f (descartado; no es columna del esquema)", m_rng[1], m_rng[2]))
rm(z, z_list)

# ---- 5. exclusiones (vacías, Isla de Pascua), reproyección -----------------------------
vacia <- st_is_empty(raw_sf)
xmin <- rep(NA_real_, nrow(raw_sf)); xmin[!vacia] <- vapply(st_geometry(raw_sf)[!vacia], function(g) st_bbox(g)[["xmin"]], numeric(1))
excl_pascua <- !vacia & xmin < -100
log_line("Excluidas por geometría vacía: ", sum(vacia), " | por Isla de Pascua (lon < -100°): ", sum(excl_pascua))
excl_idx <- vacia | excl_pascua
excl_motivo <- ifelse(vacia, "Geometría vacía en FT-01 capa 3 (sin vértices); no puede entrar a una tabla de tramos con geometría",
                      "Isla de Pascua: geometría con longitud < -100 grados (docs/fuentes.md FT-01)")
tr <- raw_sf[!excl_idx, ]
log_line("Multilíneas (multiparte) conservadas en la tabla: ", sum(vapply(st_geometry(tr), function(g) length(g) > 1, logical(1))),
         " | todas las geometrías almacenadas como MULTILINESTRING Z")
pipe <- sf_proj_pipelines("EPSG:5360", "EPSG:4326")
log_line("Reproyección 5360->4326. Pipeline elegido por PROJ: ", pipe$definition[1], " | descripción: ", pipe$description[1],
         " | accuracy: ", pipe$accuracy[1])
tr <- st_transform(tr, 4326)
log_line("CRS final EPSG:", st_crs(tr)$epsg, " | Z conservado: ", "Z" %in% colnames(st_coordinates(tr[1, ])))

# ---- 6. columnas del bloque A1 ----------------------------------------------------
as_chr <- function(x) { x <- as.character(x); x[!is.na(x) & x == ""] <- NA; x }
tab <- st_drop_geometry(tr)
out <- tibble(
  objectid_mop     = as.integer(tab$OBJECTID),
  rol              = as_chr(tab$ROL),
  rol_id           = as_chr(tab$ROL_ID),
  codigo_camino    = as_chr(tab$CODIGO_CAMINO),
  nombre_camino    = as_chr(tab$NOMBRE_CAMINO),
  clasificacion    = as_chr(tab$CLASIFICACION),
  carpeta          = as_chr(tab$CARPETA),
  calzada          = as_chr(tab$CALZADA),
  orientacion_ruta = as_chr(tab$ORIENTACION),
  km_inicio        = as.integer(tab$KM_I),
  km_fin           = as.integer(tab$KM_F),
  km_tramo         = as.integer(tab$KM_TRAMO),
  enrolado         = as_chr(tab$ENROLADO),
  concesionado     = as_chr(tab$CONCESIONADO),
  tuicion          = as_chr(tab$TUICION),
  region           = as_chr(tab$REGION)
)
# id_tramo_a1: <rol>-<n> correlativo dentro del rol por km_inicio (desempate por objectid)
out <- out |>
  arrange(rol, km_inicio, objectid_mop) |>
  group_by(rol) |>
  mutate(n_rol = row_number()) |>
  ungroup() |>
  mutate(id_tramo_a1 = ifelse(is.na(rol), paste0("SINROL-", objectid_mop), paste0(rol, "-", n_rol))) |>
  select(-n_rol)
stopifnot(!any(duplicated(out$id_tramo_a1)))
geom <- st_geometry(tr)[match(out$objectid_mop, tab$OBJECTID)]
tramos <- st_sf(out, geometria = geom, crs = 4326) |>
  select(id_tramo_a1, objectid_mop, rol, rol_id, codigo_camino, nombre_camino, clasificacion, carpeta, calzada,
         orientacion_ruta, km_inicio, km_fin, km_tramo, enrolado, concesionado, tuicion, region, geometria)

GPKG <- file.path(INT_DIR, "a1_red_vial.gpkg")
if (file.exists(GPKG)) unlink(GPKG)
st_write(tramos, GPKG, layer = "tramos", quiet = TRUE, dim = "XYZ")
log_line("Escrito ", GPKG, " capa tramos: ", nrow(tramos), " filas")

# ---- 7. procedencia y pendientes ---------------------------------------------------
campos_a1 <- unname(esperados)
attr_df <- st_drop_geometry(tramos)
proc <- bind_rows(
  lapply(campos_a1, function(cn) tibble(id_tramo = attr_df$id_tramo_a1[!is.na(attr_df[[cn]])], campo = cn, metodo = "declarado")),
  tibble(id_tramo = attr_df$id_tramo_a1[!st_is_empty(tramos)], campo = "geometria", metodo = "derivado")
) |> mutate(fuente = FUENTE, fecha_descarga = FECHA_DESCARGA, agente = AGENTE) |>
  select(id_tramo, campo, fuente, fecha_descarga, metodo, agente)
write_parquet(proc, file.path(INT_DIR, "procedencia_a1.parquet"))
log_line("Procedencia: ", nrow(proc), " filas")

pend <- bind_rows(
  lapply(campos_a1, function(cn) {
    idx <- is.na(attr_df[[cn]])
    tibble(id_tramo = attr_df$id_tramo_a1[idx], campo = cn,
           motivo = paste0("Atributo ", names(esperados)[esperados == cn], " nulo o vacío en FT-01 capa 3"))
  }),
  tibble(id_tramo = attr_df$id_tramo_a1[is.na(attr_df$rol)], campo = "id_tramo_a1",
         motivo = "ROL nulo en la capa: id provisional SINROL-<objectid>, requiere revisión humana"),
  tibble(id_tramo = "*", campo = "A1", motivo = if (length(regiones_fallidas))
           paste0("Región no descargada por fallo persistente del servicio: ", paste(regiones_fallidas, collapse = "; ")) else character(0))
) |> mutate(agente = AGENTE, fecha = FECHA_DESCARGA) |>
  select(id_tramo, campo, motivo, agente, fecha)
write.csv(pend, file.path(INT_DIR, "pendientes_a1.csv"), row.names = FALSE, fileEncoding = "UTF-8")
log_line("Pendientes: ", nrow(pend), " filas")

# Excluidos: una fila por registro crudo que no entra a la tabla
excl <- tibble(objectid_mop = as.integer(raw_sf$OBJECTID[excl_idx]),
               rol = as_chr(raw_sf$ROL[excl_idx]), region = as_chr(raw_sf$REGION[excl_idx]),
               motivo = excl_motivo[excl_idx])
write.csv(excl, file.path(INT_DIR, "a1_excluidos.csv"), row.names = FALSE, fileEncoding = "UTF-8")
log_line("Excluidos: ", nrow(excl), " filas en a1_excluidos.csv")

# ---- 8. resumen para el reporte -------------------------------------------------------
log_line("---- RESUMEN ----")
log_line("Filas por región:"); print(sort(table(attr_df$region, useNA = "ifany"), decreasing = TRUE))
log_line("NULL por columna:"); print(colSums(is.na(attr_df)))
for (cn in c("clasificacion", "carpeta", "calzada", "orientacion_ruta", "enrolado", "concesionado", "tuicion", "region")) {
  log_line("Valores distintos de ", cn, ":"); print(table(attr_df[[cn]], useNA = "ifany"))
}
log_line("km_inicio rango: ", min(attr_df$km_inicio, na.rm = TRUE), "-", max(attr_df$km_inicio, na.rm = TRUE),
         " | km_tramo rango: ", min(attr_df$km_tramo, na.rm = TRUE), "-", max(attr_df$km_tramo, na.rm = TRUE))
log_line("Roles distintos: ", n_distinct(attr_df$rol), " | SINROL: ", sum(is.na(attr_df$rol)))
log_line("Fin A1")
