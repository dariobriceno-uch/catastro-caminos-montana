# tests/test_visor.R — Validación del visor HTML autocontenido.
#
# El visor no deriva nada: solo muestra. Por lo tanto lo único que hay que
# probar es que el payload reproduce el parquet exactamente, que la procedencia
# viaja intacta (Regla 2), que la geometría no se desalinea de las filas, y que
# el archivo no depende de la red.

suppressPackageStartupMessages(library(jsonlite))

tr   <- leer_parquet(rp("data/processed/tramos.parquet"))
proc <- leer_parquet(rp("data/processed/procedencia.parquet"))
P    <- fromJSON(rp("data/interim/visor_payload.json"), simplifyVector = TRUE)
html <- readLines(rp("docs/visor_tramos.html"), warn = FALSE, encoding = "UTF-8")

COLS_TR <- setdiff(names(tr), "geometria")

# --- reconstruye la columna tal como la verá el navegador -------------------
desde_payload <- function(col) {
  t <- P$cols$t[P$cols$n == col]
  v <- P$data[[col]]
  if (t == "dict") {
    d <- P$dicts[[col]]
    ifelse(is.na(v), NA_character_, d[v + 1L])
  } else if (t == "bool") {
    as.logical(v)
  } else {
    v
  }
}

test_that("VISOR: el payload tiene las mismas filas y columnas que el parquet", {
  expect_equal(P$meta$n_tramos, nrow(tr))
  expect_true(setequal(P$cols$n, COLS_TR),
              info = sprintf("faltan: %s | sobran: %s",
                             resumen_vector(setdiff(COLS_TR, P$cols$n)),
                             resumen_vector(setdiff(P$cols$n, COLS_TR))))
})

test_that("VISOR: cada columna del payload reproduce el parquet valor a valor", {
  malas <- character()
  for (col in COLS_TR) {
    o <- tr[[col]]
    p <- desde_payload(col)
    if (length(p) != length(o)) {
      malas <- c(malas, sprintf("%s (largo)", col))
      next
    }
    if (is.numeric(o)) {
      # copia fiel bit a bit: el CSV que exporte el visor tiene que reproducir
      # el parquet, no una versión recortada de él.
      a <- as.numeric(o); b <- as.numeric(p)
      difiere <- !is.na(a) & (is.na(b) | a != b)
    } else {
      difiere <- as.character(o) != as.character(p)
      difiere[is.na(difiere)] <- FALSE
    }
    if (any(difiere)) malas <- c(malas, sprintf("%s (%d valores)", col, sum(difiere)))
  }
  expect_true(length(malas) == 0, info = resumen_vector(malas))
})

test_that("VISOR: los NULL del parquet siguen siendo NULL en el payload", {
  # Falla crítica si el exportador rellena un vacío con 0, texto vacío o un código.
  malas <- character()
  for (col in COLS_TR) {
    o <- es_nulo(tr[[col]])
    p <- is.na(desde_payload(col))
    if (!identical(as.vector(o), as.vector(p)))
      malas <- c(malas, sprintf("%s (parquet %d NULL, payload %d)", col, sum(o), sum(p)))
  }
  expect_true(length(malas) == 0, info = resumen_vector(malas))
})

test_that("VISOR: la procedencia del payload coincide con procedencia.parquet", {
  malas <- character()
  for (campo in unique(proc$campo)) {
    s <- proc[proc$campo == campo, ]
    if (!is.null(P$proc[[campo]])) {
      # campo colapsado a una sola procedencia: sólo es lícito si era constante
      u <- unique(paste(s$fuente, s$fecha_descarga, s$metodo, s$agente))
      if (length(u) != 1) {
        malas <- c(malas, sprintf("%s colapsado con %d combinaciones", campo, length(u)))
        next
      }
      e <- P$proc[[campo]]
      if (!identical(e$fuente, s$fuente[1]) ||
          !identical(e$fecha, as.character(s$fecha_descarga[1])) ||
          !identical(e$metodo, s$metodo[1]) ||
          !identical(e$agente, s$agente[1]))
        malas <- c(malas, sprintf("%s difiere", campo))
    } else if (is.null(P$proc_var[[campo]])) {
      malas <- c(malas, sprintf("%s ausente del payload", campo))
    }
  }
  expect_true(length(malas) == 0, info = resumen_vector(malas))
})

test_that("VISOR: el método declarado está en el dominio de la Regla 2", {
  metodos <- unlist(lapply(P$proc, function(e) e$metodo))
  expect_true(all(metodos %in% DOM_METODO),
              info = resumen_vector(setdiff(metodos, DOM_METODO)))
})

test_that("VISOR: la geometría no se desalinea de las filas", {
  g <- P$geom
  expect_equal(length(g$partes_por_tramo), nrow(tr))
  expect_equal(sum(g$verts_por_parte), g$n_vertices)
  expect_equal(length(g$verts_por_parte), sum(g$partes_por_tramo))
  expect_true(all(g$partes_por_tramo >= 1))
  expect_true(all(g$verts_por_parte >= 2))
})

test_that("VISOR: el primer vértice de cada tramo cae sobre coord_inicio", {
  # Detecta un corrimiento de índice entre filas y geometría, que sería el error
  # más difícil de ver a ojo en el mapa.
  g <- P$geom
  starts <- readBin(base64_dec(g$starts_b64), "integer", size = 4,
                    n = sum(g$partes_por_tramo) * 2, endian = "little")
  i0  <- cumsum(c(1L, head(g$partes_por_tramo, -1)))   # primera parte de cada tramo
  lon <- starts[(i0 - 1) * 2 + 1] / g$escala
  lat <- starts[(i0 - 1) * 2 + 2] / g$escala

  wkt <- sub("^POINT\\(", "", sub("\\)$", "", tr$coord_inicio))
  pr  <- do.call(rbind, strsplit(trimws(wkt), "[[:space:]]+"))
  olon <- as.numeric(pr[, 1])
  olat <- as.numeric(pr[, 2])

  # separación en metros; la simplificación a 5 m no mueve los extremos
  dm <- sqrt(((lon - olon) * 111320 * cos(olat * pi / 180))^2 +
             ((lat - olat) * 110540)^2)
  lejos <- which(dm > 25)
  expect_true(length(lejos) == 0,
              info = sprintf("%d tramos con el primer vértice lejos de coord_inicio; peor %.0f m en %s",
                             length(lejos),
                             if (length(lejos)) max(dm[lejos]) else 0,
                             if (length(lejos)) tr$id_tramo[lejos[which.max(dm[lejos])]] else "-"))
})

test_that("VISOR: la extensión del catastro es la de Chile continental", {
  expect_true(all(is.finite(P$bbox)) && length(P$bbox) == 4)
  expect_true(P$bbox[1] > -80 && P$bbox[3] < -60 && P$bbox[2] > -60 && P$bbox[4] < -15,
              info = paste(round(P$bbox, 3), collapse = " "))
})

test_that("VISOR: el HTML es autocontenido — ninguna referencia a la red", {
  cuerpo <- paste(html, collapse = "\n")
  patrones <- c("https?://", "<link[^>]+rel=", "<script[^>]+src=", "@import",
                "fetch[[:space:]]*\\(", "XMLHttpRequest", "importScripts", "//cdn")
  hallados <- character()
  for (pat in patrones) {
    m <- regmatches(cuerpo, gregexpr(pat, cuerpo, perl = TRUE))[[1]]
    if (length(m) > 0) hallados <- c(hallados, sprintf("%s x%d", pat, length(m)))
  }
  expect_true(length(hallados) == 0, info = resumen_vector(hallados))
})

test_that("VISOR: el HTML declara el sha256 del parquet del que salió", {
  cuerpo <- paste(html, collapse = "\n")
  expect_true(grepl('name="fondef-parquet-sha256" content="[0-9a-f]{64}"', cuerpo))
  expect_true(grepl('name="fondef-payload-sha256" content="[0-9a-f]{64}"', cuerpo))
})

test_that("VISOR: ningún diccionario viaja desempaquetado a texto suelto", {
  # Un diccionario de un solo valor serializado como cadena haría que el visor
  # indexara caracteres: mostraría "e" donde la base dice "espacial".
  # una columna 100% NULL tiene diccionario vacío, y eso es legítimo
  largo <- vapply(P$dicts, length, integer(1))
  sueltos <- names(P$dicts)[largo > 0 & !vapply(P$dicts, is.character, logical(1))]
  chr1 <- names(P$dicts)[vapply(P$dicts, function(d) length(d) == 1, logical(1))]
  malas <- character()
  for (col in chr1) {
    u <- sort(unique(tr[[col]][!es_nulo(tr[[col]])]))
    if (!identical(as.character(P$dicts[[col]]), as.character(u)))
      malas <- c(malas, col)
  }
  expect_true(length(sueltos) == 0 && length(malas) == 0,
              info = resumen_vector(c(sueltos, malas)))
})

test_that("VISOR: procedencia.parquet tiene fila si y sólo si el valor no es NULL", {
  # Es el supuesto que permite al visor no mostrar procedencia en una celda
  # vacía. Si dejara de cumplirse, la regla del visor habría que reescribirla.
  malas <- character()
  for (campo in intersect(unique(proc$campo), names(tr))) {
    con_fila <- tr$id_tramo %in% proc$id_tramo[proc$campo == campo]
    con_valor <- !es_nulo(tr[[campo]])
    if (!identical(con_fila, con_valor))
      malas <- c(malas, sprintf("%s (%d descalces)", campo, sum(con_fila != con_valor)))
  }
  expect_true(length(malas) == 0, info = resumen_vector(malas))
})

test_that("VISOR: el HTML incrusta los módulos reales, no los stubs", {
  cuerpo <- paste(html, collapse = "
")
  expect_false(grepl("STUB de", cuerpo, fixed = TRUE),
               info = "el visor entregado es la compilación de los stubs")
  for (m in c("window.Mapa", "window.Tabla", "window.Ficha"))
    expect_true(grepl(m, cuerpo, fixed = TRUE), info = m)
})

test_that("VISOR: el HTML no es más antiguo que los módulos que lo componen", {
  # La comprobación contra el parquet no basta: los módulos cambian después.
  fuentes <- c(list.files(rp("src/04_ensamblaje/visor"), full.names = TRUE),
               rp("src/04_ensamblaje/visor_html.py"),
               rp("data/processed/tramos.parquet"),
               rp("data/interim/visor_payload.json.gz"))
  fuentes <- fuentes[file.exists(fuentes)]
  mas_nuevos <- fuentes[file.mtime(fuentes) > file.mtime(rp("docs/visor_tramos.html"))]
  expect_true(length(mas_nuevos) == 0,
              info = sprintf("hay que reensamblar; más nuevos que el visor: %s",
                             resumen_vector(basename(mas_nuevos))))
})
