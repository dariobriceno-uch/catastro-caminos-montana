#!/usr/bin/env Rscript
# =============================================================================
# A3 — Altimetría. Catastro nacional de caminos de montaña (FONDEF IDeA)
# =============================================================================
#
# Uso (desde la raíz del repositorio):
#   Rscript src/03_derivacion/a3_altimetria.R [entrada.gpkg] [dir_salida]
#   Por defecto: data/interim/a2_tramos.gpkg  ->  data/interim/
#   Variables de entorno opcionales:
#     A3_CKPT  directorio de checkpoints (por defecto <tempdir>/a3_ckpt). Si
#              existe de una corrida anterior, se reutilizan el muestreo, las
#              teselas ya procesadas y los rangos Kapos ya calculados.
#     A3_LOG   ruta del log (por defecto logs/a3_altimetria.log, modo append).
#
# Entrada : capa `tramos` con `id_tramo`, `id_tramo_a1`, `utm_zona` y
#           geometría (Multi)LineString Z en EPSG:4326 (bloque A2).
# Salidas : <dir_salida>/a3_altimetria.parquet   (bloque A3 de docs/esquema.md)
#           <dir_salida>/procedencia_a3.parquet  (formato largo del protocolo)
#           <dir_salida>/vacios_a3.csv
#           Se escriben SOLO al final, completas.
#
# Fuente  : FT-07 Copernicus DEM GLO-30 (COG, bucket público
#           s3://copernicus-dem-30m/), leído por /vsicurl/ sin descargar
#           teselas a data/raw. Índice: data/raw/dem/tile_index_glo30.csv.
#           FT-09 (Kapos) se replica como regla sobre FT-07.
#           FT-01 solo como contraste (Z de la geometría).
#
# -----------------------------------------------------------------------------
# MÉTODO
# -----------------------------------------------------------------------------
# 1. Cada tramo se proyecta a UTM (EPSG:32718 / 32719 según `utm_zona`) y se
#    muestrea a lo largo de la traza cada PASO_M = 30 m (más los dos extremos)
#    por interpolación lineal sobre la distancia acumulada de los vértices.
#    MultiLineString: st_line_merge; si sigue siendo múltiple, las partes se
#    encadenan en su orden de almacenamiento y se registra en el log.
# 2. Las muestras (EPSG:4326) se agrupan por tesela de 1°×1° (floor lat/lon).
#    Por cada tesela en uso se construye un VRT con la tesela y sus vecinas
#    existentes (3×3) y se lee A MEMORIA, con un solo acceso remoto, la
#    ventana de la tesela más un margen de 3 píxeles. Sobre esa ventana se
#    calcula terrain(slope, aspect) y se extraen todas las muestras de la
#    tesela. Así la bilineal en el borde de tesela es continua, los tramos que
#    cruzan teselas se leen sin costura y el COG se abre una vez por tesela.
# 3. Cota por muestra: extracción BILINEAL. Si alguna muestra del tramo queda
#    NoData (NA), TODAS las columnas A3 del tramo van NULL y el tramo pasa a
#    vacíos (criterio estricto: no se interpola ni se rellena).
# 4. Perfil longitudinal z(d). Sin suavizar: cota_min, cota_max, cota_media
#    (media de muestras; equivale a media ponderada por longitud por el paso
#    constante). Perfil SUAVIZADO con media móvil centrada de
#    VENTANA_SUAVIZADO = 5 muestras (~150 m, bordes truncados) para todo lo
#    que depende de la derivada:
#    - pendiente_i = atan(dz_i/dd_i) en grados por segmento entre muestras.
#    - pendiente_media = media de |pendiente_i| ponderada por longitud.
#      pendiente_max = max |pendiente_i|.
#    - desnivel_subida_m = suma de dz_i > 0; desnivel_bajada_m = suma |dz_i < 0|.
#    - cruza_portezuelo: existe un máximo local INTERIOR del perfil suavizado
#      con (z_pico − mín izquierda) > 200 m y (z_pico − mín derecha) > 200 m.
#    - cota_culminante: cota (perfil crudo) en el máximo local interior de
#      mayor prominencia bilateral del perfil suavizado; si no hay máximo
#      local interior, = cota_max. Nunca supera cota_max.
# 5. orientacion_ladera: aspecto del DEM (terrain, 8 vecinos) en la celda de
#    cada muestra, clasificado en 8 rumbos (N, NE, E, SE, S, SO, O, NO,
#    sectores de 45°), descartando celdas con pendiente de terreno 0. Moda.
#    Todas planas → NULL + vacío.
# 6. sinuosidad = longitud proyectada / distancia euclídea entre extremos.
#    Extremos coincidentes (< 1 m) → NULL + vacío.
# 7. clase_kapos (FT-09 sobre FT-07), evaluada en la muestra de cota_max:
#      E = cota_max; S = pendiente del TERRENO (grados) en esa celda;
#      R = max − min del DEM en radio 7 km alrededor de esa muestra, leído
#      del overview nivel 1 del COG (~124 m; Kapos original: 1 km). R solo se
#      calcula cuando la regla lo necesita (300 ≤ E ≤ 1500).
#      1: E>4500 | 2: 3500<E≤4500 | 3: 2500<E≤3500 | 4: 1500<E≤2500 & S≥2 |
#      5: 1000<E≤1500 & (S≥5 | R>300) | 6: 300≤E≤1000 & R>300 | 0: ninguna.
#      Clase 7 NO es derivable por umbrales: se escribe 0 y queda UNA fila en
#      vacíos (id_tramo = *) advirtiendo que un 0 puede encubrir clase 7.
# 8. cota_max_z_mop = máximo del Z de la geometría de entrada (FT-01,
#    contraste); delta_z_m = cota_max − cota_max_z_mop. Filas cuyo Z es
#    íntegramente 0 o ausente → ambas NULL + vacío `z_mop_cero`.
#
# Procedencia: una fila por celda no nula; metodo `derivado`; agente A3.
# fuente: FT-07 para todo; `FT-07;FT-09` en clase_kapos (regla Kapos sobre el
# DEM) y `FT-07;FT-01` en cota_max_z_mop / delta_z_m (contraste DEM vs Z de
# FT-01). fecha_descarga: fecha UTC de ejecución para FT-07 (lectura remota,
# sin descarga previa); para el contraste con FT-01, fecha del manifest A1.
# =============================================================================

suppressPackageStartupMessages({
  library(sf); library(terra); library(dplyr); library(arrow); library(jsonlite)
})
options(warn = 1); terraOptions(progress = 0, memfrac = 0.6)

# ---- parámetros --------------------------------------------------------------
PASO_M            <- 30
VENTANA_SUAVIZADO <- 5
UMBRAL_PORTEZUELO <- 200
RADIO_KAPOS_M     <- 7000
OVERVIEW_KAPOS    <- 1
BUCKET            <- "https://copernicus-dem-30m.s3.amazonaws.com"
AGENTE            <- "A3"

args    <- commandArgs(trailingOnly = TRUE)
f_in    <- if (length(args) >= 1) args[1] else "data/interim/a2_tramos.gpkg"
dir_out <- if (length(args) >= 2) args[2] else "data/interim"
f_index <- "data/raw/dem/tile_index_glo30.csv"
ckpt    <- Sys.getenv("A3_CKPT", file.path(tempdir(), "a3_ckpt"))
f_log   <- Sys.getenv("A3_LOG", "logs/a3_altimetria.log")
dir.create(ckpt, showWarnings = FALSE, recursive = TRUE)
dir.create(dirname(f_log), showWarnings = FALSE, recursive = TRUE)
dir.create(dir_out, showWarnings = FALSE, recursive = TRUE)
fecha_hoy <- format(Sys.time(), "%Y-%m-%d", tz = "UTC")
T_INI <- Sys.time()

log_msg <- function(...) {
  s <- paste(format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "|", sprintf(...))
  cat(s, "\n"); cat(s, "\n", file = f_log, append = TRUE)
}
log_msg("==== A3 inicio | entrada=%s salida=%s ckpt=%s", f_in, dir_out, ckpt)
stopifnot(file.exists(f_in), file.exists(f_index))

# ---- índice de teselas -------------------------------------------------------
idx <- read.csv(f_index, stringsAsFactors = FALSE)
idx <- idx[idx$existe %in% c(TRUE, "TRUE", "True"), ]
tile_name <- function(lat, lon)
  sprintf("Copernicus_DSM_COG_10_%s%02d_00_%s%03d_00_DEM",
          ifelse(lat < 0, "S", "N"), abs(lat), ifelse(lon < 0, "W", "E"), abs(lon))
tile_url <- function(tn) sprintf("/vsicurl/%s/%s/%s.tif", BUCKET, tn, tn)
tile_ok  <- function(tn) tn %in% idx$tesela
tile_ll  <- function(tn) {
  lat <- as.integer(sub(".*_[NS](\\d{2})_00_.*", "\\1", tn)) * ifelse(grepl("_S\\d", tn), -1, 1)
  lon <- as.integer(sub(".*_[EW](\\d{3})_00_.*", "\\1", tn)) * ifelse(grepl("_W\\d", tn), -1, 1)
  c(lat = lat, lon = lon)
}

# ---- fecha FT-01 desde manifest A1 ------------------------------------------
fecha_ft01 <- NA_character_
mf_a1 <- "data/raw/manifest/A1.json"
if (file.exists(mf_a1)) {
  m <- tryCatch(fromJSON(mf_a1, simplifyVector = TRUE), error = function(e) NULL)
  if (!is.null(m) && "fuente" %in% names(m)) {
    ts <- m$timestamp_utc[m$fuente == "FT-01"]; ts <- ts[!is.na(ts) & nzchar(ts)]
    if (length(ts)) fecha_ft01 <- substr(min(ts), 1, 10)
  }
}
if (is.na(fecha_ft01)) { fecha_ft01 <- fecha_hoy; log_msg("AVISO: sin fecha FT-01 en %s; se usa fecha de ejecución", mf_a1) }
log_msg("fecha FT-01 (manifest A1): %s", fecha_ft01)

# ---- lectura de tramos -------------------------------------------------------
tr <- st_read(f_in, layer = "tramos", quiet = TRUE)
stopifnot(all(c("id_tramo", "id_tramo_a1", "utm_zona") %in% names(tr)))
if (is.na(st_crs(tr))) st_crs(tr) <- 4326
if (is.na(st_crs(tr)$epsg) || st_crs(tr)$epsg != 4326) tr <- st_transform(tr, 4326)
stopifnot(!any(duplicated(tr$id_tramo)))
n_tr <- nrow(tr)
log_msg("tramos leídos: %d", n_tr)

pend <- list()
add_pend <- function(id, campo, motivo)
  pend[[length(pend) + 1]] <<- data.frame(id_tramo = id, campo = campo, motivo = motivo,
                                          agente = AGENTE, fecha = fecha_hoy, stringsAsFactors = FALSE)

# ---- Z de FT-01 (contraste) y muestreo --------------------------------------
f_S <- file.path(ckpt, "muestras.rds")
muestrear <- function(geom_ll, utm_zona, id) {
  if (!utm_zona %in% c(18, 19)) {
    lon <- mean(st_bbox(geom_ll)[c(1, 3)])
    utm_zona <- if (lon < -72) 18 else 19
    log_msg("AVISO %s: utm_zona ausente/inválida; se usa %d por longitud del centro", id, utm_zona)
  }
  epsg <- 32700 + utm_zona
  g <- st_transform(st_zm(geom_ll), epsg)
  if (st_geometry_type(g) == "MULTILINESTRING") {
    g2 <- st_line_merge(g)
    if (st_geometry_type(g2) == "LINESTRING") g <- g2 else
      log_msg("AVISO %s: MULTILINESTRING no fusionable (%d partes); partes encadenadas en orden",
              id, length(st_cast(g, "LINESTRING")))
  }
  cc <- st_coordinates(g)[, c("X", "Y"), drop = FALSE]
  if (nrow(cc) < 2) return(NULL)
  seg <- sqrt(rowSums(diff(cc)^2)); d <- c(0, cumsum(seg)); L <- d[length(d)]
  if (L <= 0) return(NULL)
  dt <- unique(c(seq(0, L, by = PASO_M), L))
  x <- approx(d, cc[, 1], xout = dt, ties = "ordered")$y
  y <- approx(d, cc[, 2], xout = dt, ties = "ordered")$y
  ll <- sf_project(paste0("EPSG:", epsg), "EPSG:4326", cbind(x, y))
  data.frame(id_tramo = id, k = seq_along(dt), d = dt, lon = ll[, 1], lat = ll[, 2], L = L,
             dist_extremos = sqrt(sum((cc[nrow(cc), ] - cc[1, ])^2)), stringsAsFactors = FALSE)
}
if (file.exists(f_S)) {
  tmp <- readRDS(f_S); S <- tmp$S; z_max_mop <- tmp$z_max_mop; rm(tmp)
  log_msg("checkpoint de muestreo reutilizado: %d muestras", nrow(S))
} else {
  z_max_mop <- rep(NA_real_, n_tr); S_l <- vector("list", n_tr); t0 <- Sys.time()
  for (i in seq_len(n_tr)) {
    g <- st_geometry(tr)[i]
    cc <- st_coordinates(g)
    if ("Z" %in% colnames(cc)) { z <- cc[, "Z"]; if (!all(is.na(z))) z_max_mop[i] <- max(z, na.rm = TRUE) }
    S_l[[i]] <- muestrear(g, tr$utm_zona[i], tr$id_tramo[i])
    if (i %% 2000 == 0) log_msg("muestreo %d/%d (%s)", i, n_tr, format(round(Sys.time() - t0, 1)))
  }
  S <- bind_rows(S_l); rm(S_l)
  S$tile <- tile_name(floor(S$lat), floor(S$lon))
  saveRDS(list(S = S, z_max_mop = z_max_mop), f_S)
}
sin_geom <- setdiff(tr$id_tramo, unique(S$id_tramo))
for (id in sin_geom) add_pend(id, "*", "geometría vacía o de longitud cero")
log_msg("muestras: %d en %d teselas; tramos sin geometría útil: %d",
        nrow(S), length(unique(S$tile)), length(sin_geom))

# ---- acceso al DEM -----------------------------------------------------------
cache_ov <- new.env()
abrir_ov <- function(tn) {           # overview en memoria, para el rango Kapos
  if (!exists(tn, envir = cache_ov)) {
    r <- rast(tile_url(tn), opts = sprintf("OVERVIEW_LEVEL=%d", OVERVIEW_KAPOS))
    assign(tn, toMemory(r), envir = cache_ov)
  }
  get(tn, envir = cache_ov)
}
vecinas <- function(tn) {
  p <- tile_ll(tn); g <- expand.grid(la = p["lat"] + (-1:1), lo = p["lon"] + (-1:1))
  v <- tile_name(g$la, g$lo); v[tile_ok(v)]
}
leer_tesela_mem <- function(tn) {    # tesela + margen de 3 px, en memoria
  v <- vecinas(tn)
  r <- if (length(v) == 1) rast(tile_url(v)) else
    vrt(tile_url(v), filename = tempfile(fileext = ".vrt"), overwrite = TRUE)
  p <- tile_ll(tn); m <- 3 * res(r)[1]
  e <- ext(p["lon"] - m, p["lon"] + 1 + m, p["lat"] - m, p["lat"] + 1 + m)
  toMemory(crop(r, e))
}
rumbo8 <- function(a) c("N", "NE", "E", "SE", "S", "SO", "O", "NO")[(floor(((a %% 360) + 22.5) / 45) %% 8) + 1]
rango_local <- function(lon, lat) {
  dlat <- RADIO_KAPOS_M / 111320; dlon <- RADIO_KAPOS_M / (111320 * cos(lat * pi / 180))
  e <- ext(lon - dlon, lon + dlon, lat - dlat, lat + dlat)
  g <- expand.grid(la = floor(lat - dlat):floor(lat + dlat), lo = floor(lon - dlon):floor(lon + dlon))
  ts <- tile_name(g$la, g$lo); ts <- ts[tile_ok(ts)]
  if (!length(ts)) return(NA_real_)
  circ <- terra::buffer(terra::vect(cbind(lon, lat), crs = "EPSG:4326"), RADIO_KAPOS_M)
  mn <- Inf; mx <- -Inf
  for (tn in ts) {
    r <- abrir_ov(tn)
    ei <- tryCatch(terra::intersect(ext(r), e), error = function(err) NULL); if (is.null(ei)) next
    cr <- terra::mask(crop(r, ei), circ, touches = TRUE)
    v <- values(cr, mat = FALSE); v <- v[!is.na(v)]
    if (length(v)) { mn <- min(mn, min(v)); mx <- max(mx, max(v)) }
  }
  if (is.infinite(mn)) NA_real_ else mx - mn
}

# ---- extracción por tesela (checkpoint por tesela) ---------------------------
S$z <- NA_real_; S$aspecto <- NA_real_; S$slope_terr <- NA_real_
tiles_uso <- sort(unique(S$tile))
faltantes <- tiles_uso[!tile_ok(tiles_uso)]
if (length(faltantes)) log_msg("AVISO: %d teselas requeridas no existen en GLO-30: %s",
                               length(faltantes), paste(faltantes, collapse = ", "))
t0 <- Sys.time(); n_done <- 0
for (tn in tiles_uso) {
  ii <- which(S$tile == tn); n_done <- n_done + 1
  if (!tile_ok(tn)) next
  f_ck <- file.path(ckpt, paste0("tile_", tn, ".rds"))
  if (file.exists(f_ck)) {
    ck <- readRDS(f_ck)
    if (nrow(ck) == length(ii)) {
      S$z[ii] <- ck$z; S$aspecto[ii] <- ck$aspecto; S$slope_terr[ii] <- ck$slope_terr; next
    }
  }
  ok <- FALSE
  for (intento in 1:3) {
    res_t <- tryCatch({
      rm_ <- leer_tesela_mem(tn)
      te  <- terrain(rm_, v = c("slope", "aspect"), unit = "degrees", neighbors = 8)
      pv  <- terra::vect(cbind(S$lon[ii], S$lat[ii]), crs = "EPSG:4326")
      z   <- extract(rm_, pv, method = "bilinear", ID = FALSE)[[1]]
      ex  <- extract(te, pv, method = "simple", ID = FALSE)
      data.frame(z = z, aspecto = ex$aspect, slope_terr = ex$slope)
    }, error = function(e) { log_msg("ERROR tesela %s intento %d: %s", tn, intento, conditionMessage(e)); NULL })
    if (!is.null(res_t)) { ok <- TRUE; break }
    Sys.sleep(10 * intento)
  }
  if (!ok) { log_msg("FALLO definitivo tesela %s: %d muestras quedan NoData", tn, length(ii)); next }
  S$z[ii] <- res_t$z; S$aspecto[ii] <- res_t$aspecto; S$slope_terr[ii] <- res_t$slope_terr
  saveRDS(res_t, f_ck)
  log_msg("tesela %d/%d %s: %d muestras, NoData %d (%s)", n_done, length(tiles_uso), tn,
          length(ii), sum(is.na(res_t$z)), format(round(Sys.time() - t0, 1)))
  rm(rm_, te, res_t); gc(verbose = FALSE)
}

# ---- perfil y métricas por tramo ---------------------------------------------
suavizar <- function(z, w = VENTANA_SUAVIZADO) {
  n <- length(z); h <- w %/% 2
  vapply(seq_len(n), function(i) mean(z[max(1, i - h):min(n, i + h)]), numeric(1))
}
calc_tramo <- function(s) {
  out <- list(cota_min = NA_real_, cota_max = NA_real_, cota_media = NA_real_,
              cota_culminante = NA_real_, pendiente_media = NA_real_, pendiente_max = NA_real_,
              orientacion_ladera = NA_character_, sinuosidad = NA_real_,
              desnivel_subida_m = NA_real_, desnivel_bajada_m = NA_real_,
              cruza_portezuelo = NA, clase_kapos = NA_integer_,
              k_max = NA_integer_, n_na = sum(is.na(s$z)), n = nrow(s))
  if (out$n_na > 0 || out$n < 2) return(out)
  z <- s$z; d <- s$d
  out$cota_min <- min(z); out$cota_max <- max(z); out$cota_media <- mean(z)
  out$k_max <- which.max(z)
  zs <- suavizar(z)
  dz <- diff(zs); dd <- diff(d); dd[dd <= 0] <- NA
  pend_seg <- atan(dz / dd) * 180 / pi; ok <- !is.na(pend_seg)
  out$pendiente_media <- sum(abs(pend_seg[ok]) * dd[ok]) / sum(dd[ok])
  out$pendiente_max   <- max(abs(pend_seg[ok]))
  out$desnivel_subida_m <- sum(dz[dz > 0]); out$desnivel_bajada_m <- sum(-dz[dz < 0])
  n <- length(zs); out$cruza_portezuelo <- FALSE; out$cota_culminante <- out$cota_max
  if (n >= 3) {
    im <- which(zs[2:(n - 1)] > zs[1:(n - 2)] & zs[2:(n - 1)] >= zs[3:n]) + 1
    if (length(im)) {
      desc_izq <- vapply(im, function(i) zs[i] - min(zs[1:i]), numeric(1))
      desc_der <- vapply(im, function(i) zs[i] - min(zs[i:n]), numeric(1))
      prom <- pmin(desc_izq, desc_der)
      out$cruza_portezuelo <- any(desc_izq > UMBRAL_PORTEZUELO & desc_der > UMBRAL_PORTEZUELO)
      out$cota_culminante  <- min(z[im[which.max(prom)]], out$cota_max)
    }
  }
  a <- s$aspecto[!is.na(s$aspecto) & !is.na(s$slope_terr) & s$slope_terr > 0]
  if (length(a)) { tb <- table(rumbo8(a)); out$orientacion_ladera <- names(tb)[which.max(tb)] }
  if (s$dist_extremos[1] >= 1) out$sinuosidad <- s$L[1] / s$dist_extremos[1]
  out
}
kapos <- function(E, Sl, R) {
  if (is.na(E)) return(NA_integer_)
  if (E > 4500) return(1L); if (E > 3500) return(2L); if (E > 2500) return(3L)
  if (E > 1500) return(if (!is.na(Sl) && Sl >= 2) 4L else 0L)
  if (E > 1000) return(if ((!is.na(Sl) && Sl >= 5) || (!is.na(R) && R > 300)) 5L else 0L)
  if (E >= 300) return(if (!is.na(R) && R > 300) 6L else 0L)
  0L
}

f_R <- file.path(ckpt, "rango_kapos.rds")
R_cache <- if (file.exists(f_R)) readRDS(f_R) else list()
res_l <- vector("list", n_tr); names(res_l) <- tr$id_tramo
Sg <- split(S, S$id_tramo); t0 <- Sys.time(); n_R <- 0
for (i in seq_len(n_tr)) {
  id <- tr$id_tramo[i]; s <- Sg[[id]]
  if (is.null(s)) { res_l[[i]] <- calc_tramo(S[0, ]); next }
  o <- calc_tramo(s)
  if (!is.na(o$k_max)) {
    km <- o$k_max; Sl <- s$slope_terr[km]; R <- NA_real_
    if (o$cota_max >= 300 && o$cota_max <= 1500) {
      if (!is.null(R_cache[[id]])) R <- R_cache[[id]] else {
        R <- tryCatch(rango_local(s$lon[km], s$lat[km]),
                      error = function(e) { log_msg("ERROR rango_local %s: %s", id, conditionMessage(e)); NA_real_ })
        R_cache[[id]] <- R; n_R <- n_R + 1
        if (n_R %% 500 == 0) {
          saveRDS(R_cache, f_R)
          log_msg("rango Kapos: %d calculados (%s)", n_R, format(round(Sys.time() - t0, 1)))
        }
      }
      if (is.na(R)) add_pend(id, "clase_kapos", "rango altitudinal local (7 km) no disponible")
    }
    if (o$cota_max > 1000 && o$cota_max <= 2500 && is.na(Sl))
      add_pend(id, "clase_kapos", "pendiente de terreno no disponible en la celda de cota_max")
    o$clase_kapos <- kapos(o$cota_max, Sl, R)
    if (is.na(o$orientacion_ladera))
      add_pend(id, "orientacion_ladera", "todas las celdas bajo la traza son planas (aspecto indefinido)")
    if (is.na(o$sinuosidad))
      add_pend(id, "sinuosidad", "extremos coincidentes (< 1 m); distancia entre extremos nula")
  } else if (!id %in% sin_geom) {
    add_pend(id, "*", sprintf("DEM NoData en %d de %d muestras (tesela faltante o NoData)", o$n_na, o$n))
  }
  res_l[[i]] <- o
  if (i %% 2000 == 0) log_msg("métricas %d/%d (%s)", i, n_tr, format(round(Sys.time() - t0, 1)))
}
saveRDS(R_cache, f_R)
A3 <- bind_rows(lapply(res_l, function(o)
  as.data.frame(o[setdiff(names(o), c("k_max", "n_na", "n"))], stringsAsFactors = FALSE)))
A3 <- bind_cols(data.frame(id_tramo = tr$id_tramo, stringsAsFactors = FALSE), A3)

# ---- contraste Z de FT-01 ----------------------------------------------------
z_cero <- is.na(z_max_mop) | z_max_mop == 0
A3$cota_max_z_mop <- ifelse(z_cero, NA_real_, z_max_mop)
A3$delta_z_m <- A3$cota_max - A3$cota_max_z_mop
for (i in which(z_cero)) {
  mot <- if (is.na(z_max_mop[i])) "z_mop_cero (geometría sin Z)" else "z_mop_cero"
  add_pend(tr$id_tramo[i], "cota_max_z_mop", mot); add_pend(tr$id_tramo[i], "delta_z_m", mot)
}
for (i in which(!z_cero & is.na(A3$cota_max))) add_pend(tr$id_tramo[i], "delta_z_m", "cota_max NULL (DEM NoData)")
if (all(z_cero)) log_msg("HALLAZGO: Z de FT-01 cero/ausente en TODAS las filas")
add_pend("*", "clase_kapos",
         "clase 7 (cuencas interiores aisladas) no derivable con la regla de umbrales; un 0 puede encubrir clase 7")

cols_a3 <- c("cota_min", "cota_max", "cota_media", "cota_culminante", "pendiente_media",
             "pendiente_max", "orientacion_ladera", "sinuosidad", "desnivel_subida_m",
             "desnivel_bajada_m", "cruza_portezuelo", "clase_kapos", "cota_max_z_mop", "delta_z_m")
A3 <- A3[, c("id_tramo", cols_a3)]
A3$clase_kapos <- as.integer(A3$clase_kapos); A3$cruza_portezuelo <- as.logical(A3$cruza_portezuelo)

# ---- procedencia (formato largo) --------------------------------------------
fuente_de <- c(setNames(rep("FT-07", 11), cols_a3[1:11]), clase_kapos = "FT-07;FT-09",
               cota_max_z_mop = "FT-07;FT-01", delta_z_m = "FT-07;FT-01")
fecha_de  <- c(setNames(rep(fecha_hoy, 12), cols_a3[1:12]), cota_max_z_mop = fecha_ft01, delta_z_m = fecha_ft01)
proc <- bind_rows(lapply(cols_a3, function(cn) {
  ok <- !is.na(A3[[cn]]); if (!any(ok)) return(NULL)
  data.frame(id_tramo = A3$id_tramo[ok], campo = cn, fuente = unname(fuente_de[cn]),
             fecha_descarga = unname(fecha_de[cn]), metodo = "derivado", agente = AGENTE,
             stringsAsFactors = FALSE)
}))
pend_df <- if (length(pend)) distinct(bind_rows(pend)) else
  data.frame(id_tramo = character(), campo = character(), motivo = character(),
             agente = character(), fecha = character())

# ---- aserciones mínimas antes de escribir ------------------------------------
stopifnot(nrow(A3) == n_tr, identical(names(A3), c("id_tramo", cols_a3)))
stopifnot(all(A3$cota_min <= A3$cota_media & A3$cota_media <= A3$cota_max, na.rm = TRUE))
stopifnot(all(A3$cota_culminante <= A3$cota_max + 0.01, na.rm = TRUE))
stopifnot(all(A3$pendiente_max >= A3$pendiente_media, na.rm = TRUE))
stopifnot(all(A3$sinuosidad >= 1 - 1e-6, na.rm = TRUE))
stopifnot(nrow(proc) == sum(!is.na(as.matrix(A3[, cols_a3]))))

write_parquet(A3, file.path(dir_out, "a3_altimetria.parquet"))
write_parquet(proc, file.path(dir_out, "procedencia_a3.parquet"))
write.csv(pend_df, file.path(dir_out, "vacios_a3.csv"), row.names = FALSE, na = "", fileEncoding = "UTF-8")

# ---- resumen -----------------------------------------------------------------
log_msg("escrito %s (%d filas)", file.path(dir_out, "a3_altimetria.parquet"), nrow(A3))
nulls <- colSums(is.na(A3[, cols_a3]))
log_msg("NULL por columna: %s", paste(names(nulls), nulls, sep = "=", collapse = " "))
tk <- table(A3$clase_kapos, useNA = "ifany")
log_msg("clase_kapos: %s", paste(names(tk), tk, sep = "=", collapse = " "))
log_msg("cruza_portezuelo TRUE: %d", sum(A3$cruza_portezuelo, na.rm = TRUE))
dz <- A3$delta_z_m[!is.na(A3$delta_z_m)]
if (length(dz)) log_msg("delta_z_m: n=%d mediana=%.1f p95=%.1f |delta|>50: %d",
                        length(dz), median(dz), quantile(dz, .95), sum(abs(dz) > 50))
log_msg("procedencia: %d filas; vacíos: %d filas", nrow(proc), nrow(pend_df))
log_msg("==== A3 fin | tiempo total %s", format(round(Sys.time() - T_INI, 1)))
