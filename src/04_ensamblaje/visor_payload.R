# ---------------------------------------------------------------------------
# visor_payload.R — extrae data/processed/tramos.parquet a un payload compacto
# para el visor HTML autocontenido.
#
# No deriva ningun valor nuevo. Copia lo que ya esta en la base y adjunta la
# procedencia declarada en procedencia.parquet (Regla 2). Los NULL de la base
# viajan como null y se muestran como tales (Regla 1).
#
# Salida: data/interim/visor_payload.json
# ---------------------------------------------------------------------------

suppressMessages({library(arrow); library(sf); library(jsonlite)})

TOL_M      <- 5      # tolerancia de simplificacion, bajo el espaciado nativo (10,5 m)
ESCALA     <- 1e5    # cuantizacion de coordenadas: 1e-5 grados ~ 1,1 m
PARQUET    <- "data/processed/tramos.parquet"
GPKG       <- "data/processed/tramos.gpkg"
PROCEDEN   <- "data/processed/procedencia.parquet"
DESCRIP    <- "docs/descripciones_columnas.csv"
SALIDA     <- "data/interim/visor_payload.json"

log_ <- function(...) cat(format(Sys.time(), "%H:%M:%S"), "|", ..., "\n")

# --- 1. atributos ----------------------------------------------------------
log_("leyendo", PARQUET)
d <- read_parquet(PARQUET)
d$geometria <- NULL
n <- nrow(d)
log_("filas:", n, " columnas:", ncol(d))

# Sin redondeo: el payload es copia fiel del parquet. El redondeo para mostrar
# ocurre en el visor (V.fmt), no en los datos, para que la exportacion a CSV
# arrastre el valor exacto de la base.

dicts <- list(); data_ <- list(); cols <- list()

for (nm in names(d)) {
  x <- d[[nm]]
  if (is.logical(x)) {
    tipo <- "bool"; val <- ifelse(is.na(x), NA, as.integer(x))
  } else if (is.numeric(x)) {
    tipo <- "num"
    val <- x
  } else {
    x <- as.character(x)
    u <- sort(unique(x[!is.na(x)]))
    if (length(u) <= 2000) {                       # diccionario
      # I() evita que auto_unbox convierta un diccionario de un solo valor
      # en texto suelto: el visor indexaria caracteres en vez de valores.
      tipo <- "dict"; dicts[[nm]] <- I(u)
      val <- match(x, u) - 1L                      # 0-based, NA se mantiene
    } else {
      tipo <- "str"; val <- x
    }
  }
  data_[[nm]] <- val
  cols[[length(cols) + 1]] <- list(n = nm, t = tipo,
                                   nulos = sum(is.na(x)),
                                   distintos = length(unique(x[!is.na(x)])))
}
log_("columnas con diccionario:", length(dicts))

# --- 2. procedencia por campo (Regla 2) ------------------------------------
log_("leyendo procedencia")
p <- read_parquet(PROCEDEN)
proc <- list(); proc_var <- list()
for (campo in unique(p$campo)) {
  s <- p[p$campo == campo, ]
  k <- unique(paste(s$fuente, s$fecha_descarga, s$metodo, s$agente, sep = "\u001f"))
  if (length(k) == 1) {
    proc[[campo]] <- list(fuente = s$fuente[1], fecha = as.character(s$fecha_descarga[1]),
                          metodo = s$metodo[1], agente = s$agente[1])
  } else {
    # campo con procedencia no constante: se guarda por tramo, sin colapsar
    combos <- data.frame(k = k, stringsAsFactors = FALSE)
    partes <- do.call(rbind, strsplit(k, "\u001f", fixed = TRUE))
    proc_var[[campo]] <- list(
      opciones = lapply(seq_len(nrow(partes)), function(i)
        list(fuente = partes[i,1], fecha = partes[i,2], metodo = partes[i,3], agente = partes[i,4])),
      por_tramo = match(paste(s$fuente, s$fecha_descarga, s$metodo, s$agente, sep="\u001f"),
                        k)[match(d$id_tramo, s$id_tramo)] - 1L)
    log_("procedencia no constante en:", campo, "->", nrow(partes), "combinaciones")
  }
}
log_("campos con procedencia constante:", length(proc))

# --- 3. descripciones para el libro de codigos en linea --------------------
desc <- list()
if (file.exists(DESCRIP)) {
  dd <- read.csv(DESCRIP, sep = "|", quote = "\"", stringsAsFactors = FALSE,
                 colClasses = "character", encoding = "UTF-8")
  for (i in seq_len(nrow(dd)))
    desc[[dd$columna[i]]] <- list(que_es = dd$que_es[i], de_donde = dd$de_donde_sale[i],
                                  como_leerlo = dd$como_leerlo[i])
  log_("descripciones cargadas:", length(desc))
}

# --- 4. geometria ----------------------------------------------------------
log_("leyendo geometria de", GPKG)
g  <- st_read(GPKG, quiet = TRUE)
stopifnot(identical(g$id_tramo, d$id_tramo))       # el orden debe calzar fila a fila
gg <- st_zm(st_geometry(g))

log_("simplificando a", TOL_M, "m")
gs <- st_simplify(gg, dTolerance = TOL_M, preserveTopology = TRUE)

cnt <- function(x) if (is.matrix(x)) nrow(x) else if (is.list(x)) sum(unlist(lapply(x, cnt))) else 0
degen <- which(sapply(gs, cnt) < 2)
if (length(degen)) {                                # tramos que colapsan: geometria original
  log_("tramos degenerados restituidos sin simplificar:", length(degen))
  gs[degen] <- gg[degen]
}
gs <- st_cast(st_sfc(gs, crs = 4326), "MULTILINESTRING")

co <- st_coordinates(gs)                            # X, Y, L1 = parte, L2 = tramo
log_("vertices en el payload:", nrow(co))

qx <- as.integer(round(co[, "X"] * ESCALA))
qy <- as.integer(round(co[, "Y"] * ESCALA))
tramo_de <- as.integer(co[, "L2"])
parte_de <- as.integer(co[, "L1"])

# clave global de parte: cambia cuando cambia el tramo o la parte
clave  <- cumsum(c(TRUE, (tramo_de[-1] != tramo_de[-length(tramo_de)]) |
                          (parte_de[-1] != parte_de[-length(parte_de)])))
primero <- !duplicated(clave)                       # primer vertice de cada parte

# deltas dentro de cada parte; los primeros van absolutos aparte
dx <- c(0L, diff(qx)); dy <- c(0L, diff(qy))
dx[primero] <- 0L;     dy[primero] <- 0L
stopifnot(max(abs(dx[!primero])) < 32768, max(abs(dy[!primero])) < 32768)

starts_x <- qx[primero]; starts_y <- qy[primero]
del_x    <- dx[!primero]; del_y   <- dy[!primero]

# intercalado x,y para un solo recorrido en JS
starts <- as.integer(rbind(starts_x, starts_y))
deltas <- as.integer(rbind(del_x, del_y))

b64 <- function(v, size) {
  f <- tempfile(); con <- file(f, "wb")
  writeBin(v, con, size = size, endian = "little"); close(con)
  s <- jsonlite::base64_enc(readBin(f, "raw", file.size(f))); unlink(f); s
}
log_("codificando: partes", length(starts_x), " deltas", length(del_x))
geom <- list(
  escala      = ESCALA,
  tol_m       = TOL_M,
  n_vertices  = nrow(co),
  starts_b64  = b64(starts, 4L),                    # Int32 intercalado x,y
  deltas_b64  = b64(deltas, 2L),                    # Int16 intercalado dx,dy
  # cuantas partes tiene cada tramo, y cuantos vertices cada parte
  # tabulate respeta el orden del indice; tapply/table ordenarian los grupos
  # como texto ("1","10","100") y desalinearian la geometria de cada tramo
  partes_por_tramo = tabulate(tramo_de[primero], nbins = n),
  verts_por_parte  = tabulate(clave, nbins = max(clave))
)
bb <- as.numeric(st_bbox(gs))

payload <- list(
  meta = list(
    generado = format(Sys.time(), "%Y-%m-%dT%H:%M:%S"),
    n_tramos = n,
    parquet  = PARQUET,
    gpkg     = GPKG,
    nota     = paste("Valores copiados de la base. Ningun valor se deriva ni se",
                     "completa en el visor. Las celdas vacias son NULL en la base.")
  ),
  cols = cols, dicts = dicts, data = data_,
  proc = proc, proc_var = proc_var, desc = desc,
  geom = geom, bbox = bb
)

# --- 5. verificacion de ida y vuelta ---------------------------------------
log_("verificando reconstruccion de la geometria")
stopifnot(sum(geom$partes_por_tramo) == length(starts_x))
stopifnot(sum(geom$verts_por_parte)  == nrow(co))
stopifnot(sum(geom$verts_por_parte - 1) == length(del_x))
# reconstruye como lo hara el navegador y compara contra los cuantizados
rx <- integer(nrow(co)); ry <- integer(nrow(co)); ip <- 1L; iv <- 1L; id <- 1L
for (k in seq_along(geom$verts_por_parte)) {
  nvp <- geom$verts_por_parte[k]
  cx <- starts_x[ip]; cy <- starts_y[ip]; ip <- ip + 1L
  rx[iv] <- cx; ry[iv] <- cy; iv <- iv + 1L
  if (nvp > 1) for (j in seq_len(nvp - 1)) {
    cx <- cx + del_x[id]; cy <- cy + del_y[id]; id <- id + 1L
    rx[iv] <- cx; ry[iv] <- cy; iv <- iv + 1L
  }
}
stopifnot(identical(rx, qx), identical(ry, qy))
log_("reconstruccion exacta sobre", nrow(co), "vertices")

dir.create(dirname(SALIDA), showWarnings = FALSE, recursive = TRUE)
write(toJSON(payload, auto_unbox = TRUE, na = "null", null = "null", digits = 22), SALIDA)   # NA daria 15 cifras significativas, no el double exacto
log_("escrito", SALIDA, round(file.size(SALIDA)/1e6, 2), "MB")

# version comprimida: el visor la incrusta en base64 y la descomprime al abrir
gz <- paste0(SALIDA, ".gz")
con <- gzfile(gz, "wb", compression = 9)
writeBin(readBin(SALIDA, "raw", file.size(SALIDA)), con); close(con)
log_("gzip", round(file.size(gz)/1e6, 2), "MB -> base64",
     round(file.size(gz)*4/3/1e6, 2), "MB")
