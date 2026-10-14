# a6_geomorfologia.R — Bloque A6: unidad geomorfológica y vertiente por tramo.
#
# Insumo:  data/raw/Unidades Geomorfologicas/*.shp   (FT-10, 116 polígonos, EPSG:3857)
#          data/interim/a2_tramos.gpkg                (geometría de los tramos)
# Salida:  data/interim/a6_geomorf.parquet            id_tramo + columnas A6
#          data/interim/procedencia_a6.parquet        formato largo
#          data/interim/vacios_a6.csv
#
# Columnas que escribe (docs/esquema.md, bloque A6):
#   unidad_geomorf    nombre de la unidad TAL CUAL viene en FT-10, elegida por
#                     cruce espacial: la que contiene la mayor longitud del
#                     tramo (mismo criterio que `comuna` en A4). derivado.
#   n_unidades_geomorf cuántas unidades toca el tramo. derivado.
#   vertiente         reagrupación de `unidad_geomorf` en andina | costera |
#                     transversal | otra, según la tabla VERTIENTE de abajo,
#                     que es la misma que figura en docs/esquema.md. derivado.
#
# Nada se estima. Un tramo que no toca ningún polígono queda NULL y va a
# vacíos. Una unidad que no esté en la tabla VERTIENTE deja `vertiente`
# NULL y va a vacíos: la tabla se corrige, no se adivina.

suppressPackageStartupMessages({library(sf); library(arrow); library(dplyr); library(digest)})
root <- normalizePath(".")
hoy  <- format(Sys.Date(), "%Y-%m-%d")
lap  <- function(t0, ...) message(sprintf("[%5.0fs] ", as.numeric(Sys.time() - t0, units = "secs")), ...)
t0   <- Sys.time()

RAW_SHP  <- list.files(file.path(root, "data/raw/Unidades Geomorfologicas"),
                       pattern = "[.]shp$", full.names = TRUE)[1]
A2_GPKG  <- file.path(root, "data/interim/a2_tramos.gpkg")
OUT_DIR  <- file.path(root, "data/interim")
FECHA_DESCARGA <- "2026-08-27"   # descarga manual del usuario; ver manifest/A6.json
CRS_TRABAJO <- 32719             # solo se comparan longitudes relativas dentro de
                                 # un mismo tramo: la zona no altera cuál domina

# ---------------------------------------------------------------- tabla de vertientes
# Reagrupación explícita de las 41 unidades de FT-10. Es una decisión
# documentada (docs/esquema.md), no un dato de la fuente.
VERTIENTE <- c(
  # --- andina: cordillera de los Andes y su precordillera, de norte a sur
  "Cordillera prealtiplanica"                                   = "andina",
  "Altiplano"                                                   = "andina",
  "Precordillera rio Lauca"                                     = "andina",
  "Precordillera rio Loa superior"                              = "andina",
  "Precordillera de Domeyko"                                    = "andina",
  "Precordillera"                                               = "andina",
  "Cordillera andina de retencion crionival"                    = "andina",
  "Cordillera volcanica activa"                                 = "andina",
  "Precordillera morrenica"                                     = "andina",
  "Cordillera patagonica de lagos y rios de control tectonico"  = "andina",
  "Cordillera patagonica de fiordos y rios de control tectonico" = "andina",
  "Cordillera patagonica de ventisqueros del Pacifico"          = "andina",
  "Cordillera patagonica insular"                               = "andina",
  # --- costera: cordillera de la Costa y su borde litoral
  "Cordillera de la costa"                                      = "costera",
  "Cordillera de la costa con tectonica de hundimiento"         = "costera",
  "Farellon costero"                                            = "costera",
  "Planicie marina o fluviomarina"                              = "costera",
  "Cuencas graniticas marginales"                               = "costera",
  "Cuenca granitica marginal"                                   = "costera",
  # --- transversal: cordones que unen ambas cordilleras (Norte Chico)
  "Cordones transversales"                                      = "transversal",
  # --- otra: depresiones, llanos, pampas, cuencas, salares, desierto
  "Depresion rio Lauca"                                         = "otra",
  "Depresion salares cautivos"                                  = "otra",
  "Depresion de rio Loa superior"                                = "otra",
  "Gran fosa prealtiplanica"                                    = "otra",
  "Pampa del Tamarugal"                                         = "otra",
  "Depresion de Atacama"                                        = "otra",
  "Desierto de Atacama"                                         = "otra",
  "Salares"                                                     = "otra",
  "Pediplanos, glacis y piedemont"                              = "otra",
  "Llanos de sedimentacion fluvial o aluvional"                 = "otra",
  "Pampitas"                                                    = "otra",
  "Pampa transicional"                                          = "otra",
  "Cuencas transicionales semiaridas"                           = "otra",
  "Cuenca de Santiago"                                          = "otra",
  "Cuenca de Rancagua"                                          = "otra",
  "Llano central con tectonica de hundimiento"                  = "otra",
  "Llano central fluvio-glacio-volcanico"                       = "otra",
  "Llano central con morrenas y conos"                          = "otra",
  "Lagos de barrera morrenica"                                  = "otra",
  "Pampa ondulada o austral"                                    = "otra",
  "Pampa magellanica"                                           = "otra"
)

# ---------------------------------------------------------------- insumos
stopifnot(file.exists(RAW_SHP), file.exists(A2_GPKG))
geo <- st_read(RAW_SHP, quiet = TRUE)
lap(t0, "FT-10: ", nrow(geo), " polígonos, ", length(unique(geo$unidad)), " unidades, EPSG:", st_crs(geo)$epsg)
n_invalidas <- sum(!st_is_valid(geo))
geo <- st_make_valid(st_transform(geo, CRS_TRABAJO))
lap(t0, "polígonos reparados con st_make_valid: ", n_invalidas)

sin_tabla <- setdiff(unique(geo$unidad), names(VERTIENTE))
if (length(sin_tabla)) message("AVISO: unidades sin vertiente en la tabla: ", paste(sin_tabla, collapse = " | "))

tr <- st_read(A2_GPKG, "tramos", quiet = TRUE)
tr <- st_transform(st_zm(tr), CRS_TRABAJO)
lap(t0, "A2: ", nrow(tr), " tramos")

# ---------------------------------------------------------------- cruce: unidad dominante por longitud
hits  <- st_intersects(tr, geo); n_hit <- lengths(hits)
unidad <- rep(NA_character_, nrow(tr))
uno <- which(n_hit == 1); unidad[uno] <- geo$unidad[unlist(hits[uno])]
multi <- which(n_hit > 1)
lap(t0, "st_intersects: 1 candidato=", length(uno), ", >1=", length(multi), ", 0=", sum(n_hit == 0))
for (k in seq_along(multi)) {
  i <- multi[k]; cand <- geo[hits[[i]], ]
  lens <- vapply(seq_len(nrow(cand)), function(j)
    as.numeric(st_length(suppressWarnings(st_intersection(st_geometry(tr)[i], st_geometry(cand)[j])))), numeric(1))
  unidad[i] <- cand$unidad[which.max(lens)]
  if (k %% 500 == 0) lap(t0, "intersección exacta ", k, "/", length(multi))
}
lap(t0, "cruce listo")

vert <- unname(VERTIENTE[unidad])          # NA si la unidad no está en la tabla
vert[is.na(unidad)] <- NA_character_

a6 <- data.frame(id_tramo = tr$id_tramo, unidad_geomorf = unidad,
                 n_unidades_geomorf = as.integer(n_hit), vertiente = vert,
                 stringsAsFactors = FALSE)
message("unidad_geomorf NULL: ", sum(is.na(a6$unidad_geomorf)),
        " | vertiente NULL: ", sum(is.na(a6$vertiente)))
print(table(a6$vertiente, useNA = "ifany"))

# ---------------------------------------------------------------- procedencia (formato largo)
COLS_A6 <- c("unidad_geomorf", "n_unidades_geomorf", "vertiente")
procedencia <- bind_rows(lapply(COLS_A6, function(cn) {
  ok <- !is.na(a6[[cn]])
  data.frame(id_tramo = a6$id_tramo[ok], campo = cn, fuente = "FT-10",
             fecha_descarga = FECHA_DESCARGA, metodo = "derivado", agente = "A6",
             stringsAsFactors = FALSE)
}))

# ---------------------------------------------------------------- vacíos
pend <- list(); addp <- function(id, campo, motivo)
  pend[[length(pend) + 1]] <<- data.frame(id_tramo = id, campo = campo, motivo = motivo,
                                          agente = "A6", fecha = hoy, stringsAsFactors = FALSE)
for (id in a6$id_tramo[is.na(a6$unidad_geomorf)]) {
  addp(id, "unidad_geomorf", "el tramo no intersecta ningún polígono de FT-10")
  addp(id, "vertiente", "sin unidad_geomorf (el tramo no intersecta ningún polígono de FT-10)")
}
for (id in a6$id_tramo[!is.na(a6$unidad_geomorf) & is.na(a6$vertiente)])
  addp(id, "vertiente", paste0("unidad '", a6$unidad_geomorf[a6$id_tramo == id],
                               "' sin vertiente asignada en la tabla de docs/esquema.md"))
vacios <- if (length(pend)) bind_rows(pend) else
  data.frame(id_tramo = character(), campo = character(), motivo = character(),
             agente = character(), fecha = character())

# ---------------------------------------------------------------- escribir
write_parquet(a6, file.path(OUT_DIR, "a6_geomorf.parquet"))
write_parquet(procedencia, file.path(OUT_DIR, "procedencia_a6.parquet"))
write.csv(vacios, file.path(OUT_DIR, "vacios_a6.csv"), row.names = FALSE, fileEncoding = "UTF-8")

# manifiesto parcial (Regla 3)
dbf <- sub("[.]shp$", ".dbf", RAW_SHP)
man <- list(list(
  fuente = "FT-10", archivo = sub(paste0("^", root, "/?"), "", RAW_SHP),
  url = "PENDIENTE: completar con la URL exacta de descarga (ArcGIS Hub / IDE Chile)",
  timestamp_utc = paste0(FECHA_DESCARGA, " (manual)"),
  n_registros = nrow(geo), sha256 = digest(RAW_SHP, algo = "sha256", file = TRUE),
  agente = "A6",
  notas = paste0("Unidades geomorfológicas de Chile (Börgel); 41 unidades; EPSG:3857; ",
                 "sha256 del .shp; .dbf sha256=", digest(dbf, algo = "sha256", file = TRUE),
                 "; ", n_invalidas, " polígonos inválidos reparados con st_make_valid")))
writeLines(jsonlite::toJSON(man, auto_unbox = TRUE, pretty = TRUE),
           file.path(root, "data/raw/manifest/A6.json"), useBytes = TRUE)
lap(t0, "escrito a6_geomorf.parquet, procedencia_a6.parquet, vacios_a6.csv, manifest/A6.json")
