# a7_nieve.R — Bloque A7: días con nieve por tramo, desde los conteos de
# Earth Engine (FT-08, MOD10A1) descargados INTACTOS en data/raw/nieve/.
#
# Insumo:  data/raw/nieve/nieve_<region>.csv   (uno por región, export de a7_nieve_ee.py)
#          columnas: id_tramo, nieve_YYYY, valido_YYYY, nieve_YYYY_MM, valido_YYYY_MM
#          (mediana de los píxeles del buffer de 500 m, por año y por mes)
# Salida:  data/interim/a7_nieve.parquet, procedencia_a7.parquet, pendientes_a7.csv
#
# Método (docs/esquema.md, bloque A7):
#   año válido     valido_YYYY >= MIN_VALIDOS_ANIO días con observación (sin nube)
#   días por año   nieve_YYYY / valido_YYYY * 365        (escalado a 365)
#   dias_nieve_mediana / _media / _sd   sobre los años válidos de la serie
#   n_anios_validos                     cuántos años entraron al cálculo
#   dias_validos_mediana                mediana de valido_YYYY (fiabilidad)
#   meses_nieve   nº de meses del año en que la mediana interanual de
#                 (nieve_m / valido_m * días del mes) supera MIN_DIAS_MES
#   serie_inicio, serie_fin             años de la serie
# Un tramo con menos de MIN_ANIOS años válidos queda NULL y va a pendientes.

suppressPackageStartupMessages({library(arrow); library(dplyr); library(digest); library(jsonlite)})
root <- normalizePath(".", winslash = "/")
hoy  <- format(Sys.Date(), "%Y-%m-%d")

RAW_DIR <- file.path(root, "data/raw/nieve")
OUT_DIR <- file.path(root, "data/interim")
ESTADO  <- file.path(RAW_DIR, "tareas_ee.json")

SERIE_INI <- 2010L; SERIE_FIN <- 2024L
MIN_VALIDOS_ANIO <- 60L    # decisión 2026-08-27: 120 dejaba NULL el 13,9 % (sur nuboso) sin cambiar los valores donde ambos existen
MIN_ANIOS        <- 10L    # y un tramo con menos de 10 años válidos no se resume
MIN_DIAS_MES     <- 5      # umbral de "mes con nieve"

archivos <- list.files(RAW_DIR, pattern = "^nieve_.*[.]csv$", full.names = TRUE)
stopifnot(length(archivos) > 0)
est <- if (file.exists(ESTADO)) fromJSON(ESTADO) else list()

crudo <- bind_rows(lapply(archivos, function(f) {
  d <- read.csv(f, stringsAsFactors = FALSE, check.names = FALSE, encoding = "UTF-8")
  d$`system:index` <- NULL; d$.geo <- NULL
  d$id_tramo <- trimws(d$id_tramo)   # EE antepone un espacio a los ids que empiezan con guion
  d$archivo <- basename(f); d
}))
message("tramos en los CSV: ", nrow(crudo), " (", length(archivos), " archivos)")
stopifnot(!anyDuplicated(crudo$id_tramo))

anios <- SERIE_INI:SERIE_FIN
nieve_a  <- as.matrix(crudo[, paste0("nieve_", anios)])
valido_a <- as.matrix(crudo[, paste0("valido_", anios)])
ok_a <- !is.na(valido_a) & valido_a >= MIN_VALIDOS_ANIO & !is.na(nieve_a)
dias_a <- ifelse(ok_a, nieve_a / valido_a * 365, NA_real_)

n_ok <- rowSums(ok_a)
resumir <- function(f) vapply(seq_len(nrow(dias_a)), function(i)
  if (n_ok[i] >= MIN_ANIOS) f(dias_a[i, ok_a[i, ]]) else NA_real_, numeric(1))
dias_mediana <- resumir(median)
dias_media   <- resumir(mean)
dias_sd      <- resumir(sd)
validos_med  <- vapply(seq_len(nrow(valido_a)), function(i) median(valido_a[i, ], na.rm = TRUE), numeric(1))

# meses con nieve: mediana interanual de los días escalados de cada mes
days_in_month <- function(a, m) {
  d1 <- as.Date(sprintf("%d-%02d-01", a, m))
  as.integer(format(seq(d1, by = "month", length.out = 2)[2] - 1, "%d"))
}
dias_mes <- function(a, m) {
  n <- crudo[[sprintf("nieve_%d_%02d", a, m)]]; v <- crudo[[sprintf("valido_%d_%02d", a, m)]]
  ifelse(!is.na(v) & v >= 5, n / v * days_in_month(a, m), NA_real_)   # mes con < 5 días observados: sin dato
}
meses <- integer(nrow(crudo))
for (m in 1:12) {
  mat <- sapply(anios, function(a) dias_mes(a, m))
  med <- apply(mat, 1, median, na.rm = TRUE)
  meses <- meses + as.integer(!is.na(med) & med > MIN_DIAS_MES)
}
meses[is.na(dias_mediana)] <- NA_integer_

a7 <- data.frame(
  id_tramo = crudo$id_tramo,
  dias_nieve_mediana   = round(dias_mediana, 1),
  dias_nieve_media     = round(dias_media, 1),
  dias_nieve_sd        = round(dias_sd, 1),
  meses_nieve          = meses,
  n_anios_validos      = as.integer(n_ok),
  dias_validos_mediana = round(validos_med),
  serie_inicio = ifelse(is.na(dias_mediana), NA_integer_, SERIE_INI),
  serie_fin    = ifelse(is.na(dias_mediana), NA_integer_, SERIE_FIN),
  stringsAsFactors = FALSE)

# tramos de la base que no vinieron en ningún CSV
base <- read_parquet(file.path(root, "data/processed/tramos.parquet"), col_select = "id_tramo")
falt <- setdiff(base$id_tramo, a7$id_tramo)
if (length(falt)) a7 <- bind_rows(a7, data.frame(id_tramo = falt, stringsAsFactors = FALSE))
message("dias_nieve_mediana NULL: ", sum(is.na(a7$dias_nieve_mediana)), " de ", nrow(a7))
print(summary(a7$dias_nieve_mediana))

COLS_A7 <- setdiff(names(a7), "id_tramo")
fecha_desc <- if (length(est)) substr(min(sapply(est, `[[`, "lanzada_utc")), 1, 10) else hoy
procedencia <- bind_rows(lapply(COLS_A7, function(cn) {
  ok <- !is.na(a7[[cn]])
  data.frame(id_tramo = a7$id_tramo[ok], campo = cn, fuente = "FT-08",
             fecha_descarga = fecha_desc, metodo = "derivado", agente = "A7", stringsAsFactors = FALSE)
}))

pend <- list(); addp <- function(id, campo, motivo)
  pend[[length(pend) + 1]] <<- data.frame(id_tramo = id, campo = campo, motivo = motivo,
                                          agente = "A7", fecha = hoy, stringsAsFactors = FALSE)
for (id in falt) for (cn in COLS_A7) addp(id, cn, "el tramo no vino en ningún CSV de Earth Engine")
pocos <- a7$id_tramo[!a7$id_tramo %in% falt & is.na(a7$dias_nieve_mediana)]
for (id in pocos) for (cn in setdiff(COLS_A7, c("n_anios_validos", "dias_validos_mediana")))
  addp(id, cn, sprintf("menos de %d años con al menos %d días observados (nubes)", MIN_ANIOS, MIN_VALIDOS_ANIO))
pendientes <- if (length(pend)) bind_rows(pend) else
  data.frame(id_tramo = character(), campo = character(), motivo = character(), agente = character(), fecha = character())

write_parquet(a7, file.path(OUT_DIR, "a7_nieve.parquet"))
write_parquet(procedencia, file.path(OUT_DIR, "procedencia_a7.parquet"))
write.csv(pendientes, file.path(OUT_DIR, "pendientes_a7.csv"), row.names = FALSE, fileEncoding = "UTF-8")

# manifiesto: un registro por CSV crudo (Regla 3)
man <- lapply(archivos, function(f) list(
  fuente = "FT-08", archivo = sub(paste0("^", root, "/?"), "", f),
  url = "Google Earth Engine, export a Drive (MODIS/061/MOD10A1); ver tareas_ee.json",
  timestamp_utc = fecha_desc, n_registros = nrow(read.csv(f)),
  sha256 = digest(f, algo = "sha256", file = TRUE), agente = "A7",
  notas = sprintf("serie %d-%d; NDSI>=40; buffer 500 m; mediana de píxeles; conteos por año y mes", SERIE_INI, SERIE_FIN)))
writeLines(toJSON(man, auto_unbox = TRUE, pretty = TRUE), file.path(root, "data/raw/manifest/A7.json"), useBytes = TRUE)
message("escrito a7_nieve.parquet, procedencia_a7.parquet, pendientes_a7.csv, manifest/A7.json")
