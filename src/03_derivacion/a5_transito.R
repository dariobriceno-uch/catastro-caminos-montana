# A5 — Tránsito. Cruce de tramos con puntos censales FT-02.
#
# Ejecutar desde la raíz:  Rscript src/03_derivacion/a5_transito.R [ruta_gpkg]
#   ruta_gpkg por defecto: data/interim/a2_tramos.gpkg (capa `tramos`).
#   Variable de entorno A5_OUT_DIR permite redirigir las salidas (pruebas).
#
# Entradas:
#   data/interim/a2_tramos.gpkg                 (A2: id_tramo, rol, km_inicio, km_fin, utm_zona, geom 4326)
#   data/interim/a5_puntos_censales_planilla.parquet   (src/03_derivacion/a5_prep_planillas.R)
#   data/interim/a5_puntos_censales_rest.parquet       (idem; coordenadas de estaciones)
#
# Salidas (bloque A5 de docs/esquema.md):
#   data/interim/a5_transito.parquet    id_tramo + tmda, tmda_invierno, tmda_composicion,
#                                       punto_censal_id, dist_punto_censal_m, tmda_anio, match_metodo
#   data/interim/procedencia_a5.parquet id_tramo, campo, fuente, fecha_descarga, metodo, agente
#   data/interim/pendientes_a5.csv      id_tramo, campo, motivo, agente, fecha
#
# Reglas de asociación (ver reporte A5 de la fase de preparación):
#   1. Punto censal asociado = estación de control (REST, con coordenadas) más
#      cercana a la geometría del tramo, sin umbral. La distancia se guarda.
#      match_metodo = "espacial".
#   2. TMDA del tramo = rama de esa estación cuyo rol normalizado coincide con el
#      rol del tramo. Se toma el año más reciente disponible para la estación,
#      primero en planilla (trae muestra de junio y composición) y, si la
#      estación no está en planilla, en el REST (solo TMDA anual).
#      - 0 ramas con el rol del tramo  -> NULL + pendiente (la estación mide otro camino)
#      - >1 ramas con el mismo rol     -> tmda, tmda_invierno, tmda_composicion NULL
#        (ambigua: p.ej. Ruta 5 en ambos sentidos; decisión del orquestador,
#        opción (a)). punto_censal_id (estación), dist_punto_censal_m,
#        match_metodo y tmda_anio sí se escriben. pendientes_a5.csv lista los
#        candidatos como "rama_ambigua: <rama_id>=<tmda>; <rama_id>=<tmda>".
#   3. match_metodo = "rol_kilometraje" solo cuando el tramo no tiene geometría
#      utilizable: se busca por rol en planilla y se acepta únicamente si el rol
#      tiene una sola estación-rama en todo el país. El kilometraje no se usa
#      numéricamente porque no se pudo confirmar que planilla (km en texto,
#      esporádico) y Vialidad (KM_I/KM_F) compartan origen. dist = NULL.
#   4. tmda y tmda_invierno se redondean a entero (esquema: entero). La planilla
#      trae decimales en muchos casos; el valor exacto queda en
#      a5_puntos_censales_planilla.parquet.

suppressPackageStartupMessages({ library(sf); library(dplyr); library(arrow) })
options(warn = 1)
if (!file.exists("REGLAS.md")) stop("Ejecutar desde la raíz del repositorio")

args <- commandArgs(trailingOnly = TRUE)
gpkg   <- if (length(args) >= 1) args[1] else "data/interim/a2_tramos.gpkg"
dir_in <- "data/interim"
dir_out <- Sys.getenv("A5_OUT_DIR", unset = dir_in)
dir.create(dir_out, showWarnings = FALSE, recursive = TRUE)
fecha_descarga <- "2026-08-26"
hoy <- format(Sys.Date(), "%Y-%m-%d")

# ---- helpers ----------------------------------------------------------------
rol_norm <- function(x) {
  x <- toupper(trimws(as.character(x))); x <- chartr("ÁÉÍÓÚÑ", "AEIOUN", x)
  x <- gsub("URB\\.? *", "", x)
  x <- gsub("S */ *ROL *\\(([^)]*)\\)", "S/R-\\1", x)   # "S/ROL (B-157)" -> "S/R-B-157"
  x <- gsub("S */ *ROL", "S/R", x)                        # "S/ ROL", "S /ROL" -> "S/R"
  x <- gsub("[[:space:]]*-[[:space:]]*", "-", x)          # "A - 514" -> "A-514"
  x <- gsub("^RUTA-", "RUTA ", x)                         # "RUTA-1" -> "RUTA 1"
  x <- gsub("-CH$", " CH", x)                             # "203-CH" -> "203 CH"
  x <- gsub("[[:space:]]+", " ", x)
  x <- trimws(x)
  x[x %in% c("", "-", "--", "S/R", "NA")] <- NA_character_
  x
}
utm_epsg <- function(z) ifelse(z == 18, 32718L, ifelse(z == 19, 32719L, NA_integer_))
comp_txt <- function(r) {
  # composición porcentual anual del bloque, en el orden literal de la planilla
  nm <- c(pct_autos = "AUTOS", pct_camionetas = "CAMIONETAS", pct_camiones_2_ejes = "CAMIONES 2 EJES",
          pct_camiones_mas_2_ejes = "CAMIONES MAS 2 EJES", pct_semi_remolque = "SEMI REMOLQUE",
          pct_remolque = "REMOLQUE", pct_locomocion_colectiva = "LOCOMOCION COLECTIVA", pct_motos = "MOTOS",
          pct_bicicletas = "BICICLETAS", pct_traccion_animal = "TRACCION ANIMAL", pct_varios = "VARIOS")
  vals <- unlist(r[names(nm)])
  if (all(is.na(vals))) return(NA_character_)
  paste0(nm[!is.na(vals)], "=", formatC(vals[!is.na(vals)], format = "f", digits = 2), collapse = "|")
}

# ---- entradas ---------------------------------------------------------------
tr <- st_read(gpkg, layer = "tramos", quiet = TRUE)
req <- c("id_tramo", "rol", "km_inicio", "km_fin", "utm_zona")
stopifnot(all(req %in% names(tr)))
stopifnot(!any(duplicated(tr$id_tramo)))
if (is.na(st_crs(tr))) st_crs(tr) <- 4326
if (st_crs(tr)$epsg != 4326) tr <- st_transform(tr, 4326)
tr <- st_zm(tr, drop = TRUE, what = "ZM")   # la distancia es planimétrica
tr$rol_n <- rol_norm(tr$rol)
t0 <- Sys.time()

pl <- read_parquet(file.path(dir_in, "a5_puntos_censales_planilla.parquet"))
re <- read_parquet(file.path(dir_in, "a5_puntos_censales_rest.parquet"))

# planilla: una fila por estación-rama × año con TMDA anual, muestra de junio y composición
pl_rama <- pl %>%
  group_by(punto_censal_id, punto_rama_id, anio) %>%
  summarise(rol_planilla = first(rol_planilla),
            tmda_anual = first(tmda_anual),
            tmda_junio = { v <- tmda[muestra == "junio"]; if (length(v)) v[1] else NA_real_ },
            across(starts_with("pct_"), ~ first(.x)), .groups = "drop") %>%
  mutate(rol_n = rol_norm(rol_planilla))
pl_rama$composicion <- vapply(seq_len(nrow(pl_rama)), function(i) comp_txt(pl_rama[i, ]), character(1))

# REST: estaciones con coordenadas (geometría de la capa más reciente en que aparece)
est <- re %>% filter(!is.na(lon), !is.na(lat)) %>%
  group_by(punto_censal_id) %>% slice_max(anio, n = 1, with_ties = FALSE) %>% ungroup() %>%
  select(punto_censal_id, lon, lat, anio_rest = anio)
est_sf <- st_as_sf(est, coords = c("lon", "lat"), crs = 4326)
re_rama <- re %>% mutate(rol_n = rol_norm(rol_rest)) %>%
  select(punto_censal_id, rama_rest, rol_n, rol_rest, tmda_rest, anio)

# ---- 1. asociación espacial -------------------------------------------------
tr$punto_est <- NA_character_; tr$dist_m <- NA_real_; tr$match_metodo <- NA_character_
geom_ok <- !st_is_empty(tr) & !is.na(tr$utm_zona) & !is.na(utm_epsg(tr$utm_zona))
if (nrow(est_sf) > 0) {
  for (z in unique(tr$utm_zona[geom_ok])) {
    i <- which(geom_ok & tr$utm_zona == z)
    crs_z <- utm_epsg(z)
    t_z <- st_transform(tr[i, ], crs_z); e_z <- st_transform(est_sf, crs_z)
    k <- st_nearest_feature(t_z, e_z)
    tr$punto_est[i] <- e_z$punto_censal_id[k]
    tr$dist_m[i] <- as.numeric(st_distance(t_z, e_z[k, ], by_element = TRUE))
    tr$match_metodo[i] <- "espacial"
  }
}

# ---- 2. selección de rama y TMDA -------------------------------------------
out <- data.frame(id_tramo = tr$id_tramo, tmda = NA_integer_, tmda_invierno = NA_integer_,
                  tmda_composicion = NA_character_, punto_censal_id = NA_character_,
                  dist_punto_censal_m = tr$dist_m, tmda_anio = NA_integer_,
                  match_metodo = tr$match_metodo, stringsAsFactors = FALSE)
pend <- list()
add_pend <- function(id, campo, motivo) pend[[length(pend) + 1]] <<- data.frame(
  id_tramo = id, campo = campo, motivo = motivo, agente = "A5", fecha = hoy, stringsAsFactors = FALSE)
campos_tmda <- c("tmda", "tmda_invierno", "tmda_composicion", "tmda_anio")

for (i in seq_len(nrow(tr))) {
  id <- tr$id_tramo[i]; rn <- tr$rol_n[i]; e <- tr$punto_est[i]
  if (is.na(e)) {
    # 3. sin geometría: fallback por rol (solo si el rol es único en planilla)
    cand <- pl_rama %>% filter(!is.na(rol_n), rol_n == rn)
    if (nrow(cand) && n_distinct(cand$punto_rama_id) == 1) {
      cand <- cand %>% slice_max(anio, n = 1, with_ties = FALSE)
      out$match_metodo[i] <- "rol_kilometraje"
      out$punto_censal_id[i] <- cand$punto_rama_id
      out$tmda[i] <- as.integer(round(cand$tmda_anual)); out$tmda_invierno[i] <- as.integer(round(cand$tmda_junio))
      out$tmda_composicion[i] <- cand$composicion; out$tmda_anio[i] <- as.integer(cand$anio)
      add_pend(id, "dist_punto_censal_m", "tramo sin geometría utilizable; asociación por rol único en planilla, sin distancia")
    } else {
      for (cp in c(campos_tmda, "punto_censal_id", "dist_punto_censal_m", "match_metodo"))
        add_pend(id, cp, if (is.na(rn)) "tramo sin geometría utilizable y sin rol" else
          paste0("tramo sin geometría utilizable; rol '", tr$rol[i], "' con ", n_distinct(cand$punto_rama_id), " estación-rama en planilla (se exige 1)"))
    }
    next
  }
  out$punto_censal_id[i] <- e
  cand <- pl_rama %>% filter(punto_censal_id == e)
  origen <- "planilla"
  if (!nrow(cand)) {
    cand <- re_rama %>% filter(punto_censal_id == e, !is.na(rol_n)) %>%
      transmute(punto_censal_id, punto_rama_id = paste0(punto_censal_id, "-R", rama_rest), anio,
                rol_planilla = rol_rest, tmda_anual = tmda_rest, tmda_junio = NA_real_, rol_n, composicion = NA_character_)
    origen <- "rest"
  }
  if (!nrow(cand)) { for (cp in campos_tmda) add_pend(id, cp, paste0("estación ", e, " sin ramas con rol en planilla ni REST")); next }
  cand <- cand %>% filter(anio == max(anio))
  if (is.na(rn)) {
    # Hallazgo A1: rol "S/R", "-" o vacío -> no hay rol identificable. Se escribe
    # la estación, la distancia, el método y el año; tmda* NULL con pendiente.
    out$tmda_anio[i] <- as.integer(max(cand$anio))
    for (cp in c("tmda", "tmda_invierno", "tmda_composicion"))
      add_pend(id, cp, paste0("rol_no_identificable: rol del tramo '", tr$rol[i], "'; estación ", e, " mide [", paste(unique(cand$rol_planilla), collapse = "; "), "]"))
    next
  }
  sel <- cand %>% filter(!is.na(rol_n), rol_n == rn)
  if (nrow(sel) == 0) {
    for (cp in campos_tmda) add_pend(id, cp, paste0("estación más cercana ", e, " (", origen, ", ", max(cand$anio), ") mide roles [",
      paste(unique(cand$rol_planilla), collapse = "; "), "], no el rol del tramo '", tr$rol[i], "'"))
    next
  }
  if (n_distinct(sel$punto_rama_id) > 1) {
    # Decisión del orquestador (2026-08-26), opción (a): ramas ambiguas -> tmda,
    # tmda_invierno y tmda_composicion NULL; punto_censal_id (estación),
    # dist_punto_censal_m, match_metodo y tmda_anio sí se escriben porque
    # describen la estación asociada, no la rama. Candidatos a pendientes.
    out$tmda_anio[i] <- as.integer(max(sel$anio))
    motivo <- paste0("rama_ambigua: ", paste0(sel$punto_rama_id, "=", round(sel$tmda_anual), collapse = "; "))
    for (cp in c("tmda", "tmda_invierno", "tmda_composicion")) add_pend(id, cp, motivo)
    next
  }
  sel <- sel[1, ]
  out$punto_censal_id[i] <- sel$punto_rama_id
  out$tmda[i] <- as.integer(round(sel$tmda_anual))
  out$tmda_invierno[i] <- as.integer(round(sel$tmda_junio))
  out$tmda_composicion[i] <- sel$composicion
  out$tmda_anio[i] <- as.integer(sel$anio)
  if (is.na(out$tmda[i])) add_pend(id, "tmda", paste0("rama ", sel$punto_rama_id, " sin TMDA anual en la fuente"))
  if (is.na(out$tmda_invierno[i])) add_pend(id, "tmda_invierno", if (origen == "rest") paste0("estación ", e, " solo en REST (", sel$anio, "): sin muestra de junio") else paste0("rama ", sel$punto_rama_id, " sin muestra de junio"))
  if (is.na(out$tmda_composicion[i])) add_pend(id, "tmda_composicion", if (origen == "rest") paste0("estación ", e, " solo en REST: sin composición") else paste0("rama ", sel$punto_rama_id, " sin distribución porcentual"))
}

# ---- procedencia ------------------------------------------------------------
metodo_campo <- c(tmda = "declarado", tmda_invierno = "declarado", tmda_composicion = "declarado",
                  punto_censal_id = "declarado", tmda_anio = "declarado",
                  dist_punto_censal_m = "derivado", match_metodo = "derivado")
proc <- bind_rows(lapply(names(metodo_campo), function(cp) {
  ok <- !is.na(out[[cp]])
  if (!any(ok)) return(NULL)
  data.frame(id_tramo = out$id_tramo[ok], campo = cp, fuente = "FT-02", fecha_descarga = fecha_descarga,
             metodo = metodo_campo[[cp]], agente = "A5", stringsAsFactors = FALSE)
}))
pend_df <- if (length(pend)) bind_rows(pend) else
  data.frame(id_tramo = character(), campo = character(), motivo = character(), agente = character(), fecha = character())

# ---- aserciones internas ----------------------------------------------------
stopifnot(identical(names(out), c("id_tramo", "tmda", "tmda_invierno", "tmda_composicion", "punto_censal_id",
                                  "dist_punto_censal_m", "tmda_anio", "match_metodo")))
stopifnot(nrow(out) == nrow(tr), !any(duplicated(out$id_tramo)))
stopifnot(all(is.na(out$match_metodo) | out$match_metodo %in% c("espacial", "rol_kilometraje")))
stopifnot(all(is.na(out$dist_punto_censal_m) | out$dist_punto_censal_m >= 0))
n_no_nulos <- sum(!is.na(out[, setdiff(names(out), "id_tramo")]))
stopifnot(nrow(proc) == n_no_nulos)               # completitud de procedencia
stopifnot(all(proc$metodo %in% c("derivado", "declarado", "estimado")))
# toda celda NULL de un tramo con geometría tiene fila en pendientes
for (cp in setdiff(names(out), "id_tramo")) {
  nulos <- out$id_tramo[is.na(out[[cp]])]
  faltan <- setdiff(nulos, pend_df$id_tramo[pend_df$campo == cp])
  if (length(faltan)) stop("celdas NULL sin pendiente en ", cp, ": ", paste(head(faltan), collapse = ","))
}

write_parquet(out, file.path(dir_out, "a5_transito.parquet"))
write_parquet(proc, file.path(dir_out, "procedencia_a5.parquet"))
write.csv(pend_df, file.path(dir_out, "pendientes_a5.csv"), row.names = FALSE, fileEncoding = "UTF-8")

cat("A5: tramos", nrow(out), "| espacial", sum(out$match_metodo == "espacial", na.rm = TRUE),
    "| rol_kilometraje", sum(out$match_metodo == "rol_kilometraje", na.rm = TRUE), "\n")
for (cp in setdiff(names(out), "id_tramo")) cat("  NULL", cp, ":", sum(is.na(out[[cp]])), "\n")
cat("  dist_punto_censal_m mediana:", round(median(out$dist_punto_censal_m, na.rm = TRUE)),
    "| >5000 m:", sum(out$dist_punto_censal_m > 5000, na.rm = TRUE), "\n")
cat("  procedencia filas:", nrow(proc), "| pendientes filas:", nrow(pend_df), "\n")
cat("  rama_ambigua:", n_distinct(pend_df$id_tramo[grepl("^rama_ambigua", pend_df$motivo)]),
    "| rol_no_identificable:", n_distinct(pend_df$id_tramo[grepl("^rol_no_identificable", pend_df$motivo)]), "\n")
cat("  tmda_anio:", paste(names(table(out$tmda_anio)), table(out$tmda_anio), collapse = " "), "\n")
cat("  dist p95:", round(quantile(out$dist_punto_censal_m, 0.95, na.rm = TRUE)), "| >10000 m:", sum(out$dist_punto_censal_m > 10000, na.rm = TRUE), "\n")
cat("  tiempo:", round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1), "min\n")
