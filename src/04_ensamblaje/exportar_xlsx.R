# ---------------------------------------------------------------------------
# exportar_xlsx.R — versión Excel de data/processed/tramos.parquet
#
# No deriva ni transforma ningún valor: copia la base tal cual. Lo único que
# no viaja es la columna `geometria` (binario WKB, 254 MB), que Excel no puede
# representar; las coordenadas de inicio y fin de cada tramo sí van.
#
# Salida: data/processed/tramos.xlsx  con cuatro hojas
#   tramos        18.368 filas × 63 columnas, NULL = celda vacía
#   procedencia   fuente / fecha / método / agente por campo (Regla 2)
#   diccionario   qué es cada columna, de dónde sale, cómo leerla
#   acerca_de     origen, sha256 del parquet, avisos de lectura
# ---------------------------------------------------------------------------

suppressMessages({library(arrow); library(openxlsx); library(digest)})

PARQUET  <- "data/processed/tramos.parquet"
PROCEDEN <- "data/processed/procedencia.parquet"
DESCRIP  <- "docs/descripciones_columnas.csv"
SALIDA   <- "data/processed/tramos.xlsx"

log_ <- function(...) cat(format(Sys.time(), "%H:%M:%S"), "|", ..., "\n")

# --- 1. tramos --------------------------------------------------------------
log_("leyendo", PARQUET)
d <- read_parquet(PARQUET)
d$geometria <- NULL
n <- nrow(d)
log_("filas:", n, " columnas:", ncol(d))

# --- 2. procedencia por campo ----------------------------------------------
p <- read_parquet(PROCEDEN)
proc <- unique(p[, c("campo", "fuente", "fecha_descarga", "metodo", "agente")])
proc$n_tramos_con_valor <- sapply(seq_len(nrow(proc)), function(i)
  sum(p$campo == proc$campo[i] & p$fuente == proc$fuente[i] &
      p$metodo == proc$metodo[i] & p$agente == proc$agente[i]))
proc <- proc[order(match(proc$campo, names(d))), ]
names(proc) <- c("campo", "fuente", "fecha_descarga", "metodo", "agente",
                 "n_tramos_con_valor")
rownames(proc) <- NULL
log_("procedencia:", nrow(proc), "combinaciones campo/fuente")

# --- 3. diccionario ---------------------------------------------------------
dic <- read.csv(DESCRIP, sep = "|", quote = "\"", stringsAsFactors = FALSE,
                colClasses = "character", encoding = "UTF-8")
dic <- dic[match(names(d), dic$columna), ]
dic$tipo <- sapply(names(d), function(nm) {
  x <- d[[nm]]
  if (is.logical(x)) "lógico" else if (is.numeric(x)) "número" else "texto"
})
dic$n_sin_dato <- sapply(d, function(x) sum(is.na(x)))
dic <- dic[, c("columna", "tipo", "n_sin_dato", "que_es", "de_donde_sale", "como_leerlo")]
rownames(dic) <- NULL

# --- 4. acerca de -----------------------------------------------------------
sha <- digest(PARQUET, algo = "sha256", file = TRUE)
acerca <- data.frame(clave = c(
  "origen", "sha256 del parquet", "generado", "filas", "columnas",
  "celda vacía", "geometría", "km_inicio, km_fin, km_tramo",
  "km_tramo = 0", "km_tramo en tramos subdivididos",
  "unidad de análisis", "porcentajes", "precisión numérica"
), valor = c(
  PARQUET, sha, format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  format(n, big.mark = "."), ncol(d),
  "NULL en la base: el valor no se pudo derivar. Nunca es un cero.",
  "No incluida (binario). Ver coord_inicio y coord_fin, o data/processed/tramos.gpkg.",
  "Están en METROS pese al nombre (docs/esquema.md).",
  "Significa que la fuente no lo informó, no cero metros (2.227 tramos).",
  paste("Es la longitud del tramo ANTES de partirlo por comuna (campo declarado,",
        "no se recalcula). La longitud de la fila está en longitud_calc_m.",
        "Sumar km_tramo por rol cuenta el mismo camino más de una vez."),
  "La fila es el tramo, no el camino. Un rol aparece en varias filas.",
  "Un porcentaje calculado sobre un filtro de esta tabla no es un porcentaje nacional.",
  paste("Excel conserva 15 cifras significativas; el parquet guarda 17. La diferencia",
        "está en la 15ª cifra (error relativo < 1e-14). El valor de referencia es el parquet.")
), stringsAsFactors = FALSE)

# --- 5. escribir ------------------------------------------------------------
log_("escribiendo", SALIDA)
wb <- createWorkbook()
cab <- createStyle(fontName = "Calibri", fontSize = 10, textDecoration = "bold",
                   fgFill = "#E7E6E6", border = "bottom")
for (h in list(list("tramos", d), list("procedencia", proc),
               list("diccionario", dic), list("acerca_de", acerca))) {
  addWorksheet(wb, h[[1]])
  writeData(wb, h[[1]], h[[2]], headerStyle = cab, na.string = "",
            withFilter = h[[1]] %in% c("tramos", "procedencia", "diccionario"))
  freezePane(wb, h[[1]], firstRow = TRUE)
}
setColWidths(wb, "tramos", cols = seq_along(d), widths = "auto")
setColWidths(wb, "diccionario", cols = 4:6, widths = 60)
setColWidths(wb, "acerca_de", cols = 1:2, widths = c(32, 100))
addStyle(wb, "diccionario", createStyle(wrapText = TRUE, valign = "top"),
         rows = 2:(nrow(dic) + 1), cols = 4:6, gridExpand = TRUE)
addStyle(wb, "acerca_de", createStyle(wrapText = TRUE, valign = "top"),
         rows = 2:(nrow(acerca) + 1), cols = 2, gridExpand = TRUE)
saveWorkbook(wb, SALIDA, overwrite = TRUE)
log_("escrito", SALIDA, round(file.size(SALIDA) / 1e6, 1), "MB")

# --- 6. verificación de ida y vuelta ----------------------------------------
log_("verificando: releyendo el xlsx y comparando contra el parquet")
r <- read.xlsx(SALIDA, sheet = "tramos", na.strings = "")
stopifnot(nrow(r) == n, identical(names(r), names(d)))
malas <- character()
for (nm in names(d)) {
  o <- d[[nm]]; x <- r[[nm]]
  if (!identical(is.na(o), is.na(x))) { malas <- c(malas, paste0(nm, " (NULL)")); next }
  # Excel guarda 15 cifras significativas por diseño (el double tiene 17):
  # 386.61372913666992 queda como 386.61372913666997. Se admite sólo eso.
  ok <- if (is.numeric(o)) all(is.na(o) | abs(as.numeric(o) - as.numeric(x)) <= abs(o) * 1e-14)
        else if (is.logical(o)) all(is.na(o) | o == as.logical(x))
        else all(is.na(o) | as.character(o) == as.character(x))
  if (!ok) malas <- c(malas, nm)
}
if (length(malas)) stop("columnas que no reproducen el parquet: ", paste(malas, collapse = ", "))
log_("las", ncol(d), "columnas reproducen el parquet (números a 15 cifras, límite de Excel), NULL incluidos")
