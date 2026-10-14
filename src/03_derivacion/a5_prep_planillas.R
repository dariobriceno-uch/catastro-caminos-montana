# A5 — Tránsito. Fase de preparación.
# Normaliza las planillas FT-02 (data/raw/Censo Nacional/*.xls) a una tabla
# larga: una fila por estación-rama × año × muestra. Todo `declarado`.
# También normaliza las capas del REST de respaldo (data/raw/censo_rest/) a
# una tabla de puntos con coordenadas, para el cruce espacial posterior.
#
# Ejecutar desde la raíz:  Rscript src/03_derivacion/a5_prep_planillas.R
#
# Salidas:
#   data/interim/a5_puntos_censales_planilla.parquet
#   data/interim/a5_puntos_censales_rest.parquet
#   data/interim/vacios_a5_prep.csv
#
# Decisiones documentadas (ver reporte A5):
#   - punto_censal_id  = "RR-EEE" (estación de control), primeros dos bloques
#     del código de la planilla "RR-EEE-RR-M". Coincide en formato con
#     ESTACION_DE_CONTROL del REST.
#   - punto_rama_id    = "RR-EEE-RR" (estación + rama).
#   - muestra_literal  = V / I / P tal cual la planilla; `muestra` se mapea a
#     febrero / junio / octubre según la ficha oficial
#     (data/raw/censo_rest/ficha_plan_nacional_censo_vial.html: "tres muestras:
#     en febrero (verano), en junio (invierno) y en octubre (primavera)").
#   - anio             = del título "VOLUMEN DE TRANSITO AÑO 2024" (letras
#     espaciadas), compactando espacios.
#   - tmda             = TOTAL RAMA de la muestra (columna literal).
#   - tmda_anual       = "Transito Medio Diario Anual" de la fila resumen del
#     bloque (una por estación-rama), repetido en las tres muestras.
#   - km_planilla      = número extraído del texto "( KM. 92.160 )" o "(470 MTS.)"
#     presente en NOMBRE DEL CAMINO; km_texto conserva el literal. Solo cuando
#     el texto lo trae. No se infiere.
#   - Las planillas NO traen coordenadas: no hay lat/lon.

suppressPackageStartupMessages({
  library(readxl); library(dplyr); library(arrow); library(jsonlite)
})
options(warn = 1)
setwd_root <- function() {
  if (!file.exists("REGLAS.md")) stop("Ejecutar desde la raíz del repositorio")
}
setwd_root()

dir_xls  <- "data/raw/Censo Nacional"
dir_rest <- "data/raw/censo_rest"
dir_out  <- "data/interim"
dir.create(dir_out, showWarnings = FALSE, recursive = TRUE)

fecha_descarga <- "2026-08-26"
pend <- list()
add_pend <- function(archivo, fila, motivo) {
  pend[[length(pend) + 1]] <<- data.frame(
    archivo = archivo, fila_excel = fila, motivo = motivo,
    agente = "A5", fecha = format(Sys.Date(), "%Y-%m-%d"),
    stringsAsFactors = FALSE)
}

compact <- function(x) trimws(gsub("[[:space:]]+", " ", x))
# Títulos como "V O L U M E N   D E   T R A N S I T O   A Ñ O   2 0 2 4":
# quita todos los espacios y reinserta uno donde había 2 o más.
descompactar_titulo <- function(x) {
  x <- gsub(intToUtf8(160), " ", x, fixed = TRUE)   # NBSP entre palabras
  x <- gsub("[[:space:]]{2,}", "§", x)
  x <- gsub("[[:space:]]", "", x)
  trimws(gsub("§", " ", x))
}

map_muestra <- c(V = "febrero", I = "junio", P = "octubre")

comp_cols <- c(
  "AUTOS" = "autos", "CAMIONETAS" = "camionetas",
  "CAMIONES2EJES" = "camiones_2_ejes", "CAMIONESMAS2EJES" = "camiones_mas_2_ejes",
  "CAMINONESMAS2EJES" = "camiones_mas_2_ejes",  # typo presente en PNCV2025
  "SEMIREMOLQUE" = "semi_remolque", "REMOLQUE" = "remolque",
  "LOCOMOCIONCOLECTIVA" = "locomocion_colectiva", "MOTOS" = "motos",
  "BICICLETAS" = "bicicletas", "TRACCIONANIMAL" = "traccion_animal",
  "VARIOS" = "varios", "TOTALRAMA" = "total_rama",
  "TRANSITOANTERIOR" = "transito_anterior")

norm_hdr <- function(h) {
  h <- toupper(compact(h))
  h <- chartr("ÁÉÍÓÚÑ", "AEIOUN", h)
  gsub("[^A-Z0-9]", "", h)
}

leer_planilla <- function(f) {
  hojas <- excel_sheets(f)
  out <- list()
  for (s in hojas) {
    d <- suppressMessages(read_excel(f, sheet = s, col_names = FALSE,
                                     .name_repair = "minimal", col_types = "text"))
    if (nrow(d) == 0) next
    # fila de encabezado: primera cuyo contenido en col 1 o 2 empieza con ESTACI
    hdr_rows <- which(apply(d[, 1:2], 1, function(r) any(grepl("^ESTACI", r))))
    if (!length(hdr_rows)) { add_pend(basename(f), NA, paste0("hoja ", s, ": sin fila de encabezado")); next }
    hdr <- hdr_rows[1]
    hv  <- as.character(unlist(d[hdr, ]))
    hn  <- norm_hdr(hv); hn[is.na(hv)] <- ""
    col_code <- which(grepl("^ESTACIONDECONTROL", hn))[1]
    col_nom  <- which(hn == "NOMBREDELCAMINO")[1]
    col_rol  <- which(hn == "ROL")[1]
    col_asim <- which(hn == "ESTACIONASIMILABLE")[1]
    col_mue  <- which(hn == "MUESTRA")[1]
    if (any(is.na(c(col_code, col_nom, col_rol, col_asim, col_mue)))) {
      add_pend(basename(f), hdr, paste0("hoja ", s, ": encabezado incompleto: ", paste(hv[!is.na(hv)], collapse = "|"))); next
    }
    col_comp <- sapply(names(comp_cols), function(k) { w <- which(hn == k); if (length(w)) w[1] else NA })
    col_comp <- col_comp[!is.na(col_comp)]
    faltan <- setdiff(unique(comp_cols), comp_cols[names(col_comp)])
    if (length(faltan)) add_pend(basename(f), hdr, paste0("hoja ", s, ": columnas de composición ausentes: ", paste(faltan, collapse = ",")))

    # título: región y año (celdas no vacías de las filas anteriores al encabezado)
    tit <- as.character(unlist(d[seq_len(hdr - 1), ])); tit <- tit[!is.na(tit)]
    tit <- descompactar_titulo(tit)
    region_planilla <- if (length(tit)) tit[1] else NA_character_
    anio_txt <- regmatches(tit, regexpr("A[NÑ]O[ ]*20[0-9]{2}", tit))
    anio <- if (length(anio_txt)) as.integer(sub(".*(20[0-9]{2}).*", "\\1", anio_txt[1])) else NA_integer_
    if (is.na(anio)) {
      m <- regmatches(s, regexpr("20[0-9]{2}", s))
      if (length(m)) anio <- as.integer(m) else add_pend(basename(f), NA, paste0("hoja ", s, ": año no encontrado en título ni nombre de hoja"))
    }

    codes <- d[[col_code]]
    pat <- "^([0-9]{2})-([0-9]{3})-([0-9]{2})-0?([123])$"
    is_row <- !is.na(codes) & grepl(pat, trimws(codes))
    # filas con algo en col código que no son ni patrón ni encabezado ni título
    otras <- which(!is.na(codes) & !is_row & seq_along(codes) > hdr & !grepl("^ESTACI", codes))
    for (i in otras) add_pend(basename(f), i, paste0("código de estación no interpretable: '", codes[i], "'"))

    idx <- which(is_row)
    if (!length(idx)) { add_pend(basename(f), NA, paste0("hoja ", s, ": sin filas de datos")); next }
    cc <- trimws(codes[idx])
    reg <- sub(pat, "\\1", cc); est <- sub(pat, "\\2", cc); ram <- sub(pat, "\\3", cc); mu <- sub(pat, "\\4", cc)
    rows <- data.frame(
      fila_excel = idx, codigo_planilla = cc,
      region_codigo = reg, punto_censal_id = paste0(reg, "-", est),
      rama = ram, punto_rama_id = paste0(reg, "-", est, "-", ram),
      muestra_num = mu, stringsAsFactors = FALSE)
    rows$nombre_fila <- compact(d[[col_nom]][idx])
    rows$rol_fila    <- compact(d[[col_rol]][idx])
    rows$estacion_asimilable <- compact(d[[col_asim]][idx])
    rows$muestra_literal <- compact(d[[col_mue]][idx])
    for (k in names(col_comp)) rows[[comp_cols[[k]]]] <- suppressWarnings(as.numeric(d[[col_comp[[k]]]][idx]))

    # bloque = estación-rama. Fila resumen: la siguiente a la última muestra del
    # bloque cuya col NOMBRE contiene "Transito Medio Diario Anual".
    rows$tmda_anual <- NA_real_; rows$tasa_crecimiento <- NA_real_
    pct_names <- setdiff(unique(comp_cols), c("total_rama", "transito_anterior"))
    for (p in pct_names) rows[[paste0("pct_", p)]] <- NA_real_
    rows$rol_planilla <- NA_character_
    rows$nombre_camino <- NA_character_; rows$nombre_rama <- NA_character_; rows$ubicacion_rama <- NA_character_
    for (b in split(seq_len(nrow(rows)), rows$punto_rama_id)) {
      fe <- rows$fila_excel[b]
      if (length(b) != 3) add_pend(basename(f), fe[1], paste0("bloque ", rows$punto_rama_id[b[1]], " con ", length(b), " filas de muestra (se esperaban 3)"))
      if (any(duplicated(rows$muestra_num[b]))) add_pend(basename(f), fe[1], paste0("bloque ", rows$punto_rama_id[b[1]], ": muestra repetida"))
      roles <- unique(na.omit(rows$rol_fila[b])); roles <- roles[roles != ""]
      if (length(roles) == 1) rows$rol_planilla[b] <- roles
      else if (length(roles) > 1) { rows$rol_planilla[b] <- paste(roles, collapse = " / "); add_pend(basename(f), fe[1], paste0("bloque ", rows$punto_rama_id[b[1]], ": más de un ROL: ", paste(roles, collapse = " / "))) }
      else add_pend(basename(f), fe[1], paste0("bloque ", rows$punto_rama_id[b[1]], ": sin ROL"))
      n1 <- rows$nombre_fila[b][rows$muestra_num[b] == "1"]; n2 <- rows$nombre_fila[b][rows$muestra_num[b] == "2"]; n3 <- rows$nombre_fila[b][rows$muestra_num[b] == "3"]
      rows$nombre_camino[b]  <- if (length(n1)) n1[1] else NA
      rows$nombre_rama[b]    <- if (length(n2)) n2[1] else NA
      rows$ubicacion_rama[b] <- if (length(n3)) n3[1] else NA
      rs <- max(fe) + 1
      rv <- if (rs <= nrow(d)) as.character(unlist(d[rs, ])) else character()
      # la etiqueta "Transito Medio Diario Anual" está en una columna distinta a
      # NOMBRE (col 4 en las planillas revisadas); se busca en toda la fila.
      if (length(rv) && any(grepl("Transito Medio Diario Anual", rv, ignore.case = TRUE), na.rm = TRUE)) {
        rows$tmda_anual[b] <- suppressWarnings(as.numeric(d[[col_rol]][rs]))
        tc <- which(grepl("Tasa", rv))
        if (length(tc) && tc[1] < length(rv)) rows$tasa_crecimiento[b] <- suppressWarnings(as.numeric(rv[tc[1] + 1]))
        for (k in names(col_comp)) { p <- comp_cols[[k]]; if (p %in% pct_names) rows[[paste0("pct_", p)]][b] <- suppressWarnings(as.numeric(rv[col_comp[[k]]])) }
        if (is.na(rows$tmda_anual[b[1]])) add_pend(basename(f), rs, paste0("bloque ", rows$punto_rama_id[b[1]], ": fila resumen sin TMDA numérico"))
      } else {
        add_pend(basename(f), max(fe), paste0("bloque ", rows$punto_rama_id[b[1]], ": sin fila resumen 'Transito Medio Diario Anual'"))
      }
    }
    # km en texto de cualquiera de los tres nombres del bloque
    km_src <- ifelse(grepl("KM|MTS", rows$ubicacion_rama, ignore.case = TRUE), rows$ubicacion_rama,
              ifelse(grepl("KM|MTS", rows$nombre_rama, ignore.case = TRUE), rows$nombre_rama,
              ifelse(grepl("KM|MTS", rows$nombre_camino, ignore.case = TRUE), rows$nombre_camino, NA)))
    rows$km_texto <- km_src
    km_m <- regmatches(km_src, regexpr("KM[ .]*[0-9]+([.,][0-9]+)?", km_src, ignore.case = TRUE))
    km_val <- rep(NA_real_, nrow(rows))
    has_km <- !is.na(km_src) & grepl("KM[ .]*[0-9]", km_src, ignore.case = TRUE)
    km_val[has_km] <- suppressWarnings(as.numeric(gsub(",", ".", sub("KM[ .]*", "", km_m, ignore.case = TRUE))))
    mts <- !is.na(km_src) & !has_km & grepl("[0-9]+ *MTS", km_src, ignore.case = TRUE)
    mts_m <- regmatches(km_src, regexpr("[0-9]+([.,][0-9]+)? *MTS", km_src, ignore.case = TRUE))
    km_val[mts] <- suppressWarnings(as.numeric(gsub(",", ".", sub(" *MTS", "", mts_m, ignore.case = TRUE)))) / 1000
    rows$km_planilla <- km_val
    bad_mu <- !rows$muestra_literal %in% names(map_muestra)
    for (i in which(bad_mu)) add_pend(basename(f), rows$fila_excel[i], paste0("valor de MUESTRA no reconocido: '", rows$muestra_literal[i], "'"))
    rows$muestra <- unname(map_muestra[rows$muestra_literal])
    rows$anio <- anio
    rows$region_planilla <- region_planilla
    rows$archivo_origen <- basename(f); rows$hoja <- s
    rows$generacion <- ifelse(grepl("^PNCV2025", basename(f)), "PNCV2025", "Region/PlanNacional-2024")
    out[[s]] <- rows
  }
  bind_rows(out)
}

fs <- list.files(dir_xls, pattern = "\\.xls$", full.names = TRUE)
stopifnot(length(fs) == 16)
pl <- bind_rows(lapply(fs, leer_planilla))
pl$tmda <- pl$total_rama
pl$fuente <- "FT-02"; pl$fecha_descarga <- fecha_descarga; pl$metodo <- "declarado"
pl <- pl %>% select(
  archivo_origen, hoja, generacion, fila_excel, region_planilla, region_codigo, anio,
  codigo_planilla, punto_censal_id, rama, punto_rama_id, rol_planilla, rol_fila,
  nombre_punto = nombre_camino, nombre_rama, ubicacion_rama, nombre_fila,
  km_texto, km_planilla, estacion_asimilable,
  muestra_literal, muestra, tmda, tmda_anual, tasa_crecimiento,
  any_of(unname(comp_cols)), starts_with("pct_"), fuente, fecha_descarga, metodo) %>%
  arrange(archivo_origen, fila_excel)
write_parquet(pl, file.path(dir_out, "a5_puntos_censales_planilla.parquet"))

# ---- REST de respaldo -------------------------------------------------------
leer_rest <- function(fj) {
  j <- fromJSON(fj, simplifyVector = TRUE)
  if (is.null(j$features) || !length(j$features)) return(NULL)
  a <- j$features$attributes; g <- j$features$geometry
  names(a) <- chartr("ÑÓ", "NO", toupper(names(a)))   # AÑO -> ANO, REGIÓN -> REGION
  a$lon <- g$x; a$lat <- g$y
  a$capa_rest <- as.integer(sub("layer_([0-9]+)_p.*", "\\1", basename(fj)))
  a$archivo_origen <- basename(fj)
  a
}
rest <- bind_rows(lapply(list.files(dir_rest, pattern = "^layer_[0-9]+_p[0-9]+\\.json$", full.names = TRUE), leer_rest))
# ESTACION_DE_CONTROL viene mayoritariamente como "RR-EEE" pero 7 estaciones
# vienen sin relleno ("02-82"). NUMERO coincide con el sufijo en todos los casos,
# así que el id se normaliza a "RR-" + NUMERO en 3 dígitos; el literal se conserva.
reg_pref <- sub("-.*$", "", trimws(rest$ESTACION_DE_CONTROL))
id_norm <- ifelse(!is.na(rest$NUMERO) & grepl("^[0-9]{2}$", reg_pref),
                  sprintf("%s-%03d", reg_pref, rest$NUMERO), trimws(rest$ESTACION_DE_CONTROL))
rest_long <- bind_rows(lapply(1:4, function(k) {
  data.frame(
    objectid = rest$OBJECTID, globalid = rest$GLOBALID, capa_rest = rest$capa_rest,
    punto_censal_id = id_norm, estacion_de_control_literal = rest$ESTACION_DE_CONTROL, numero = rest$NUMERO,
    asim_estacion = rest$ASIM_ESTACION, rama_rest = k,
    rol_rest = rest[[paste0("ROL_RAMA_", k)]], nombre_rest = rest[[paste0("NOMBRE_RAMA_", k)]],
    tmda_rest = rest[[paste0("TMDA_RAMA_", k)]],
    anio = rest$ANO, zona = rest$ZONA, comuna = rest$COMUNA, provincia = rest$PROVINCIA,
    region = rest$REGION, lon = rest$lon, lat = rest$lat,
    archivo_origen = rest$archivo_origen, stringsAsFactors = FALSE)
})) %>%
  filter(!is.na(rol_rest), rol_rest != "-", rol_rest != "") %>%
  mutate(fuente = "FT-02", fecha_descarga = fecha_descarga, metodo = "declarado",
         epsg = 4326L) %>%
  arrange(capa_rest, objectid, rama_rest)
write_parquet(rest_long, file.path(dir_out, "a5_puntos_censales_rest.parquet"))

# ---- vacíos y resumen ------------------------------------------------------
pend_df <- if (length(pend)) bind_rows(pend) else
  data.frame(archivo = character(), fila_excel = integer(), motivo = character(), agente = character(), fecha = character())
write.csv(pend_df, file.path(dir_out, "vacios_a5_prep.csv"), row.names = FALSE, fileEncoding = "UTF-8")

# resumen por planilla (lo usa el manifest A5.json para n_registros)
resumen <- pl %>% group_by(archivo_origen, hoja, generacion, anio) %>%
  summarise(n_filas = n(), n_estaciones = n_distinct(punto_censal_id),
            n_estacion_rama = n_distinct(punto_rama_id), .groups = "drop")
write.csv(resumen, file.path(dir_out, "a5_prep_resumen_planillas.csv"), row.names = FALSE, fileEncoding = "UTF-8")

cat("Planilla: filas", nrow(pl), "| estaciones", n_distinct(pl$punto_censal_id),
    "| estacion-rama", n_distinct(pl$punto_rama_id), "| años", paste(sort(unique(pl$anio)), collapse = ","),
    "| muestras", paste(names(table(pl$muestra_literal)), table(pl$muestra_literal), collapse = " "), "\n")
cat("  NA tmda:", sum(is.na(pl$tmda)), "| NA tmda_anual:", sum(is.na(pl$tmda_anual)), "| NA rol:", sum(is.na(pl$rol_planilla)),
    "| km_planilla no NA:", sum(!is.na(pl$km_planilla)), "\n")
cat("REST: puntos", nrow(rest), "| filas rama", nrow(rest_long), "| estaciones", n_distinct(rest_long$punto_censal_id),
    "| años", paste(sort(unique(rest_long$anio)), collapse = ","), "\n")
cat("Vacíos prep:", nrow(pend_df), "\n")
