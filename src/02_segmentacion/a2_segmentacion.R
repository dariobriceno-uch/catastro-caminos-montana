# =============================================================================
# A2 — Validación y subdivisión de tramos.
# Lee data/interim/a1_red_vial.gpkg (capa `tramos`) y escribe:
#   data/interim/a2_tramos.gpkg (capa `tramos`)
#   data/interim/procedencia_a2.parquet
#   data/interim/pendientes_a2.csv
#   logs/a2_segmentacion.log
#
# Re-ejecutable desde la raíz:  Rscript src/02_segmentacion/a2_segmentacion.R
# No modifica nada en data/raw/ ni en a1_red_vial.gpkg.
#
# ---------------------------------------------------------------------------
# DECISIONES DE MÉTODO (documentación obligatoria)
# ---------------------------------------------------------------------------
# 1. UNIDADES DE km_tramo. A1 reporta que KM_I/KM_F/KM_TRAMO vienen en METROS
#    (literal de la capa FT-01). Se verificó empíricamente: la razón
#    longitud_calc_m / km_tramo tiene mediana 0,999 en una muestra de 2.000
#    tramos. Por lo tanto:
#        delta_longitud_pct = 100 * (longitud_calc_m - km_tramo) / km_tramo
#    con km_tramo tal cual (metros). No se multiplica por 1.000.
#    Si km_tramo == 0 (1.622 tramos en A1) el delta es indefinido → NULL +
#    pendiente con motivo `km_tramo_cero_en_A1`.
#
# 2. ZONA UTM. utm_zona = 18 si la longitud del centroide del tramo (EPSG:4326,
#    centroide planar) es < -72°, y 19 si es >= -72°. El meridiano central de la
#    zona 18S es -75° y el de la 19S es -69°; -72° es el límite teórico entre
#    ambas. Se usa el centroide y no los extremos para que el tramo completo
#    tenga una sola zona. Toda longitud se calcula en EPSG:32700 + utm_zona.
#
# 3. CORTE POR COMUNA. Única regla de corte activa en fase 1. Se usa
#    exclusivamente data/raw/ine/comunas_2017.geojson (FT-05, 345 polígonos,
#    descargado por A4 y registrado en data/raw/manifest/A4.json). A2 NO escribe
#    la columna `comuna` (pertenece a A4); solo usa los polígonos para cortar.
#    - `cambio_carpeta` NO aplica: cada tramo de FT-01 ya trae una sola
#      carpeta (la capa está segmentada por carpeta), no hay dónde cortar.
#    - `punto_control` NO aplica en fase 1: no hay fuente de puntos de control
#      descargada en data/raw/. Queda documentado para fases posteriores.
#    Ambos valores existen en el dominio pero no se emiten.
#
# 4. GEOMETRÍA DE LOS HIJOS Y CONSERVACIÓN DE Z. sf::st_intersection (GEOS)
#    devuelve geometrías XY: pierde la Z de FT-01. Por eso la intersección con
#    las comunas se usa SOLO para localizar los puntos de corte (extremos de
#    los pedazos). Cada punto de corte se proyecta sobre el padre en UTM
#    (segmento i, fracción t, medida m en metros) y los hijos se construyen
#    rebanando el arreglo XYZ ORIGINAL en EPSG:4326: los vértices interiores se
#    copian exactos y los dos extremos nuevos se interpolan linealmente en X, Y
#    y Z sobre el segmento cortado. Así los hijos particionan exactamente al
#    padre, conservan Z y no sufren redondeo por reproyección.
#    La intersección se calcula en EPSG:4326 con s2 apagado (planar): la
#    partición topológica es la misma que en UTM y evita reproyectar comunas.
#
# 5. RESIDUOS. Un pedazo de menos de 20 m producto de la tolerancia de los
#    límites comunales (líneas que rozan un límite, vértices sobre el borde) no
#    constituye un tramo. Umbral UMBRAL_RESIDUAL_M = 20. Los cortes que generan
#    un pedazo < 20 m se eliminan uno a uno (el pedazo se funde con su vecino
#    contiguo: el anterior en el recorrido, o el siguiente si es el primero),
#    de modo que no se pierde longitud. Si tras la fusión queda un solo pedazo,
#    el tramo no se subdivide (motivo_corte = original). El conteo de residuos
#    fundidos se registra en el log y en el reporte.
#
# 6. NUMERACIÓN. Hijos = <id_tramo_a1>-<k>, k = 1..n en orden de recorrido
#    desde el primer vértice de la línea (medida creciente sobre el padre).
#    Cada hijo es un pedazo contiguo; si un tramo entra dos veces en la misma
#    comuna produce dos hijos distintos.
#
# 7. TRAMOS SIN COMUNA. Tramos que no intersectan ningún polígono comunal
#    (mar, borde) no se cortan, motivo_corte = original, y se registran en
#    pendientes con motivo `fuera_de_comunas` (campo motivo_corte).
#
# 8. PADRES MULTIPARTE. 5 padres son MULTILINESTRING reales. El referenciamiento
#    lineal recorre las partes en orden y no interpola entre partes distintas;
#    un hijo que abarca más de una parte sale como MULTILINESTRING Z.
#
# 9. SALIDA. Capa homogénea MULTILINESTRING Z en EPSG:4326 (los hijos de una
#    parte se promueven a multiparte para no mezclar tipos en el gpkg).
#    coord_inicio / coord_fin: WKT `POINT(lon lat)` del primer y último vértice.
# =============================================================================

suppressPackageStartupMessages({
  library(sf); library(dplyr); library(arrow); library(jsonlite)
})
options(warn = 1, stringsAsFactors = FALSE)
sf_use_s2(FALSE)
T0 <- Sys.time()

if (!file.exists("REGLAS.md")) stop("Ejecutar desde la raíz del repositorio")
ROOT    <- normalizePath(".", winslash = "/")
IN_GPKG <- file.path(ROOT, "data/interim/a1_red_vial.gpkg")
COMUNAS <- file.path(ROOT, "data/raw/ine/comunas_2017.geojson")
MAN_A1  <- file.path(ROOT, "data/raw/manifest/A1.json")
MAN_A4  <- file.path(ROOT, "data/raw/manifest/A4.json")
OUT_GPKG <- file.path(ROOT, "data/interim/a2_tramos.gpkg")
OUT_PROC <- file.path(ROOT, "data/interim/procedencia_a2.parquet")
OUT_PEND <- file.path(ROOT, "data/interim/pendientes_a2.csv")
LOG_DIR  <- file.path(ROOT, "logs"); dir.create(LOG_DIR, showWarnings = FALSE, recursive = TRUE)
LOG      <- file.path(LOG_DIR, "a2_segmentacion.log")

AGENTE <- "A2"
UMBRAL_RESIDUAL_M <- 20      # ver decisión 5
LON_LIMITE_ZONA   <- -72     # ver decisión 2
TOL_DEDUP_M       <- 0.01    # dos cortes a < 1 cm son el mismo corte
COLS_A2 <- c("longitud_calc_m", "delta_longitud_pct", "coord_inicio", "coord_fin",
             "subdividido", "motivo_corte", "utm_zona")

cat("", file = LOG)
log_line <- function(...) {
  msg <- paste0(format(Sys.time(), "%Y-%m-%d %H:%M:%S", tz = "UTC"), " UTC | ", paste0(..., collapse = ""))
  cat(msg, "\n"); con <- file(LOG, open = "ab"); writeBin(charToRaw(enc2utf8(paste0(msg, "\n"))), con); close(con)
}
log_line("Inicio A2")

# ---- fechas de descarga desde los manifests ---------------------------------
man_a1 <- fromJSON(MAN_A1, simplifyVector = TRUE)
ts_a1  <- man_a1$timestamp_utc[man_a1$fuente == "FT-01"]
FECHA_FT01 <- substr(min(ts_a1), 1, 10)
man_a4 <- fromJSON(MAN_A4, simplifyVector = TRUE)
ent_com <- man_a4[grepl("comunas_2017[.]geojson$", man_a4$archivo), ]
if (nrow(ent_com) != 1) stop("A4.json no tiene exactamente una entrada para comunas_2017.geojson")
if (ent_com$fuente != "FT-05") stop("comunas_2017.geojson no está registrado como FT-05")
FECHA_FT05 <- substr(ent_com$timestamp_utc, 1, 10)
if (!grepl("^\\d{4}-\\d{2}-\\d{2}$", FECHA_FT01) || !grepl("^\\d{4}-\\d{2}-\\d{2}$", FECHA_FT05))
  stop("fecha de descarga no parseable en manifest")
log_line("fecha FT-01 = ", FECHA_FT01, " | fecha FT-05 = ", FECHA_FT05,
         " | sha256 comunas (manifest) = ", ent_com$sha256)
# comprobación de integridad del insumo de corte contra su manifest
if (requireNamespace("digest", quietly = TRUE)) {
  sha_now <- digest::digest(COMUNAS, algo = "sha256", file = TRUE)
  if (!identical(sha_now, ent_com$sha256)) stop("sha256 de comunas_2017.geojson no coincide con A4.json")
  log_line("sha256 de comunas_2017.geojson verificado contra manifest")
}

# ---- entrada ----------------------------------------------------------------
a1 <- st_read(IN_GPKG, layer = "tramos", quiet = TRUE)
if (st_crs(a1)$epsg != 4326) stop("a1_red_vial.gpkg no está en EPSG:4326")
if (anyDuplicated(a1$id_tramo_a1)) stop("id_tramo_a1 duplicado en A1")
GEOM_COL <- attr(a1, "sf_column")
N_IN <- nrow(a1)
log_line("A1: ", N_IN, " tramos, geometría ", class(st_geometry(a1))[1], ", Z presente = ",
         all(grepl("Z", vapply(st_geometry(a1)[1:min(50, N_IN)], function(g) class(g)[1], character(1)))))

com <- st_read(COMUNAS, quiet = TRUE)
if (nrow(com) != 345) stop("comunas_2017.geojson: se esperaban 345 polígonos, hay ", nrow(com))
com <- st_transform(com, 4326)
com_geom <- st_geometry(com)
log_line("Comunas: ", nrow(com), " polígonos; válidos = ", sum(st_is_valid(com_geom)))

# ---- utm_zona ---------------------------------------------------------------
cen <- suppressWarnings(st_coordinates(st_centroid(st_geometry(a1))))
a1$utm_zona <- ifelse(cen[, "X"] < LON_LIMITE_ZONA, 18L, 19L)
log_line("utm_zona: 18 = ", sum(a1$utm_zona == 18L), " | 19 = ", sum(a1$utm_zona == 19L))
epsg_utm <- function(z) 32700L + as.integer(z)

# ---- longitud del padre en su UTM (sin reproyectar toda la capa a una zona) --
len_padre <- numeric(N_IN)
for (z in c(18L, 19L)) {
  i <- which(a1$utm_zona == z)
  if (length(i)) len_padre[i] <- as.numeric(st_length(st_transform(st_geometry(a1)[i], epsg_utm(z))))
}
log_line("longitud padre calculada; min = ", round(min(len_padre), 2), " m, max = ", round(max(len_padre)), " m")

# ---- cruce con comunas: candidatos a corte ----------------------------------
ix <- suppressMessages(st_intersects(st_geometry(a1), com_geom))
n_com <- lengths(ix)
log_line("tramos por n° de comunas intersectadas: 0 = ", sum(n_com == 0), " | 1 = ", sum(n_com == 1),
         " | >=2 = ", sum(n_com >= 2))

# =============================================================================
# Referenciamiento lineal (sin lwgeom)
# =============================================================================
# Localiza el punto P (x,y) sobre la polilínea (cx,cy,part): segmento i,
# fracción t en [0,1], distancia d. No se consideran segmentos entre partes.
seg_locate <- function(px, py, cx, cy, part) {
  n <- length(cx)
  ax <- cx[-n]; ay <- cy[-n]; bx <- cx[-1]; by <- cy[-1]
  ok <- part[-n] == part[-1]
  dx <- bx - ax; dy <- by - ay; l2 <- dx * dx + dy * dy
  t <- ((px - ax) * dx + (py - ay) * dy) / pmax(l2, 1e-300)
  t <- pmin(pmax(t, 0), 1)
  d2 <- (px - (ax + t * dx))^2 + (py - (ay + t * dy))^2
  d2[!ok | l2 == 0] <- Inf
  i <- which.min(d2)
  list(i = i, t = t[i], d = sqrt(d2[i]))
}

# Construye la geometría (sfg XYZ, EPSG:4326) del pedazo entre los cortes
# c0 = (i0,t0) y c1 = (i1,t1) sobre el arreglo original xyz (con parte L1).
slice_xyz <- function(xyz, part, c0, c1) {
  interp <- function(i, t) xyz[i, ] + t * (xyz[i + 1, ] - xyz[i, ])
  p_ini <- interp(c0$i, c0$t); p_fin <- interp(c1$i, c1$t)
  # vértices originales interiores (i0+1 .. i1); ninguno si ambos cortes caen en el mismo segmento
  j <- if (c0$i + 1 <= c1$i) seq.int(c0$i + 1, c1$i) else integer(0)
  pts   <- rbind(p_ini, xyz[j, , drop = FALSE], p_fin)
  parts <- c(part[c0$i], part[j], part[c1$i])
  # dedup de puntos consecutivos idénticos en XY (cuando t0 == 1 o t1 == 0)
  keep <- c(TRUE, !(abs(diff(pts[, 1])) == 0 & abs(diff(pts[, 2])) == 0))
  pts <- pts[keep, , drop = FALSE]; parts <- parts[keep]
  out <- list()
  for (p in unique(parts)) {
    m <- pts[parts == p, , drop = FALSE]
    if (nrow(m) >= 2) out[[length(out) + 1]] <- m
  }
  if (length(out) == 0) return(NULL)
  st_multilinestring(out, dim = "XYZ")
}

# Devuelve lista de sfg hijos (ordenados) o NULL si no hay subdivisión.
cortar_tramo <- function(k) {
  g4326 <- st_geometry(a1)[k]
  z <- a1$utm_zona[k]
  xyz  <- st_coordinates(g4326)                       # X Y Z L1 L2
  part <- xyz[, "L1"]; xyz <- xyz[, c("X", "Y", "Z"), drop = FALSE]
  gutm <- st_transform(g4326, epsg_utm(z))
  cu   <- st_coordinates(gutm)[, c("X", "Y"), drop = FALSE]
  n <- nrow(cu)
  seglen <- sqrt(diff(cu[, 1])^2 + diff(cu[, 2])^2)
  seglen[part[-n] != part[-1]] <- 0                   # no hay longitud entre partes
  cum <- c(0, cumsum(seglen)); L <- cum[n]
  # pedazos XY por comuna candidata (solo para ubicar los cortes)
  g_xy <- st_zm(g4326)
  cortes <- list(list(i = 1L, t = 0, m = 0), list(i = n - 1L, t = 1, m = L))
  d_max <- 0
  for (cidx in ix[[k]]) {
    pz <- suppressWarnings(suppressMessages(st_intersection(g_xy, com_geom[cidx])))
    if (length(pz) == 0 || all(st_is_empty(pz))) next
    tp <- as.character(st_geometry_type(pz))
    if (tp == "GEOMETRYCOLLECTION") {
      pz <- tryCatch(st_collection_extract(pz, "LINESTRING"), error = function(e) NULL, warning = function(w) NULL)
      if (is.null(pz) || length(pz) == 0) next
    } else if (!tp %in% c("LINESTRING", "MULTILINESTRING")) next
    pz <- st_cast(st_cast(pz, "MULTILINESTRING"), "LINESTRING")
    if (length(pz) == 0) next
    pc <- st_coordinates(pz)                            # X Y L1
    ends <- pc[c(match(unique(pc[, "L1"]), pc[, "L1"]), nrow(pc) + 1 - match(unique(pc[, "L1"]), rev(pc[, "L1"]))), , drop = FALSE]
    eu <- st_coordinates(st_transform(st_sfc(lapply(seq_len(nrow(ends)), function(r) st_point(ends[r, 1:2])), crs = 4326), epsg_utm(z)))
    for (r in seq_len(nrow(eu))) {
      loc <- seg_locate(eu[r, 1], eu[r, 2], cu[, 1], cu[, 2], part)
      d_max <- max(d_max, loc$d)
      loc$m <- cum[loc$i] + loc$t * seglen[loc$i]
      cortes[[length(cortes) + 1]] <- loc
    }
  }
  m <- vapply(cortes, `[[`, numeric(1), "m")
  o <- order(m); cortes <- cortes[o]; m <- m[o]
  # dedup: cortes a menos de TOL_DEDUP_M se consideran el mismo
  # (se conservan siempre el primero y el último; un corte interior se conserva
  #  solo si dista más de TOL del último conservado y del extremo final)
  keep <- rep(FALSE, length(m)); keep[1] <- TRUE; last <- m[1]
  for (q in seq_len(length(m))[-1]) {
    if (q == length(m)) { keep[q] <- TRUE; break }
    if (m[q] - last > TOL_DEDUP_M && m[length(m)] - m[q] > TOL_DEDUP_M) { keep[q] <- TRUE; last <- m[q] }
  }
  cortes <- cortes[keep]; m <- m[keep]
  n_res <- 0L
  # fusión de residuos < UMBRAL_RESIDUAL_M con el vecino contiguo
  repeat {
    if (length(m) <= 2) break
    seg <- diff(m)
    if (all(seg >= UMBRAL_RESIDUAL_M)) break
    s <- which.min(seg)                                 # pedazo s va de corte s a s+1
    drop <- if (s == 1) 2L else s                       # primero: se funde con el siguiente; otro: con el anterior
    cortes <- cortes[-drop]; m <- m[-drop]; n_res <- n_res + 1L
  }
  if (length(m) <= 2) return(list(hijos = NULL, n_res = n_res, d_max = d_max))
  hijos <- vector("list", length(m) - 1)
  for (h in seq_along(hijos)) hijos[[h]] <- slice_xyz(xyz, part, cortes[[h]], cortes[[h + 1]])
  if (any(vapply(hijos, is.null, logical(1)))) stop("hijo vacío en ", a1$id_tramo_a1[k])
  list(hijos = hijos, n_res = n_res, d_max = d_max)
}

# ---- ejecución del corte ----------------------------------------------------
cand <- which(n_com >= 2)
log_line("candidatos a corte (>= 2 comunas): ", length(cand))
res_hijos <- list(); n_res_total <- 0L; d_max_global <- 0; n_sub <- 0L
t1 <- Sys.time()
for (jj in seq_along(cand)) {
  k <- cand[jj]
  r <- cortar_tramo(k)
  n_res_total <- n_res_total + r$n_res; d_max_global <- max(d_max_global, r$d_max)
  if (!is.null(r$hijos)) { res_hijos[[a1$id_tramo_a1[k]]] <- r$hijos; n_sub <- n_sub + 1L }
  if (jj %% 200 == 0) log_line("  corte ", jj, "/", length(cand), " (", n_sub, " subdivididos)")
}
log_line("corte terminado en ", round(as.numeric(difftime(Sys.time(), t1, units = "secs"))), " s | subdivididos = ",
         n_sub, " | candidatos no subdivididos tras fusión = ", length(cand) - n_sub,
         " | residuos < ", UMBRAL_RESIDUAL_M, " m fundidos = ", n_res_total,
         " | distancia máx. punto de corte a la línea = ", signif(d_max_global, 3), " m")

# ---- tabla de salida --------------------------------------------------------
a1df <- st_drop_geometry(a1)
cols_a1 <- setdiff(names(a1df), "utm_zona")

filas <- vector("list", N_IN); geoms <- vector("list", N_IN)
for (k in seq_len(N_IN)) {
  id <- a1$id_tramo_a1[k]
  base <- a1df[k, cols_a1, drop = FALSE]
  if (!is.null(res_hijos[[id]])) {
    hs <- res_hijos[[id]]
    df <- base[rep(1, length(hs)), , drop = FALSE]
    df$id_tramo <- paste0(id, "-", seq_along(hs))
    df$subdividido <- TRUE; df$motivo_corte <- "cambio_comuna"
    filas[[k]] <- df; geoms[[k]] <- hs
  } else {
    df <- base; df$id_tramo <- id
    df$subdividido <- FALSE; df$motivo_corte <- "original"
    filas[[k]] <- df; geoms[[k]] <- list(st_geometry(a1)[[k]])
  }
}
out <- bind_rows(filas)
gs  <- st_sfc(do.call(c, geoms), crs = 4326)
gs  <- st_cast(gs, "MULTILINESTRING")
out$utm_zona <- a1$utm_zona[match(out$id_tramo_a1, a1$id_tramo_a1)]

# longitud calculada por zona, sin reproyectar toda la capa a una sola zona
out$longitud_calc_m <- NA_real_
for (z in c(18L, 19L)) {
  i <- which(out$utm_zona == z)
  if (length(i)) out$longitud_calc_m[i] <- as.numeric(st_length(st_transform(gs[i], epsg_utm(z))))
}

# delta contra km_tramo EN METROS (decisión 1); hijos → NULL
km <- as.numeric(out$km_tramo)
out$delta_longitud_pct <- ifelse(!out$subdividido & !is.na(km) & km > 0,
                                 100 * (out$longitud_calc_m - km) / km, NA_real_)

# coordenadas de inicio y fin (primer / último vértice), WKT POINT(lon lat)
cc <- st_coordinates(gs)
first_i <- match(seq_len(nrow(out)), cc[, "L2"])
last_i  <- nrow(cc) + 1 - match(seq_len(nrow(out)), rev(cc[, "L2"]))
wkt_pt <- function(x, y) sprintf("POINT(%s %s)", formatC(x, digits = 15, format = "g"), formatC(y, digits = 15, format = "g"))
out$coord_inicio <- wkt_pt(cc[first_i, "X"], cc[first_i, "Y"])
out$coord_fin    <- wkt_pt(cc[last_i, "X"],  cc[last_i, "Y"])

# orden de columnas: A1 + llaves + bloque A2
out <- out[, c("id_tramo", "id_tramo_a1", setdiff(cols_a1, "id_tramo_a1"), COLS_A2)]
out_sf <- st_sf(out, geom = gs)

# ---- verificaciones internas -------------------------------------------------
stopifnot(!anyDuplicated(out$id_tramo), all(a1$id_tramo_a1 %in% out$id_tramo_a1),
          all(out$longitud_calc_m > 0), all(out$motivo_corte %in% c("original", "cambio_comuna")))
# Σ hijos ≈ padre ±1 %
if (n_sub > 0) {
  sh <- out %>% filter(subdividido) %>% group_by(id_tramo_a1) %>%
    summarise(suma = sum(longitud_calc_m), n = n(), .groups = "drop")
  sh$padre <- len_padre[match(sh$id_tramo_a1, a1$id_tramo_a1)]
  sh$d <- abs(sh$suma - sh$padre) / sh$padre
  log_line("Σ hijos vs padre: max |delta| = ", signif(max(sh$d) * 100, 3), "% | padres con |delta| > 1 % = ", sum(sh$d > 0.01))
  if (any(sh$d > 0.01)) stop("Σ hijos difiere del padre en más de 1 %: ", paste(head(sh$id_tramo_a1[sh$d > 0.01]), collapse = ", "))
  log_line("hijos por padre: ", paste(names(table(sh$n)), "hijos=", table(sh$n), collapse = " | "))
}
# Z conservada en todos los hijos
z_ok <- all(vapply(st_geometry(out_sf)[out$subdividido], function(g) grepl("Z", class(g)[1]), logical(1)))
log_line("Z conservada en hijos: ", z_ok); if (!z_ok) stop("hijos sin Z")

# ---- escritura --------------------------------------------------------------
if (file.exists(OUT_GPKG)) unlink(OUT_GPKG)
st_write(out_sf, OUT_GPKG, layer = "tramos", quiet = TRUE)
log_line("escrito ", OUT_GPKG, " (", nrow(out_sf), " filas)")

# ---- procedencia (formato largo, una fila por celda no nula) ----------------
proc <- list()
for (cc_ in COLS_A2) {
  v <- out[[cc_]]
  nn <- if (is.character(v)) !(is.na(v) | trimws(v) == "") else !is.na(v)
  if (!any(nn)) next
  if (cc_ %in% c("subdividido", "motivo_corte")) {
    fte <- ifelse(out$subdividido[nn], "FT-05", "FT-01")
    fch <- ifelse(out$subdividido[nn], FECHA_FT05, FECHA_FT01)
  } else { fte <- "FT-01"; fch <- FECHA_FT01 }
  proc[[cc_]] <- data.frame(id_tramo = out$id_tramo[nn], campo = cc_, fuente = fte,
                            fecha_descarga = fch, metodo = "derivado", agente = AGENTE)
}
proc <- bind_rows(proc)
proc <- proc[, c("id_tramo", "campo", "fuente", "fecha_descarga", "metodo", "agente")]
write_parquet(proc, OUT_PROC)
log_line("procedencia: ", nrow(proc), " filas")

# ---- pendientes -------------------------------------------------------------
HOY <- format(Sys.time(), "%Y-%m-%d", tz = "UTC")
pend <- list()
h <- out$subdividido
if (any(h)) pend[[1]] <- data.frame(id_tramo = out$id_tramo[h], campo = "delta_longitud_pct",
                                    motivo = "hijo_sin_km_oficial: km_tramo describe al padre, no existe kilometraje declarado del hijo")
z0 <- !out$subdividido & is.na(out$delta_longitud_pct)
if (any(z0)) pend[[2]] <- data.frame(id_tramo = out$id_tramo[z0], campo = "delta_longitud_pct",
                                     motivo = "km_tramo_cero_en_A1: km_tramo declarado = 0, delta indefinido")
fc <- which(n_com == 0)
if (length(fc)) pend[[3]] <- data.frame(id_tramo = a1$id_tramo_a1[fc], campo = "motivo_corte",
                                        motivo = "fuera_de_comunas: no intersecta ningún polígono de comunas_2017 (FT-05); no se cortó")
pend <- bind_rows(pend)
if (nrow(pend) == 0) pend <- data.frame(id_tramo = character(), campo = character(), motivo = character())
pend$agente <- AGENTE; pend$fecha <- HOY
pend <- pend[, c("id_tramo", "campo", "motivo", "agente", "fecha")]
con <- file(OUT_PEND, open = "wb"); write.csv(pend, con, row.names = FALSE, fileEncoding = "UTF-8"); close(con)
log_line("pendientes: ", nrow(pend), " filas (hijos sin km = ", sum(h), ", km_tramo=0 = ", sum(z0),
         ", fuera_de_comunas = ", length(fc), ")")

# ---- resumen ----------------------------------------------------------------
dl <- out$delta_longitud_pct[!is.na(out$delta_longitud_pct)]
log_line("RESUMEN | entrada ", N_IN, " | salida ", nrow(out), " | subdivididos ", n_sub, " padres → ", sum(h), " hijos",
         " | motivo_corte: ", paste(names(table(out$motivo_corte)), table(out$motivo_corte), collapse = ", "),
         " | utm_zona: 18=", sum(out$utm_zona == 18L), " 19=", sum(out$utm_zona == 19L),
         " | delta_longitud_pct (n=", length(dl), "): mediana ", signif(median(dl), 3), "%, p95 |delta| ",
         signif(quantile(abs(dl), .95), 3), "%, n |delta|>10% = ", sum(abs(dl) > 10),
         " | tiempo ", round(as.numeric(difftime(Sys.time(), T0, units = "mins")), 1), " min")
log_line("Fin A2")
