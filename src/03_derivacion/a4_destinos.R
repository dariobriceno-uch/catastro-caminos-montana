# =============================================================================
# A4 — Destinos y contexto
# Deriva el bloque A4 de docs/esquema.md a partir de data/interim/a2_tramos.gpkg
# y de los insumos crudos FT-03 (DIFROL), FT-05 (INE) y FT-06 (SERNATUR).
#
# Uso (desde la raíz del repositorio):
#   Rscript src/03_derivacion/a4_destinos.R [ruta_gpkg_tramos] [dir_salida]
#   por defecto: data/interim/a2_tramos.gpkg  ->  data/interim/
#
# Salidas:
#   <dir_salida>/a4_destinos.parquet    id_tramo + columnas del bloque A4
#   <dir_salida>/procedencia_a4.parquet formato largo
#   <dir_salida>/vacios_a4.csv
#
# Reglas: ningún valor se escribe si no proviene de un archivo en data/raw/.
# Cualquier celda no derivable va NULL y a vacíos.
#
# DECISIONES DEL ORQUESTADOR (2026-08-26)
# - buffer_join_m = 500 m para pasos, centros de esquí y localidades; su fuente
#   en procedencia es el literal "—".
# - "Localidad con servicios" = entidades INE Censo 2017 con CATEGORIA en
#   {CIUDAD, PUEBLO} (SERVICIOS_CATEGORIAS).
# - Centro de esquí (FT-06, SERNATUR atractivos turísticos): la capa no tiene
#   categoría propia. Criterio, solo por atributos de la fuente:
#     subtipo_at == "Area Nevada"  Y  nombre ~ /ski|esqu[ií]|invernal/ (sin
#     distinguir mayúsculas). Del subtipo (21 registros) quedan 18; se excluyen
#     por el regex Nevados del Sollipulli y Campos de Hielo Norte/Sur.
#   FT-06 no trae cota base -> esqui_cota_base es NULL en todas las filas.
# - es_paso NO se filtra por tipo de tráfico: todo paso dentro del buffer marca
#   TRUE y paso_trafico conserva el literal de la fuente.
# - en_zona_fronteriza: FT-03c entrega la línea interior de la zona (no un
#   polígono). El polígono se construye así, en EPSG:32719:
#     1. línea 'Chile continental' de zf_2024.shp, descartando partes < 1 km y
#        fusionando (st_line_merge) -> una línea abierta de ~8.440 km, extremos
#        N (-70,344°, -20,061°) y S (-66,078°, -55,183°);
#     2. límite internacional terrestre (pais_c ∈ Argentina/Bolivia/Perú). La
#        línea con Argentina viene en dos piezas: se agrega un SEGMENTO RECTO de
#        62,1 km entre (-73,087°, -49,284°) y (-73,450°, -49,789°) (sección sin
#        demarcar);
#     3. extremo S: toca el límite (distancia 0), no se agrega nada;
#        extremo N: está a 164 km del límite. Se agregan dos SEGMENTOS: desde
#        (-70,344°, -20,061°) 300 km hacia el oeste (misma coordenada Y en UTM
#        19S) y desde ese punto al punto más cercano del límite (tramo marítimo
#        del límite con Perú). Un cierre directo dejaba fuera el extremo norte
#        del país (7 pasos de Arica y Parinacota / Tarapacá);
#     4. st_node + st_polygonize + st_union -> 1 polígono de ~677.600 km².
#   Control derivado de datos: los 82 pasos de FT-03a caen dentro (tol. 50 m).
#   en_zona_fronteriza se evalúa sobre los EXTREMOS del tramo (TRUE si alguno
#   cae dentro), no sobre la traza completa, por costo del overlay con líneas
#   de hasta 286.000 vértices (decisión del orquestador, 2026-08-26).
#   Por incorporar geometría construida (no de la fuente), la columna lleva
#   metodo = "estimado" en procedencia. Las coordenadas exactas de cada segmento
#   añadido se imprimen en el log en cada ejecución.
# =============================================================================
suppressPackageStartupMessages({
  library(sf); library(dplyr); library(arrow); library(jsonlite)
})
sf_use_s2(FALSE)
options(warn = 1)

# ---------------------------------------------------------------- parámetros
args     <- commandArgs(trailingOnly = TRUE)
IN_GPKG  <- if (length(args) >= 1) args[1] else "data/interim/a2_tramos.gpkg"
OUT_DIR  <- if (length(args) >= 2) args[2] else "data/interim"
AGENTE   <- "A4"
FECHA_HOY <- format(Sys.Date(), "%Y-%m-%d")

# Radio de cruce (m). Propuesta: 500 m, coherente con la escala 1:50.000 de
# DIFROL (0,5 mm de plano = 25 m; se adopta un margen amplio por la
# incertidumbre del posicionamiento de pasos "Valor no oficial"). El
# orquestador puede cambiarlo; queda registrado en buffer_join_m.
BUFFER_JOIN_M <- 500L
# Esquí tiene buffer propio: FT-06 y FT-12 ubican el punto en el dominio
# esquiable (Villarrica a 2,1 km del S-887, Corralco a 755 m del R-785), no en
# el estacionamiento. 2.500 m recupera ambos; decisión 2026-08-27.
BUFFER_ESQUI_M <- 2500L
# Un centro de FT-12 (OSM) a menos de esta distancia de uno de FT-06 es el
# mismo centro: se conserva el oficial (SERNATUR).
DEDUP_ESQUI_M  <- 1500

# Criterio "localidad con servicios" (nivel 3 del criterio de inclusión).
# Se define SOLO por el atributo CATEGORIA de las capas INE Censo 2017:
# CIUDAD | PUEBLO | ALDEA | CASERÍO. Valor por defecto: entidades urbanas
# (CIUDAD, PUEBLO). El orquestador fija el criterio definitivo.
SERVICIOS_CATEGORIAS <- c("CIUDAD", "PUEBLO")

# Criterio "centro de esquí" en FT-06 (SERNATUR, atractivos turísticos).
# La capa no tiene categoría "centro de esquí"; el subtipo más cercano es
# 'Area Nevada' (21 registros) que además incluye campos de hielo y nevados.
# Se exige subtipo 'Area Nevada' Y nombre que contenga ski/esquí/invernal.
ESQUI_SUBTIPO       <- "Area Nevada"
ESQUI_NOMBRE_REGEX  <- "ski|esqu[ií]|invernal"

# Líneas del límite internacional que cuentan como frontera terrestre
# (atributo pais_c de FT-03b). Se excluyen 'Antártica' y 'Deslinde ZEE'.
LIMITE_PAISES <- c("Argentina", "Bolivia", "Perú")

# Zona fronteriza: FT-03c trae LÍNEAS (límite interior de la zona), no
# polígonos. Se construye el polígono cerrando cada extremo de la línea
# 'Chile continental' con el segmento más corto al límite internacional y
# polygonizando. Si CONSTRUIR_POLIGONO_ZF = FALSE, en_zona_fronteriza va NULL.
CONSTRUIR_POLIGONO_ZF <- TRUE
ZF_UBICACION          <- "Chile continental"

# ---------------------------------------------------------------- rutas raw
RAW <- list(
  pasos    = "data/raw/Pasos Fronterizos/Pasos fronterizos Descarga/pasos_fronterizos_19-02.shp",
  limite   = "data/raw/Límite internacional/V4_limite_Internacional_Recuadro_CHS/V4_limite_internacional_50k.shp",
  zf       = "data/raw/Zona fronteriza/ZF_limite_2024/zf_2024.shp",
  comunas  = "data/raw/ine/comunas_2017.geojson",
  provincias = "data/raw/ine/provincias_2017.geojson",
  ciudades = "data/raw/ine/ciudades_2017.zip",
  pueblos  = "data/raw/ine/pueblos_2017.zip",
  aldeas   = "data/raw/ine/aldeas_2017.zip",
  caserios = "data/raw/ine/caserios_2017.zip",
  sernatur = "data/raw/sernatur/atractivos-turisticos.gpkg",
  osm_esqui = list.files("data/raw/osm_esqui", pattern = "^osm_esqui_chile_.*[.]json$", full.names = TRUE)[1],
  manifest_osm = "data/raw/manifest/A4_osm.json",
  manifest = "data/raw/manifest/A4.json"
)
faltan <- RAW[!file.exists(unlist(RAW))]
if (length(faltan)) stop("Faltan insumos en data/raw/: ", paste(unlist(faltan), collapse = "; "))

# fechas de descarga por fuente, leídas del manifest (no se inventan)
man <- fromJSON(RAW$manifest, simplifyVector = TRUE)
fecha_fuente <- function(codigo) {
  ts <- man$timestamp_utc[man$fuente == codigo]
  d  <- unique(substr(ts, 1, 10))
  d  <- d[grepl("^\\d{4}-\\d{2}-\\d{2}$", d)]
  if (!length(d)) NA_character_ else max(d)
}
man_osm <- fromJSON(RAW$manifest_osm, simplifyVector = TRUE)
FECHAS <- c("FT-03a" = fecha_fuente("FT-03a"), "FT-03b" = fecha_fuente("FT-03b"),
            "FT-03c" = fecha_fuente("FT-03c"), "FT-05" = fecha_fuente("FT-05"),
            "FT-06" = fecha_fuente("FT-06"),
            "FT-12" = substr(man_osm$timestamp_utc[man_osm$fuente == "FT-12"][1], 1, 10))
FECHAS["FT-06;FT-12"] <- max(FECHAS[c("FT-06", "FT-12")], na.rm = TRUE)

# ---------------------------------------------------------------- tramos
tramos <- st_read(IN_GPKG, layer = "tramos", quiet = TRUE)
stopifnot(all(c("id_tramo", "utm_zona") %in% names(tramos)))
stopifnot(!any(duplicated(tramos$id_tramo)))
tramos <- st_zm(tramos, drop = TRUE, what = "ZM")
if (is.na(st_crs(tramos))) st_crs(tramos) <- 4326
tramos <- st_transform(tramos, 4326)
tramos <- tramos[, c("id_tramo", "utm_zona")]
tramos$utm_zona <- as.integer(tramos$utm_zona)
message("tramos: ", nrow(tramos), " | zonas UTM: ", paste(sort(unique(tramos$utm_zona)), collapse = ","))

# ---------------------------------------------------------------- insumos
shp_in_zip <- function(zip) {
  inner <- utils::unzip(zip, list = TRUE)$Name
  inner <- inner[grepl("[.]shp$", inner)][1]
  st_read(paste0("/vsizip/", zip, "/", inner), quiet = TRUE)
}
to4326 <- function(x) st_transform(x, 4326)

pasos   <- to4326(st_read(RAW$pasos, quiet = TRUE))
limite  <- to4326(st_read(RAW$limite, quiet = TRUE))
zf      <- to4326(st_read(RAW$zf, quiet = TRUE))
comunas <- to4326(st_read(RAW$comunas, quiet = TRUE)) |> st_make_valid()
provs   <- to4326(st_read(RAW$provincias, quiet = TRUE)) |> st_make_valid()
sern    <- to4326(st_read(RAW$sernatur, quiet = TRUE))

leer_loc <- function(zip, campo_nombre) {
  x <- shp_in_zip(zip) |> to4326() |> st_make_valid()
  tipo <- if ("TIPO" %in% names(x)) x$TIPO else NA_character_
  st_sf(nombre = x[[campo_nombre]], categoria = x$CATEGORIA, tipo = tipo,
        poblacion = x$TOT_PERSON, comuna_ine = x$NOM_COMUNA, geometry = st_geometry(x))
}
localidades <- rbind(
  leer_loc(RAW$ciudades, "URBANO"), leer_loc(RAW$pueblos, "URBANO"),
  leer_loc(RAW$aldeas,   "NOM_ENT"), leer_loc(RAW$caserios, "NOM_ENT"))
message("localidades INE: ", nrow(localidades), " | categorías: ",
        paste(names(table(localidades$categoria)), table(localidades$categoria), collapse = ", "))
servicios <- localidades[localidades$categoria %in% SERVICIOS_CATEGORIAS, ]
message("localidades con servicios (", paste(SERVICIOS_CATEGORIAS, collapse = "+"), "): ", nrow(servicios))

esqui06 <- sern[!is.na(sern$subtipo_at) & sern$subtipo_at == ESQUI_SUBTIPO &
                grepl(ESQUI_NOMBRE_REGEX, sern$nombre, ignore.case = TRUE), ]
esqui06 <- st_sf(nombre = esqui06$nombre, fuente = "FT-06", geometry = st_geometry(esqui06))
message("centros de esquí FT-06 (criterio atributos): ", nrow(esqui06))

# FT-12: OpenStreetMap. Nodos y áreas con landuse=winter_sports o sport=skiing
# y nombre. Las áreas vienen con su centroide ("center") desde Overpass.
osm <- fromJSON(RAW$osm_esqui, simplifyVector = FALSE)$elements
osm <- Filter(function(e) { t <- e$tags; !is.null(t$name) &&
  (identical(t$landuse, "winter_sports") || identical(t$sport, "skiing")) }, osm)
esqui12 <- st_sf(
  nombre = vapply(osm, function(e) e$tags$name, character(1)),
  fuente = "FT-12",
  geometry = st_sfc(lapply(osm, function(e) { c <- if (!is.null(e$center)) e$center else e
                                             st_point(c(c$lon, c$lat)) }), crs = 4326))
message("centros de esquí FT-12 (OSM): ", nrow(esqui12))
# el mismo centro en las dos fuentes: se queda el oficial
d12 <- st_distance(st_transform(esqui12, 32719), st_transform(esqui06, 32719))
dup <- apply(d12, 1, function(r) any(as.numeric(r) <= DEDUP_ESQUI_M))
message("centros OSM que duplican uno de SERNATUR (a <= ", DEDUP_ESQUI_M, " m): ", sum(dup),
        " -> se descartan; se agregan ", sum(!dup), ": ", paste(esqui12$nombre[!dup], collapse = " | "))
esqui <- rbind(esqui06, esqui12[!dup, ])
esqui$.idx <- seq_len(nrow(esqui))
esqui_matched <- rep(FALSE, nrow(esqui))   # se llena en el cruce; sirve para vacíos

limite_terr <- limite[limite$pais_c %in% LIMITE_PAISES, ]
limite_u    <- st_union(st_geometry(limite_terr))

# polígono de zona fronteriza
zf_pol <- NULL
if (CONSTRUIR_POLIGONO_ZF) {
  # Construcción (documentada, parametrizada):
  #  1. línea interior ZF 'Chile continental', descartando partes degeneradas (< 1 km);
  #  2. límite internacional terrestre; si viene en piezas separadas (hay una sección
  #     sin demarcar entre -49,28° y -49,79°), se une con el segmento recto entre
  #     extremos de piezas distintas más cercanos (< ZF_HUECO_MAX_M);
  #  3. cada extremo de la línea ZF que no toque el límite (> 1 km) se cierra por mar:
  #     ZF_OFFSET_MAR_M hacia el oeste y desde ahí al punto más cercano del límite
  #     (el límite con Perú incluye un tramo marítimo); el cierre directo cortaba el
  #     extremo norte del país;
  #  4. polygonize + unión. Control de completitud: todos los pasos de FT-03a deben
  #     caer dentro del polígono (con tolerancia de 50 m). Se informa en el log.
  CRS_ZF <- 32719L; ZF_HUECO_MAX_M <- 100000; ZF_OFFSET_MAR_M <- 300000
  crs_zf <- st_crs(CRS_ZF)
  endpts <- function(ls) do.call(c, lapply(seq_along(ls), function(i) {
    cc <- st_coordinates(ls[i])[, 1:2]; st_sfc(st_point(cc[1, ]), st_point(cc[nrow(cc), ]), crs = crs_zf)
  }))
  seg <- function(a, b) st_sfc(st_linestring(rbind(st_coordinates(a)[, 1:2], st_coordinates(b)[, 1:2])), crs = crs_zf)
  zl <- st_transform(st_geometry(zf[zf$ubicacion == ZF_UBICACION, ]), CRS_ZF)
  zl <- st_cast(zl, "LINESTRING"); zl <- zl[as.numeric(st_length(zl)) > 1000]
  zl <- st_cast(st_line_merge(st_union(zl)), "LINESTRING")
  lim_p <- st_transform(st_geometry(limite_terr), CRS_ZF)
  lm <- st_cast(st_line_merge(st_union(lim_p)), "LINESTRING")
  huecos <- st_sfc(crs = crs_zf)
  if (length(lm) > 1) {
    e <- endpts(lm); pieza <- rep(seq_along(lm), each = 2)
    D <- matrix(as.numeric(st_distance(e)), length(e)); D[outer(pieza, pieza, "==")] <- Inf
    usados <- integer(0)
    for (i in seq_along(e)) {
      j <- which.min(D[i, ])
      if (!(i %in% usados) && D[i, j] < ZF_HUECO_MAX_M && which.min(D[j, ]) == i) {
        huecos <- c(huecos, seg(e[i], e[j])); usados <- c(usados, i, j)
        ll <- st_coordinates(st_transform(c(e[i], e[j]), 4326))
        message("zona fronteriza: hueco del límite cerrado con segmento de ", round(D[i, j] / 1000, 1), " km entre (",
                paste(round(ll[1, 1:2], 4), collapse = ", "), ") y (", paste(round(ll[2, 1:2], 4), collapse = ", "), ")")
      }
    }
  }
  lim_u <- st_union(c(lim_p, huecos))
  cierres <- st_sfc(crs = crs_zf)
  for (k in seq_along(e_zf <- endpts(zl))) {
    d0 <- as.numeric(st_distance(e_zf[k], lim_u))
    if (d0 < 1000) { message("zona fronteriza: extremo ", k, " de la línea ZF toca el límite"); next }
    xy <- st_coordinates(e_zf[k])[, 1:2]
    W  <- st_sfc(st_point(c(xy[1] - ZF_OFFSET_MAR_M, xy[2])), crs = crs_zf)
    s2 <- st_nearest_points(W, lim_u)
    cierres <- c(cierres, seg(e_zf[k], W), s2)
    ll <- st_coordinates(st_transform(c(e_zf[k], W, st_cast(s2, "POINT")[2]), 4326))
    message("zona fronteriza: extremo ", k, " cerrado por mar (", round(d0 / 1000), " km al límite en línea recta): segmentos (",
            paste(round(ll[1, 1:2], 4), collapse = ", "), ") -> (", paste(round(ll[2, 1:2], 4), collapse = ", "), ") -> (",
            paste(round(ll[3, 1:2], 4), collapse = ", "), ")")
  }
  red <- st_node(st_union(c(zl, st_cast(lim_u, "MULTILINESTRING"), cierres)))
  pol <- st_collection_extract(st_polygonize(red), "POLYGON")
  if (length(pol) == 0) {
    warning("No se pudo cerrar el polígono de zona fronteriza; en_zona_fronteriza irá NULL")
  } else {
    zf_pol <- st_make_valid(st_union(pol))
    pasos_in <- lengths(st_intersects(st_buffer(st_transform(pasos, CRS_ZF), 50), zf_pol)) > 0
    message("zona fronteriza: ", length(pol), " polígono(s), área ", round(as.numeric(st_area(zf_pol)) / 1e6),
            " km2; control: ", sum(pasos_in), "/", nrow(pasos), " pasos FT-03a dentro")
    if (!all(pasos_in)) warning("pasos fuera del polígono ZF: ", paste(pasos$nombre[!pasos_in], collapse = "; "))
  }
}

# ---------------------------------------------------------------- utilidades
T0 <- Sys.time()
lap <- function(t0, ...) message(sprintf("  [%s] %s (%.1f min)", format(Sys.time(), "%H:%M:%S"),
                                        paste0(...), as.numeric(difftime(Sys.time(), t0, units = "mins"))))
# descompone líneas en segmentos de 2 vértices -> permite índice espacial (STRtree) en st_nearest_feature
segmentar <- function(g) {
  cc <- st_coordinates(g)
  key <- do.call(paste, as.list(as.data.frame(cc[, -(1:2), drop = FALSE])))
  i <- which(key[-1] == key[-nrow(cc)])
  m <- cbind(cc[i, 1], cc[i, 2], cc[i + 1, 1], cc[i + 1, 2])
  st_sfc(lapply(seq_len(nrow(m)), function(k) st_linestring(matrix(m[k, ], 2, byrow = TRUE))), crs = st_crs(g))
}
# puntos extremos de cada tramo (st_boundary; MULTILINESTRING -> extremos de cada parte)
extremos <- function(t_z) {
  b <- st_boundary(st_geometry(t_z)); vac <- st_is_empty(b)
  if (any(vac)) b[vac] <- st_point_on_surface(st_geometry(t_z)[vac])   # líneas cerradas: sin extremos
  bp <- st_sf(i = seq_len(nrow(t_z)), geometry = b)
  suppressWarnings(st_cast(bp, "POINT"))
}
# unidad administrativa con mayor longitud del tramo dentro de ella
dominante <- function(t_z, pol_z, campo, etiqueta) {
  t0 <- Sys.time()
  hits <- st_intersects(t_z, pol_z); n_hit <- lengths(hits)
  out <- rep(NA_character_, nrow(t_z))
  uno <- which(n_hit == 1); out[uno] <- pol_z[[campo]][unlist(hits[uno])]
  multi <- which(n_hit > 1)
  lap(t0, etiqueta, ": st_intersects listo; 1 candidato=", length(uno), ", >1=", length(multi), ", 0=", sum(n_hit == 0))
  for (k in seq_along(multi)) {
    i <- multi[k]; cand <- pol_z[hits[[i]], ]
    lens <- vapply(seq_len(nrow(cand)), function(j)
      as.numeric(st_length(suppressWarnings(st_intersection(st_geometry(t_z)[i], st_geometry(cand)[j])))), numeric(1))
    out[i] <- cand[[campo]][which.max(lens)]
    if (k %% 500 == 0) lap(t0, etiqueta, ": intersección exacta ", k, "/", length(multi))
  }
  lap(t0, etiqueta, ": listo")
  list(valor = out, n_hit = n_hit)
}
# objeto más cercano dentro del buffer: st_intersects indexado contra buffer del OBJETIVO
# (puntos o polígonos pequeños), nunca buffer de las líneas; distancia exacta solo en los pares candidatos
mas_cercano <- function(t_z, obj_z, buffer, etiqueta) {
  t0 <- Sys.time()
  idx <- rep(NA_integer_, nrow(t_z)); dist <- rep(NA_real_, nrow(t_z))
  if (nrow(obj_z) == 0) return(list(idx = idx, dist = dist))
  w <- st_intersects(t_z, st_buffer(st_geometry(obj_z), buffer))
  for (i in which(lengths(w) > 0)) {
    d <- as.numeric(st_distance(st_geometry(t_z)[i], st_geometry(obj_z)[w[[i]]]))
    idx[i] <- w[[i]][which.min(d)]; dist[i] <- min(d)
  }
  lap(t0, etiqueta, ": ", sum(!is.na(idx)), " tramos con objeto a <= ", buffer, " m")
  list(idx = idx, dist = dist)
}

# ---------------------------------------------------------------- derivación por zona UTM
res <- list(); n_multi_comuna <- 0L; n_multi_prov <- 0L
for (z in sort(unique(tramos$utm_zona))) {
  if (!z %in% c(18L, 19L)) { warning("utm_zona no válida: ", z, " (se omite, va a vacíos)"); next }
  crs <- 32700L + z; tz0 <- Sys.time()
  t_z <- st_transform(tramos[tramos$utm_zona == z, ], crs)
  message("zona ", z, ": ", nrow(t_z), " tramos")

  com_z <- st_transform(comunas, crs); prv_z <- st_transform(provs, crs)
  pas_z <- st_transform(pasos, crs);   esq_z <- st_transform(esqui, crs)
  loc_z <- st_transform(localidades, crs); srv_z <- st_transform(servicios, crs)
  lim_seg <- segmentar(st_transform(limite_u, crs))
  zfp_z <- if (!is.null(zf_pol)) st_transform(zf_pol, crs) else NULL
  lap(tz0, "capas reproyectadas; límite en ", length(lim_seg), " segmentos")

  dc <- dominante(t_z, com_z, "NOM_COMUNA", "comuna");   n_multi_comuna <- n_multi_comuna + sum(dc$n_hit > 1)
  dp <- dominante(t_z, prv_z, "NOM_PROVIN", "provincia"); n_multi_prov   <- n_multi_prov   + sum(dp$n_hit > 1)

  mp <- mas_cercano(t_z, pas_z, BUFFER_JOIN_M, "pasos")
  ml <- mas_cercano(t_z, loc_z, BUFFER_JOIN_M, "localidades")

  # esquí: en ambos sentidos. (a) cada tramo toma su centro más cercano dentro
# del buffer; (b) cada centro toma su tramo más cercano dentro del buffer. Sin
# (b), La Parva (a 156 m del G-21-4) se perdía porque ese tramo está a 1 m de
# Farellones. Un tramo puede quedar con varios nombres.
cruce_esqui <- function(t_z, esq_z, buffer) {
  n <- nrow(t_z); nom <- vector("list", n); fte <- vector("list", n)
  agrega <- function(i, j) { nom[[i]] <<- c(nom[[i]], esq_z$nombre[j]); fte[[i]] <<- c(fte[[i]], esq_z$fuente[j])
                             esqui_matched[esq_z$.idx[j]] <<- TRUE }
  if (nrow(esq_z) > 0) {
    bz <- st_buffer(st_geometry(esq_z), buffer)
    w <- st_intersects(t_z, bz)
    for (i in which(lengths(w) > 0)) {
      d <- as.numeric(st_distance(st_geometry(t_z)[i], st_geometry(esq_z)[w[[i]]]))
      agrega(i, w[[i]][which.min(d)])
    }
    w2 <- st_intersects(bz, t_z)
    for (j in which(lengths(w2) > 0)) {
      d <- as.numeric(st_distance(st_geometry(esq_z)[j], st_geometry(t_z)[w2[[j]]]))
      agrega(w2[[j]][which.min(d)], j)
    }
  }
  list(nombre = vapply(nom, function(v) if (length(v)) paste(sort(unique(v)), collapse = "; ") else NA_character_, character(1)),
       fuente = vapply(fte, function(v) if (length(v)) paste(sort(unique(v)), collapse = ";") else NA_character_, character(1)))
}
ce <- cruce_esqui(t_z, esq_z, BUFFER_ESQUI_M)
lap(tz0, "esquí: ", sum(!is.na(ce$nombre)), " tramos con centro a <= ", BUFFER_ESQUI_M, " m (dos sentidos)")

# extremos del tramo -> distancia mínima al límite (segmento más cercano vía índice, distancia exacta por par)
  t0 <- Sys.time(); bp <- extremos(t_z)
  nf <- st_nearest_feature(bp, lim_seg)
  d_pt <- as.numeric(st_distance(st_geometry(bp), lim_seg[nf], by_element = TRUE))
  dist_lim <- as.numeric(tapply(d_pt, factor(bp$i, levels = seq_len(nrow(t_z))), min))
  lap(t0, "dist_limite_m: ", nrow(bp), " extremos")

  # zona fronteriza: TRUE si algún extremo del tramo cae dentro del polígono (decisión documentada:
  # se evalúan los extremos, no la traza completa, para evitar overlay de líneas de cientos de miles de vértices)
  if (!is.null(zfp_z)) {
    t0 <- Sys.time(); in_pt <- lengths(st_intersects(bp, zfp_z)) > 0
    en_zf <- as.logical(tapply(in_pt, factor(bp$i, levels = seq_len(nrow(t_z))), any))
    lap(t0, "en_zona_fronteriza: ", sum(en_zf), " TRUE")
  } else en_zf <- rep(NA, nrow(t_z))

  # distancia a localidad con servicios más cercana (índice + distancia exacta al polígono elegido)
  t0 <- Sys.time()
  if (nrow(srv_z) > 0) {
    nfs <- st_nearest_feature(t_z, srv_z)
    d_srv <- as.numeric(st_distance(st_geometry(t_z), st_geometry(srv_z)[nfs], by_element = TRUE)) / 1000
  } else d_srv <- rep(NA_real_, nrow(t_z))
  lap(t0, "dist_servicios_km listo")

  res[[as.character(z)]] <- tibble(
    id_tramo          = t_z$id_tramo,
    provincia         = dp$valor,
    comuna            = dc$valor,
    es_paso           = !is.na(mp$idx),
    paso_nombre       = ifelse(is.na(mp$idx), NA_character_, pas_z$nombre[mp$idx]),
    paso_pais         = ifelse(is.na(mp$idx), NA_character_, pas_z$pais[mp$idx]),
    paso_trafico      = ifelse(is.na(mp$idx), NA_character_, pas_z$trafico[mp$idx]),
    paso_habilitacion = ifelse(is.na(mp$idx), NA_character_, pas_z$habilitacn[mp$idx]),
    dist_limite_m     = round(dist_lim, 1),
    en_zona_fronteriza = en_zf,
    es_esqui          = !is.na(ce$nombre),
    esqui_nombre      = ce$nombre,
    .esqui_fuente     = ce$fuente,
    esqui_cota_base   = NA_real_,      # FT-06 no trae cota base: siempre NULL
    es_localidad      = !is.na(ml$idx),
    localidad_nombre  = ifelse(is.na(ml$idx), NA_character_, loc_z$nombre[ml$idx]),
    dist_servicios_km = round(d_srv, 3),
    buffer_join_m     = BUFFER_JOIN_M,
    .n_comunas        = dc$n_hit
  )
  lap(tz0, "zona ", z, " completa")
}
out <- bind_rows(res)
# tramos omitidos por utm_zona inválida
faltantes <- setdiff(tramos$id_tramo, out$id_tramo)
if (length(faltantes)) out <- bind_rows(out, tibble(id_tramo = faltantes))
out <- out[match(tramos$id_tramo, out$id_tramo), ]
message("tramos con más de una comuna (A2 debió cortar): ", n_multi_comuna,
        " | con más de una provincia: ", n_multi_prov)

COLS_A4 <- c("provincia", "comuna", "es_paso", "paso_nombre", "paso_pais", "paso_trafico",
             "paso_habilitacion", "dist_limite_m", "en_zona_fronteriza", "es_esqui", "esqui_nombre",
             "esqui_cota_base", "es_localidad", "localidad_nombre", "dist_servicios_km", "buffer_join_m")
destinos <- out[, c("id_tramo", COLS_A4)]

# ---------------------------------------------------------------- procedencia (formato largo)
META <- tribble(
  ~campo,               ~fuente,  ~metodo,
  "provincia",          "FT-05",  "derivado",
  "comuna",             "FT-05",  "derivado",
  "es_paso",            "FT-03a", "derivado",
  "paso_nombre",        "FT-03a", "declarado",
  "paso_pais",          "FT-03a", "declarado",
  "paso_trafico",       "FT-03a", "declarado",
  "paso_habilitacion",  "FT-03a", "declarado",
  "dist_limite_m",      "FT-03b", "derivado",
  "en_zona_fronteriza", "FT-03c", "estimado",   # polígono construido; ver encabezado
  "es_esqui",           "FT-06;FT-12", "derivado",
  "esqui_nombre",       "FT-06;FT-12", "declarado",
  "esqui_cota_base",    "FT-06",  "declarado",
  "es_localidad",       "FT-05",  "derivado",
  "localidad_nombre",   "FT-05",  "declarado",
  "dist_servicios_km",  "FT-05",  "derivado",
  "buffer_join_m",      "—",      "derivado"
)
fecha_de <- function(f) if (f %in% names(FECHAS) && !is.na(FECHAS[f])) unname(FECHAS[f]) else FECHA_HOY
procedencia <- bind_rows(lapply(COLS_A4, function(cn) {
  m <- META[META$campo == cn, ]
  ok <- !is.na(destinos[[cn]]); ids <- destinos$id_tramo[ok]
  if (!length(ids)) return(NULL)
  # es_esqui sale de las dos fuentes (un FALSE las necesita a ambas);
  # esqui_nombre lleva la fuente del centro o centros que aportaron el nombre
  fte <- if (cn == "es_esqui") rep("FT-06;FT-12", length(ids))
         else if (cn == "esqui_nombre") out$.esqui_fuente[match(ids, out$id_tramo)]
         else rep(m$fuente, length(ids))
  tibble(id_tramo = ids, campo = cn, fuente = fte,
         fecha_descarga = vapply(fte, fecha_de, character(1)),
         metodo = m$metodo, agente = AGENTE)
}))

# ---------------------------------------------------------------- vacíos
pend <- list()
addp <- function(id, campo, motivo) pend[[length(pend) + 1]] <<- tibble(id_tramo = id, campo = campo, motivo = motivo, agente = AGENTE, fecha = FECHA_HOY)
addp("*", "esqui_cota_base", "FT-06 (SERNATUR atractivos turísticos) no trae campo de cota base; columna NULL en todas las filas")
for (cn in c("paso_nombre", "paso_pais", "paso_trafico", "paso_habilitacion"))
  addp("*", cn, "NULL estructural cuando es_paso = FALSE (no aplica)")
addp("*", "esqui_nombre", "NULL estructural cuando es_esqui = FALSE (no aplica)")
for (k in which(!esqui_matched))
  addp("*", "es_esqui", sprintf("centro '%s' (%s) sin ningún tramo enrolado a <= %d m: el camino de acceso no está en la red MOP o el punto de la fuente queda lejos del acceso",
                               esqui$nombre[k], esqui$fuente[k], BUFFER_ESQUI_M))
addp("*", "es_esqui", "Bosque Nevado Huilo Huilo (Panguipulli): centro operativo según el propio recinto y listado en Snow-Forecast, pero ausente de FT-06 (SERNATUR 2020) y de FT-12 (OSM); sin fuente reutilizable no se escribe")
addp("*", "localidad_nombre", "NULL estructural cuando es_localidad = FALSE (no aplica)")
if (is.null(zf_pol)) addp("*", "en_zona_fronteriza", "FT-03c es capa de líneas; no se construyó polígono de zona fronteriza")
for (id in destinos$id_tramo[is.na(destinos$comuna)])    addp(id, "comuna",    "el tramo no intersecta ningún polígono comunal INE 2017")
for (id in destinos$id_tramo[is.na(destinos$provincia)]) addp(id, "provincia", "el tramo no intersecta ningún polígono provincial INE 2017")
for (id in destinos$id_tramo[is.na(destinos$dist_limite_m)]) addp(id, "dist_limite_m", "no se pudo calcular distancia al límite internacional")
for (id in destinos$id_tramo[is.na(destinos$dist_servicios_km)]) addp(id, "dist_servicios_km", "no se pudo calcular distancia a localidad con servicios")
for (id in faltantes) addp(id, "*", "utm_zona fuera de {18,19}; bloque A4 no derivado")
vacios <- bind_rows(pend)

# ---------------------------------------------------------------- escritura
dir.create(OUT_DIR, showWarnings = FALSE, recursive = TRUE)
write_parquet(destinos,    file.path(OUT_DIR, "a4_destinos.parquet"))
write_parquet(procedencia, file.path(OUT_DIR, "procedencia_a4.parquet"))
write.csv(vacios, file.path(OUT_DIR, "vacios_a4.csv"), row.names = FALSE, fileEncoding = "UTF-8")

# resumen
nulls <- sapply(COLS_A4, function(cn) sum(is.na(destinos[[cn]])))
message("\n== a4_destinos: ", nrow(destinos), " filas ==")
message("NULL por columna: ", paste(names(nulls), nulls, sep = "=", collapse = ", "))
message("es_paso TRUE: ", sum(destinos$es_paso, na.rm = TRUE), " | es_esqui TRUE: ", sum(destinos$es_esqui, na.rm = TRUE),
        " | es_localidad TRUE: ", sum(destinos$es_localidad, na.rm = TRUE),
        " | en_zona_fronteriza TRUE: ", sum(destinos$en_zona_fronteriza, na.rm = TRUE))
# pasos vehiculares según literal de FT-03a (decisión del orquestador: no se filtra en la base, solo se informa)
PASO_VEHICULAR <- c("Personas, vehículos y carga", "Solo cruce de peatones y vehículos particulares")
veh <- destinos$es_paso %in% TRUE & destinos$paso_trafico %in% PASO_VEHICULAR
message("tramos con paso vehicular (", paste(PASO_VEHICULAR, collapse = " / "), "): ", sum(veh),
        " | con paso no vehicular: ", sum(destinos$es_paso %in% TRUE) - sum(veh))
message("procedencia: ", nrow(procedencia), " filas | vacíos: ", nrow(vacios), " filas")
lap(T0, "tiempo total")
