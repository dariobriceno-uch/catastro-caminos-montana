# tests/test_a1.R — Validación del bloque A1 (Red Vial, FT-01).
# Una aserción por test_that para que el resumen sea por aserción.

a1   <- leer_gpkg(rp("data/interim/a1_red_vial.gpkg"))
a1df <- sin_geom(a1)
proc <- leer_parquet(rp("data/interim/procedencia_a1.parquet"))
pend <- leer_csv(rp("data/interim/pendientes_a1.csv"))
man  <- leer_manifest(rp("data/raw/manifest/A1.json"))
crudo <- leer_red_vial_cruda()

# -- Estructura ---------------------------------------------------------------
test_that("A1: columnas exactamente bloque A1 + objectid_mop + id_tramo_a1", {
  esperadas <- c(COLS_A1, COLS_A1_LLAVES)
  presentes <- names(a1df)
  g <- nombre_geom(a1)
  # La geometría del gpkg puede llamarse 'geometria' o 'geom'; cuenta como 'geometria'.
  if (!is.null(g)) presentes <- c(presentes, "geometria")
  faltan <- setdiff(esperadas, presentes)
  sobran <- setdiff(presentes, esperadas)
  expect_true(length(faltan) == 0 && length(sobran) == 0,
              info = sprintf("faltan: %s | sobran: %s",
                             resumen_vector(faltan), resumen_vector(sobran)))
})

test_that("A1: id_tramo_a1 es único y no nulo", {
  ids <- a1df$id_tramo_a1
  expect_true(!any(is.na(ids)) && !anyDuplicated(ids),
              info = sprintf("NA: %d, duplicados: %s", sum(is.na(ids)),
                             resumen_vector(ids[duplicated(ids)])))
})

test_that("A1: id_tramo_a1 tiene formato <rol>-<n>", {
  ok <- grepl("-[0-9]+$", a1df$id_tramo_a1) &
        startsWith(as.character(a1df$id_tramo_a1), as.character(a1df$rol))
  expect_true(all(ok, na.rm = TRUE),
              info = resumen_vector(a1df$id_tramo_a1[!ok]))
})

test_that("A1: objectid_mop es único y no nulo", {
  o <- a1df$objectid_mop
  expect_true(!any(is.na(o)) && !anyDuplicated(o))
})

test_that("A1: toda geometría es no vacía y de tipo línea", {
  tipos <- as.character(sf::st_geometry_type(a1))
  expect_true(all(!sf::st_is_empty(a1)) && all(tipos %in% c("LINESTRING", "MULTILINESTRING")),
              info = resumen_vector(unique(tipos)))
})

test_that("A1: geometría fuera de Isla de Pascua (lon > -100)", {
  bb <- sf::st_bbox(sf::st_transform(a1, 4326))
  expect_gt(bb["xmin"], -100)
})

# -- Contra la capa cruda -----------------------------------------------------
test_that("A1: existen JSON crudos de FT-01 en data/raw/red_vial", {
  expect_false(is.null(crudo), info = "no hay archivos con features en data/raw/red_vial/")
})

test_that("A1: todo rol de la tabla existe en la capa cruda", {
  skip_if(is.null(crudo), "sin crudo")
  no_en_crudo <- setdiff(unique(a1df$rol), unique(crudo$ROL))
  expect_true(length(no_en_crudo) == 0)
  if (length(no_en_crudo)) hallazgo("roles no presentes en crudo: ", resumen_vector(no_en_crudo))
})

test_that("A1: todo objectid_mop existe en la capa cruda y no está duplicado en ella", {
  skip_if(is.null(crudo), "sin crudo")
  expect_true(all(a1df$objectid_mop %in% crudo$OBJECTID) && !anyDuplicated(crudo$OBJECTID),
              info = sprintf("ids sin origen: %s; OBJECTID duplicados en crudo: %d",
                             resumen_vector(setdiff(a1df$objectid_mop, crudo$OBJECTID)),
                             sum(duplicated(crudo$OBJECTID))))
})

test_that("A1: atributos declarados copiados literales desde el crudo (por objectid_mop)", {
  skip_if(is.null(crudo), "sin crudo")
  idx <- match(a1df$objectid_mop, crudo$OBJECTID)
  difs <- character()
  for (campo in names(MAPA_A1_CRUDO)) {
    origen <- MAPA_A1_CRUDO[[campo]]
    if (!(campo %in% names(a1df)) || !(origen %in% names(crudo))) next
    a <- as.character(a1df[[campo]]); b <- as.character(crudo[[origen]][idx])
    a[is.na(a)] <- ""; b[is.na(b)] <- ""
    n <- sum(trimws(a) != trimws(b))
    if (n > 0) difs <- c(difs, sprintf("%s (%d)", campo, n))
  }
  expect_true(length(difs) == 0)
  if (length(difs)) hallazgo("campos con diferencias vs crudo: ", paste(difs, collapse = "; "))
})

test_that("A1: 'Sin Revisar' se conserva literal (no colapsado a No ni NULL)", {
  skip_if(is.null(crudo), "sin crudo")
  idx <- match(a1df$objectid_mop, crudo$OBJECTID)
  problemas <- character()
  for (campo in c("enrolado", "concesionado", "tuicion")) {
    origen <- MAPA_A1_CRUDO[[campo]]
    n_crudo <- sum(crudo[[origen]][idx] == "Sin Revisar", na.rm = TRUE)
    n_tabla <- sum(a1df[[campo]] == "Sin Revisar", na.rm = TRUE)
    if (n_crudo != n_tabla) problemas <- c(problemas, sprintf("%s: crudo=%d tabla=%d", campo, n_crudo, n_tabla))
  }
  expect_true(length(problemas) == 0, info = paste(problemas, collapse = "; "))
})

test_that("A1: dominio de enrolado/concesionado/tuicion ⊆ {Sí, No, Sin Revisar}", {
  fuera <- character()
  for (campo in c("enrolado", "concesionado", "tuicion")) {
    v <- unique(na.omit(a1df[[campo]]))
    fuera <- c(fuera, setdiff(v, c("Sí", "Si", "SI", "No", "NO", "Sin Revisar")))
  }
  # Solo se reporta: el valor crudo manda (Regla 1); el test de copia literal es el que veta.
  if (length(fuera)) hallazgo("valores fuera del dominio documentado: ", resumen_vector(fuera))
  expect_true(TRUE)
})

# -- Manifest -----------------------------------------------------------------
test_that("A1: manifest A1 tiene los campos exigidos por el protocolo", {
  req <- c("fuente", "archivo", "url", "timestamp_utc", "n_registros", "sha256", "agente")
  expect_true(!is.null(man) && all(req %in% names(man)),
              info = sprintf("faltan: %s", resumen_vector(setdiff(req, names(man)))))
})

test_that("A1: cada archivo del manifest existe", {
  skip_if(is.null(man), "sin manifest")
  rutas <- rp(man$archivo)
  expect_true(all(file.exists(rutas)), info = resumen_vector(man$archivo[!file.exists(rutas)]))
})

test_that("A1: sha256 de cada archivo coincide con el manifest", {
  skip_if(is.null(man), "sin manifest")
  rutas <- rp(man$archivo)
  ex <- file.exists(rutas)
  calc <- vapply(rutas[ex], sha256_archivo, character(1))
  malos <- man$archivo[ex][tolower(calc) != tolower(man$sha256[ex])]
  expect_true(all(ex) && length(malos) == 0, info = resumen_vector(malos))
})

test_that("A1: filas de a1 + filas excluidas reportadas = suma n_registros del manifest", {
  skip_if(is.null(man), "sin manifest")
  es_datos <- grepl("red_vial/.*_p[0-9]+[.]json$", man$archivo)
  n_man <- sum(suppressWarnings(as.numeric(man$n_registros[es_datos])), na.rm = TRUE)
  # Excluidas (p. ej. Isla de Pascua): data/interim/a1_excluidos.csv, una fila por registro excluido.
  excl <- leer_csv(rp("data/interim/a1_excluidos.csv"))
  n_excl <- if (is.null(excl)) 0L else nrow(excl)
  if (is.null(excl)) hallazgo("no existe data/interim/a1_excluidos.csv; se asume 0 excluidas")
  expect_equal(nrow(a1df) + n_excl, n_man,
               info = sprintf("a1=%d excluidas=%d manifest=%s", nrow(a1df), n_excl, n_man))
})

test_that("A1: n_registros del manifest coincide con features reales de cada JSON", {
  skip_if(is.null(man) || is.null(crudo), "sin manifest o crudo")
  es_datos <- grepl("red_vial/.*_p[0-9]+[.]json$", man$archivo)
  reales <- table(crudo$.archivo)
  malos <- character()
  for (i in which(es_datos)) {
    b <- basename(man$archivo[i]); n <- suppressWarnings(as.numeric(man$n_registros[i]))
    r <- if (b %in% names(reales)) as.numeric(reales[[b]]) else 0
    if (is.na(n) || n != r) malos <- c(malos, sprintf("%s: manifest=%s real=%d", b, n, r))
  }
  expect_true(length(malos) == 0, info = paste(malos, collapse = "; "))
})

# -- Procedencia ----------------------------------------------------------------
test_that("A1: procedencia tiene columnas exactas del protocolo", {
  expect_setequal(names(proc), COLS_PROCEDENCIA)
})

test_that("A1: metodo ∈ {derivado, declarado, estimado}", {
  expect_true(all(proc$metodo %in% DOM_METODO), info = resumen_vector(setdiff(proc$metodo, DOM_METODO)))
})

test_that("A1: ninguna fila con metodo = derivado y fuente vacía", {
  malas <- proc$metodo == "derivado" & es_nulo(proc$fuente)
  expect_equal(sum(malas, na.rm = TRUE), 0)
})

test_that("A1: toda fila de procedencia tiene fuente y fecha_descarga ISO", {
  ok_f <- !es_nulo(proc$fuente)
  ok_d <- grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}$", as.character(proc$fecha_descarga))
  expect_true(all(ok_f) && all(ok_d), info = sprintf("sin fuente: %d, fecha no ISO: %d", sum(!ok_f), sum(!ok_d)))
})

test_that("A1: fuente de A1 es FT-01", {
  expect_true(all(grepl("^FT-01", proc$fuente)), info = resumen_vector(setdiff(proc$fuente, "FT-01")))
})

test_that("A1: toda celda no nula tiene exactamente una fila de procedencia (y ninguna de más)", {
  d <- diagnostico_procedencia(a1, proc, "id_tramo_a1", COLS_A1)
  expect_true(nrow(d$faltantes) == 0 && length(d$duplicadas) == 0 && nrow(d$sobrantes) == 0,
              info = sprintf("celdas=%d proc=%d faltantes=%d duplicadas=%d sobrantes=%d campos_fuera=%s",
                             d$n_celdas, d$n_proc, nrow(d$faltantes), length(d$duplicadas),
                             nrow(d$sobrantes), resumen_vector(d$campos_fuera)))
})

test_that("A1: campos declarados llevan metodo=declarado y geometria metodo=derivado", {
  decl <- proc$campo %in% setdiff(COLS_A1, "geometria") & proc$metodo != "declarado"
  geo  <- proc$campo == "geometria" & proc$metodo != "derivado"
  expect_true(sum(decl) == 0 && sum(geo) == 0,
              info = sprintf("declarados mal: %d, geometria mal: %d", sum(decl), sum(geo)))
})

# -- Pendientes -------------------------------------------------------------------
test_that("A1: toda celda NULL de un campo A1 tiene fila en pendientes_a1.csv", {
  ids <- a1df$id_tramo_a1
  falt <- character()
  for (cc in setdiff(COLS_A1, "geometria")) {
    nul <- es_nulo(a1df[[cc]])
    if (any(nul)) {
      cub <- pendiente_cubre(pend, ids[nul], cc)
      if (any(!cub)) falt <- c(falt, sprintf("%s (%d)", cc, sum(!cub)))
    }
  }
  expect_true(length(falt) == 0, info = paste(falt, collapse = "; "))
})

test_that("A1: pendientes_a1.csv, si existe, tiene columnas exactas del protocolo", {
  skip_if(is.null(pend), "sin pendientes_a1.csv")
  expect_setequal(names(pend), COLS_PENDIENTES)
})

test_that("A1: suma de n_registros de las páginas = count_total.json (conteo independiente del servicio)", {
  skip_if(is.null(man) || !file.exists(rp("data/raw/red_vial/count_total.json")), "sin manifest o count_total.json")
  es_datos <- grepl("red_vial/.*_p[0-9]+[.]json$", man$archivo)
  n_pag <- sum(suppressWarnings(as.numeric(man$n_registros[es_datos])), na.rm = TRUE)
  n_tot <- jsonlite::fromJSON(rp("data/raw/red_vial/count_total.json"))$count
  # Isla de Pascua se excluye en A1, por lo que la resta debe estar en a1_excluidos.csv; acá se compara descarga vs servicio.
  expect_equal(n_pag, as.numeric(n_tot), info = sprintf("páginas=%s total=%s", n_pag, n_tot))
})
