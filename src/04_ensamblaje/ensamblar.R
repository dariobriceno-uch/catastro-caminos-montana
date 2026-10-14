# Ensamblaje final — orquestador (bloque ORQ).
# Une data/interim/{a2_tramos.gpkg, a3_altimetria, a4_destinos, a5_transito, a6_geomorf}.parquet por id_tramo,
# remapea procedencia_a1 (id_tramo_a1 -> id_tramo de A2), consolida procedencia y vacíos,
# escribe data/processed/tramos.parquet, tramos.gpkg, procedencia.parquet, data/vacios.csv,
# logs/agregados_regionales.csv. No deriva ningún valor nuevo: solo une y remapea.
suppressPackageStartupMessages({library(sf); library(arrow); library(dplyr)})
root <- normalizePath(".")
hoy <- format(Sys.Date(), "%Y-%m-%d")
ip <- function(p) file.path(root, "data/interim", p)
lee_parquet_opt <- function(p) if (file.exists(ip(p))) read_parquet(ip(p)) else NULL

a2 <- st_read(ip("a2_tramos.gpkg"), "tramos", quiet = TRUE)
geom_col <- attr(a2, "sf_column")
cat("A2:", nrow(a2), "filas\n")

bloques <- list(A3 = "a3_altimetria.parquet", A4 = "a4_destinos.parquet", A5 = "a5_transito.parquet",
                A6 = "a6_geomorf.parquet", A7 = "a7_nieve.parquet")
tab <- a2
faltantes <- c()
for (b in names(bloques)) {
  d <- lee_parquet_opt(bloques[[b]])
  if (is.null(d)) { faltantes <- c(faltantes, b); cat("FALTA", b, "\n"); next }
  stopifnot(!any(duplicated(d$id_tramo)))
  extra <- setdiff(names(d), c("id_tramo", names(tab)))
  tab <- left_join(tab, d[, c("id_tramo", extra)], by = "id_tramo")
  cat(b, ":", nrow(d), "filas,", length(extra), "columnas\n")
}

# Bloque ORQ
tab$en_lista_colega <- NA  # reference/candidatos_colega.xlsx no existe (Regla 6 no ejecutable)
col_orden <- c("id_tramo", "en_lista_colega", setdiff(names(tab), c("id_tramo", "en_lista_colega", geom_col)), geom_col)
tab <- tab[, col_orden]

# Procedencia
pa1 <- read_parquet(ip("procedencia_a1.parquet"))
mapa <- st_drop_geometry(a2)[, c("id_tramo", "id_tramo_a1")]
pa1 <- pa1 %>% rename(id_tramo_a1 = id_tramo) %>% inner_join(mapa, by = "id_tramo_a1", relationship = "many-to-many") %>%
  select(id_tramo, campo, fuente, fecha_descarga, metodo, agente)
proc <- list(pa1)
for (b in c("a2", "a3", "a4", "a5", "a6", "a7")) {
  d <- lee_parquet_opt(sprintf("procedencia_%s.parquet", b))
  if (!is.null(d)) proc[[length(proc) + 1]] <- d[, c("id_tramo", "campo", "fuente", "fecha_descarga", "metodo", "agente")]
}
proc <- bind_rows(proc) %>% mutate(fecha_descarga = as.character(fecha_descarga))
cat("Procedencia:", nrow(proc), "filas\n")

# Vacíos
pend <- list()
for (b in c("a1", "a2", "a3", "a4", "a5", "a6", "a7")) {
  p <- ip(sprintf("vacios_%s.csv", b))
  if (file.exists(p)) {
    d <- read.csv(p, stringsAsFactors = FALSE, encoding = "UTF-8")
    d <- d[, c("id_tramo", "campo", "motivo", "agente", "fecha")]
    if (b == "a1") { # remapear id_tramo_a1 -> id_tramo
      d <- d %>% rename(id_tramo_a1 = id_tramo) %>% inner_join(mapa, by = "id_tramo_a1", relationship = "many-to-many") %>%
        select(id_tramo, campo, motivo, agente, fecha)
    }
    pend[[b]] <- d
  }
}
pend[["orq"]] <- data.frame(
  id_tramo = "*", campo = "en_lista_colega",
  motivo = "reference/candidatos_colega.xlsx no existe; Regla 6 no ejecutable",
  agente = "ORQ", fecha = hoy)
if ("A7" %in% faltantes) pend[["orq_nieve"]] <- data.frame(
  id_tramo = "*", campo = c("dias_nieve_mediana", "serie_inicio", "serie_fin"),
  motivo = "FT-08 pendiente: bloque A7 no entregado", agente = "ORQ", fecha = hoy)
for (b in faltantes) pend[[paste0("falta_", b)]] <- data.frame(id_tramo = "*", campo = b, motivo = "bloque no entregado", agente = "ORQ", fecha = hoy)
pend <- bind_rows(pend)
cat("Vacíos:", nrow(pend), "filas\n")

# Agregados regionales (recalculados desde la tabla)
agg <- st_drop_geometry(tab) %>% group_by(region) %>%
  summarise(n_tramos = n(), suma_longitud_calc_m = sum(longitud_calc_m, na.rm = TRUE),
            n_es_paso = if ("es_paso" %in% names(tab)) sum(es_paso %in% TRUE) else NA_integer_, .groups = "drop")

dir.create(file.path(root, "data/processed"), showWarnings = FALSE, recursive = TRUE)
st_write(tab, file.path(root, "data/processed/tramos.gpkg"), "tramos", delete_dsn = TRUE, quiet = TRUE)
df <- st_drop_geometry(tab); df$geometria <- unclass(st_as_binary(st_geometry(tab))); attributes(df$geometria) <- NULL  # WKB (GeoParquet); WKT era inviable con 10 M de vértices
write_parquet(df, file.path(root, "data/processed/tramos.parquet"))
write_parquet(proc, file.path(root, "data/processed/procedencia.parquet"))
write.csv(pend, file.path(root, "data/vacios.csv"), row.names = FALSE, fileEncoding = "UTF-8")
write.csv(agg, file.path(root, "logs/agregados_regionales.csv"), row.names = FALSE, fileEncoding = "UTF-8")
cat("Escrito. Columnas:", ncol(df), "\n")
print(colSums(is.na(df)))
