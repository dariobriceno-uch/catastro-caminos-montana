# Libro de códigos — generado desde data/processed/tramos.parquet, procedencia.parquet y docs/esquema.md.
# No inventa nada: descripciones del esquema, dominios y rangos observados en la tabla final.
suppressWarnings(suppressMessages({library(arrow); library(dplyr)}))
t <- as.data.frame(read_parquet("data/processed/tramos.parquet"))
t$geometria <- NULL
pr <- read_parquet("data/processed/procedencia.parquet")
n <- nrow(t)

# --- descripciones desde esquema.md (tablas markdown; primera celda = `columna`) ---
esq <- readLines("docs/esquema.md", encoding = "UTF-8")
bloque <- NA; desc <- list()
for (l in esq) {
  if (grepl("^### Bloque", l)) bloque <- sub("^### Bloque ([A-Z0-9]+).*", "\\1", l)
  if (grepl("^\\| `", l)) {
    cells <- trimws(strsplit(sub("^\\|", "", sub("\\|$", "", l)), "|", fixed = TRUE)[[1]])
    col <- gsub("`", "", cells[1])
    tipo <- cells[if (length(cells) >= 4 && grepl("^`", cells[2])) 3 else 2]
    d <- cells[length(cells)]; if (d == "" && length(cells) > 1) d <- ""
    desc[[col]] <- list(bloque = bloque, tipo = tipo, desc = d, origen = if (grepl("^`", cells[2])) gsub("`", "", cells[2]) else "")
  }
}
unidades <- c(km_inicio="m (literal de la capa)", km_fin="m (literal de la capa)", km_tramo="m (literal de la capa)",
  longitud_calc_m="m", delta_longitud_pct="%", cota_min="msnm", cota_max="msnm", cota_media="msnm", cota_culminante="msnm",
  cota_max_z_mop="msnm", delta_z_m="m", pendiente_media="grados", pendiente_max="grados", desnivel_subida_m="m",
  desnivel_bajada_m="m", dist_limite_m="m", dist_servicios_km="km", buffer_join_m="m", dist_punto_censal_m="m",
  tmda="veh/día", tmda_invierno="veh/día", esqui_cota_base="msnm", sinuosidad="adimensional", utm_zona="zona UTM sur")

fmt <- function(x) format(x, big.mark = ".", decimal.mark = ",", trim = TRUE)
# descripciones en lenguaje llano (docs/descripciones_columnas.csv, separador |) y glosario
dl <- read.delim("docs/descripciones_columnas.csv", sep = "|", quote = "", stringsAsFactors = FALSE, encoding = "UTF-8", fileEncoding = "UTF-8")
glos <- readLines("docs/glosario.md", encoding = "UTF-8")
out <- c("# Libro de códigos — `data/processed/tramos.parquet`", "",
  sprintf("Generado el %s por `src/04_ensamblaje/libro_codigos.R` a partir de la tabla final (%s filas, %d columnas + `geometria`), `procedencia.parquet` y `docs/esquema.md`. Dominios, rangos y conteos son **observados**, no declarados.", format(Sys.Date()), fmt(n), ncol(t)), "",
  "Cada ficha empieza con una explicación en lenguaje llano (qué es la variable, de dónde sale y cómo leerla), pensada para quien no maneja vocabulario geográfico ni conoce las fuentes. Después vienen los datos técnicos: bloque del esquema, campo de origen, procedencia registrada, conteo de vacíos y valores observados.", "",
  glos, "",
  "## Índice", "")
for (col in names(t)) out <- c(out, sprintf("- [`%s`](#%s)", col, gsub("[^a-z0-9]+", "-", tolower(col))))
out <- c(out, "")
for (col in names(t)) {
  x <- t[[col]]; nn <- sum(is.na(x)); e <- desc[[col]]
  p <- pr %>% filter(campo == col) %>% count(fuente, metodo, agente) %>% arrange(desc(n))
  out <- c(out, sprintf("## `%s`", col), "")
  k <- match(col, dl$columna)
  if (!is.na(k)) out <- c(out, sprintf("- **Qué es:** %s", dl$que_es[k]), sprintf("- **De dónde sale:** %s", dl$de_donde_sale[k]), sprintf("- **Cómo leerlo:** %s", dl$como_leerlo[k]))
  out <- c(out, sprintf("- **Bloque:** %s · **Tipo:** %s%s", if (is.null(e)) "ORQ/llave" else e$bloque, if (is.null(e)) class(x)[1] else e$tipo,
                        if (!is.null(e) && e$origen != "") sprintf(" · **Campo origen:** `%s`", e$origen) else ""))
  if (!is.null(e) && nzchar(e$desc)) out <- c(out, sprintf("- **Nota del esquema:** %s", e$desc))
  if (col %in% names(unidades)) out <- c(out, sprintf("- **Unidad:** %s", unidades[[col]]))
  out <- c(out, sprintf("- **Procedencia:** %s", if (nrow(p)) paste(sprintf("%s / %s / %s (%s celdas)", p$fuente, p$metodo, p$agente, fmt(p$n)), collapse = "; ") else "sin filas (llave o columna vacía)"))
  out <- c(out, sprintf("- **Válidos / NULL:** %s / %s (%.1f %% NULL)", fmt(n - nn), fmt(nn), 100 * nn / n))
  if (nn < n) {
    if (is.numeric(x) && !is.logical(x)) {
      q <- quantile(x, c(0, .05, .5, .95, 1), na.rm = TRUE)
      out <- c(out, sprintf("- **Rango:** mín %s · p5 %s · mediana %s · p95 %s · máx %s", fmt(round(q[1], 2)), fmt(round(q[2], 2)), fmt(round(q[3], 2)), fmt(round(q[4], 2)), fmt(round(q[5], 2))))
      if (length(unique(na.omit(x))) <= 12) {
        f <- sort(table(x), decreasing = TRUE)
        out <- c(out, "- **Dominio observado:**", "", "| Valor | n |", "|---|---:|", sprintf("| %s | %s |", names(f), fmt(as.integer(f))), "")
      }
    } else if (is.logical(x)) {
      out <- c(out, sprintf("- **Dominio observado:** TRUE %s · FALSE %s", fmt(sum(x %in% TRUE)), fmt(sum(x %in% FALSE))))
    } else {
      u <- length(unique(na.omit(x)))
      if (u <= 40) {
        f <- sort(table(x), decreasing = TRUE)
        out <- c(out, sprintf("- **Dominio observado (%d valores):**", u), "", "| Valor | n |", "|---|---:|", sprintf("| %s | %s |", gsub("\\|", "\\\\|", names(f)), fmt(as.integer(f))), "")
      } else {
        f <- sort(table(x), decreasing = TRUE)[1:5]
        out <- c(out, sprintf("- **Valores distintos:** %s. Más frecuentes: %s", fmt(u), paste(sprintf("`%s` (%s)", names(f), fmt(as.integer(f))), collapse = ", ")))
      }
    }
  }
  out <- c(out, "")
}
writeLines(out, "docs/libro_codigos.md", useBytes = FALSE)
cat("escrito docs/libro_codigos.md:", length(out), "líneas\\n")
