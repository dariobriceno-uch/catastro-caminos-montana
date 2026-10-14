# tests/helpers.R — utilidades compartidas por todas las etapas de validación.
# No escribe datos. Solo lee data/raw, data/interim, data/processed y docs.

suppressPackageStartupMessages({
  library(testthat)
  library(jsonlite)
})

RAIZ <- normalizePath(Sys.getenv("FONDEF_RAIZ", unset = getwd()), winslash = "/")
rp <- function(...) file.path(RAIZ, ...)

# ---------------------------------------------------------------------------
# Esquema (docs/esquema.md) transcrito como contrato de columnas por bloque.
# ---------------------------------------------------------------------------
COLS_ORQ <- c("id_tramo", "en_lista_colega")
COLS_A1  <- c("rol", "rol_id", "codigo_camino", "nombre_camino", "clasificacion",
              "carpeta", "calzada", "orientacion_ruta", "km_inicio", "km_fin",
              "km_tramo", "enrolado", "concesionado", "tuicion", "region",
              "geometria")
COLS_A1_LLAVES <- c("objectid_mop", "id_tramo_a1")
COLS_A2  <- c("longitud_calc_m", "delta_longitud_pct", "coord_inicio", "coord_fin",
              "subdividido", "motivo_corte", "utm_zona")
COLS_A3  <- c("cota_min", "cota_max", "cota_media", "cota_culminante",
              "pendiente_media", "pendiente_max", "orientacion_ladera",
              "sinuosidad", "desnivel_subida_m", "desnivel_bajada_m",
              "cruza_portezuelo", "clase_kapos", "cota_max_z_mop", "delta_z_m")
COLS_A4  <- c("provincia", "comuna", "es_paso", "paso_nombre", "paso_pais",
              "paso_trafico", "paso_habilitacion", "dist_limite_m",
              "en_zona_fronteriza", "es_esqui", "esqui_nombre", "esqui_cota_base",
              "es_localidad", "localidad_nombre", "dist_servicios_km",
              "buffer_join_m")
COLS_A5  <- c("tmda", "tmda_invierno", "tmda_composicion", "punto_censal_id",
              "dist_punto_censal_m", "tmda_anio", "match_metodo")
COLS_A6  <- c("unidad_geomorf", "n_unidades_geomorf", "vertiente")
COLS_A7  <- c("dias_nieve_mediana", "dias_nieve_media", "dias_nieve_sd", "meses_nieve",
              "n_anios_validos", "dias_validos_mediana", "serie_inicio", "serie_fin")
DOM_VERTIENTE <- c("andina", "costera", "transversal", "otra")

# Correspondencia campo A1 -> campo crudo de FT-01 capa 3
MAPA_A1_CRUDO <- c(rol = "ROL", rol_id = "ROL_ID", codigo_camino = "CODIGO_CAMINO",
                   nombre_camino = "NOMBRE_CAMINO", clasificacion = "CLASIFICACION",
                   carpeta = "CARPETA", calzada = "CALZADA",
                   orientacion_ruta = "ORIENTACION", km_inicio = "KM_I",
                   km_fin = "KM_F", km_tramo = "KM_TRAMO", enrolado = "ENROLADO",
                   concesionado = "CONCESIONADO", tuicion = "TUICION",
                   region = "REGION")

DOM_METODO       <- c("derivado", "declarado", "estimado")
DOM_MOTIVO_CORTE <- c("original", "cambio_comuna", "cambio_carpeta", "punto_control")
DOM_UTM          <- c(18L, 19L)
DOM_RUMBOS       <- c("N", "NE", "E", "SE", "S", "SO", "O", "NO")
DOM_MATCH        <- c("espacial", "rol_kilometraje")
COLS_PROCEDENCIA <- c("id_tramo", "campo", "fuente", "fecha_descarga", "metodo", "agente")
COLS_VACIOS  <- c("id_tramo", "campo", "motivo", "agente", "fecha")
N_PASOS_HABILITADOS_REF <- 64L   # docs/fuentes.md FT-03a, control de completitud

# ---------------------------------------------------------------------------
# Insumos por etapa: el primero es el archivo principal; si no existe la
# etapa se salta completa.
# ---------------------------------------------------------------------------
INSUMOS <- list(
  a1 = c(rp("data/interim/a1_red_vial.gpkg"),
         rp("data/interim/procedencia_a1.parquet"),
         rp("data/raw/manifest/A1.json")),
  a2 = c(rp("data/interim/a2_tramos.gpkg"),
         rp("data/interim/procedencia_a2.parquet"),
         rp("data/interim/a1_red_vial.gpkg")),
  a3 = c(rp("data/interim/a3_altimetria.parquet"),
         rp("data/interim/procedencia_a3.parquet"),
         rp("data/interim/a2_tramos.gpkg")),
  a4 = c(rp("data/interim/a4_destinos.parquet"),
         rp("data/interim/procedencia_a4.parquet"),
         rp("data/interim/a2_tramos.gpkg")),
  a5 = c(rp("data/interim/a5_transito.parquet"),
         rp("data/interim/procedencia_a5.parquet"),
         rp("data/interim/a2_tramos.gpkg")),
  a6 = c(rp("data/interim/a6_geomorf.parquet"),
         rp("data/interim/procedencia_a6.parquet"),
         rp("data/interim/a2_tramos.gpkg")),
  a7 = c(rp("data/interim/a7_nieve.parquet"),
         rp("data/interim/procedencia_a7.parquet"),
         rp("data/processed/tramos.parquet")),
  final = c(rp("data/processed/tramos.parquet"),
            rp("data/processed/procedencia.parquet"),
            rp("data/vacios.csv")),
  visor = c(rp("data/processed/tramos.parquet"),
            rp("data/processed/procedencia.parquet"),
            rp("data/interim/visor_payload.json"),
            rp("docs/visor_tramos.html"))
)

# ---------------------------------------------------------------------------
# Lectura
# ---------------------------------------------------------------------------
leer_gpkg <- function(path, capa = "tramos") {
  suppressPackageStartupMessages(library(sf))
  capas <- sf::st_layers(path)$name
  if (!capa %in% capas) capa <- capas[1]
  sf::st_read(path, layer = capa, quiet = TRUE)
}

leer_parquet <- function(path) {
  suppressPackageStartupMessages(library(arrow))
  as.data.frame(arrow::read_parquet(path))
}

leer_csv <- function(path) {
  if (!file.exists(path)) return(NULL)
  d <- tryCatch(read.csv(path, stringsAsFactors = FALSE, encoding = "UTF-8",
                         colClasses = "character", na.strings = c("", "NA")),
                error = function(e) NULL)
  if (is.null(d)) return(NULL)
  d
}

leer_manifest <- function(path) {
  if (!file.exists(path)) return(NULL)
  m <- jsonlite::fromJSON(path, simplifyVector = TRUE)
  if (is.list(m) && !is.data.frame(m) && !is.null(m$entradas)) m <- m$entradas
  if (!is.data.frame(m)) m <- as.data.frame(m, stringsAsFactors = FALSE)
  m
}

leer_manifests_todos <- function() {
  fs <- list.files(rp("data/raw/manifest"), pattern = "[.]json$", full.names = TRUE)
  fs <- c(fs, Filter(file.exists, rp("data/raw/manifest.json")))
  ms <- lapply(fs, leer_manifest)
  ms <- Filter(function(x) !is.null(x) && nrow(x) > 0, ms)
  if (length(ms) == 0) return(NULL)
  cols <- Reduce(union, lapply(ms, names))
  ms <- lapply(ms, function(m) { for (cc in setdiff(cols, names(m))) m[[cc]] <- NA; m[cols] })
  do.call(rbind, ms)
}

# JSON crudos de FT-01 (Esri JSON, paginado). Devuelve data.frame de atributos.
leer_red_vial_cruda <- function() {
  fs <- list.files(rp("data/raw/red_vial"), pattern = "_p[0-9]+[.]json$", full.names = TRUE)
  if (length(fs) == 0) return(NULL)
  partes <- lapply(fs, function(f) {
    j <- jsonlite::fromJSON(f, simplifyVector = TRUE, flatten = TRUE)
    if (is.null(j$features) || length(j$features) == 0) return(NULL)
    d <- j$features
    names(d) <- sub("^attributes[.]", "", names(d))
    d <- d[, !grepl("^geometry", names(d)), drop = FALSE]
    d$.archivo <- basename(f)
    d
  })
  partes <- Filter(Negate(is.null), partes)
  if (length(partes) == 0) return(NULL)
  cols <- Reduce(union, lapply(partes, names))
  partes <- lapply(partes, function(p) { for (cc in setdiff(cols, names(p))) p[[cc]] <- NA; p[cols] })
  do.call(rbind, partes)
}

sha256_archivo <- function(path) {
  if (requireNamespace("digest", quietly = TRUE)) {
    return(digest::digest(path, algo = "sha256", file = TRUE))
  }
  as.character(openssl::sha256(file(path)))
}

# ---------------------------------------------------------------------------
# Utilidades de tabla
# ---------------------------------------------------------------------------
sin_geom <- function(x) {
  if (inherits(x, "sf")) sf::st_drop_geometry(x) else x
}

nombre_geom <- function(x) {
  if (inherits(x, "sf")) attr(x, "sf_column") else NULL
}

es_nulo <- function(v) {
  if (inherits(v, "sfc")) return(sf::st_is_empty(v))
  if (is.character(v)) return(is.na(v) | trimws(v) == "")
  is.na(v)
}

# Matriz lógica de celdas no nulas para las columnas indicadas.
celdas_no_nulas <- function(tabla, id_col, columnas, alias_geom = "geometria") {
  g <- nombre_geom(tabla)
  out <- list()
  for (cc in columnas) {
    if (cc == alias_geom && !is.null(g) && !(alias_geom %in% names(sin_geom(tabla)))) {
      v <- !sf::st_is_empty(sf::st_geometry(tabla))
    } else if (cc %in% names(tabla)) {
      v <- !es_nulo(tabla[[cc]])
    } else {
      v <- rep(FALSE, nrow(tabla))
    }
    if (any(v)) out[[cc]] <- data.frame(id_tramo = as.character(sin_geom(tabla)[[id_col]][v]),
                                        campo = cc, stringsAsFactors = FALSE)
  }
  if (length(out) == 0) return(data.frame(id_tramo = character(), campo = character()))
  do.call(rbind, out)
}

# Verificación de procedencia. Devuelve lista con diagnósticos; las aserciones
# las hace el archivo de test.
diagnostico_procedencia <- function(tabla, proc, id_col, columnas) {
  esperado <- celdas_no_nulas(tabla, id_col, columnas)
  esperado$llave <- paste(esperado$id_tramo, esperado$campo, sep = "\r")
  proc_llave <- paste(as.character(proc$id_tramo), as.character(proc$campo), sep = "\r")
  conteo <- table(proc_llave)
  list(
    n_celdas = nrow(esperado),
    n_proc = nrow(proc),
    faltantes = esperado[!(esperado$llave %in% names(conteo)), c("id_tramo", "campo")],
    duplicadas = names(conteo)[conteo > 1],
    sobrantes = proc[!(proc_llave %in% esperado$llave), , drop = FALSE],
    campos_fuera = setdiff(unique(as.character(proc$campo)), columnas)
  )
}

vacio_cubre <- function(pend, id, campo) {
  if (is.null(pend) || nrow(pend) == 0) return(rep(FALSE, length(id)))
  glob_todo <- any(pend$id_tramo == "*" & pend$campo == "*", na.rm = TRUE)
  glob_campo <- unique(pend$campo[pend$id_tramo == "*" & !is.na(pend$id_tramo)])
  llaves <- paste(pend$id_tramo, pend$campo, sep = "\r")
  glob_todo | campo %in% glob_campo | paste(id, campo, sep = "\r") %in% llaves |
    paste(id, "*", sep = "\r") %in% llaves
}

resumen_vector <- function(v, n = 10) {
  v <- unique(as.character(v))
  if (length(v) == 0) return("(ninguno)")
  s <- paste(head(v, n), collapse = ", ")
  if (length(v) > n) s <- paste0(s, " ... (+", length(v) - n, ")")
  s
}

# Hallazgos no bloqueantes: se imprimen y quedan en el log, no fallan.
HALLAZGOS <- new.env()
HALLAZGOS$lista <- character()
hallazgo <- function(...) {
  msg <- paste0(...)
  HALLAZGOS$lista <- c(HALLAZGOS$lista, msg)
  message("  [HALLAZGO] ", msg)
  invisible(msg)
}
