# tests/test_a6.R — Validación del bloque A6 (geomorfología, FT-10).

suppressPackageStartupMessages(library(sf))

a6   <- leer_parquet(rp("data/interim/a6_geomorf.parquet"))
a2df <- sin_geom(leer_gpkg(rp("data/interim/a2_tramos.gpkg")))
proc <- leer_parquet(rp("data/interim/procedencia_a6.parquet"))
pend <- leer_csv(rp("data/interim/vacios_a6.csv"))

shp <- list.files(rp("data/raw/Unidades Geomorfologicas"), pattern = "[.]shp$", full.names = TRUE)
crudo <- if (length(shp)) sf::st_drop_geometry(sf::st_read(shp[1], quiet = TRUE)) else NULL

# La tabla de docs/esquema.md, transcrita. Si cambia allá, cambia acá.
VERT_ESQUEMA <- list(
  andina = c("Cordillera prealtiplanica", "Altiplano", "Precordillera rio Lauca",
             "Precordillera rio Loa superior", "Precordillera de Domeyko", "Precordillera",
             "Cordillera andina de retencion crionival", "Cordillera volcanica activa",
             "Precordillera morrenica",
             "Cordillera patagonica de lagos y rios de control tectonico",
             "Cordillera patagonica de fiordos y rios de control tectonico",
             "Cordillera patagonica de ventisqueros del Pacifico", "Cordillera patagonica insular"),
  costera = c("Cordillera de la costa", "Cordillera de la costa con tectonica de hundimiento",
              "Farellon costero", "Planicie marina o fluviomarina",
              "Cuencas graniticas marginales", "Cuenca granitica marginal"),
  transversal = "Cordones transversales")

test_that("A6: columnas requeridas y ninguna ajena", {
  expect_true(all(c("id_tramo", COLS_A6) %in% names(a6)),
              info = resumen_vector(setdiff(c("id_tramo", COLS_A6), names(a6))))
  ajenas <- intersect(names(a6), c(COLS_A1, COLS_A2, COLS_A3, COLS_A4, COLS_A5, "en_lista_colega"))
  expect_true(length(ajenas) == 0, info = resumen_vector(ajenas))
})

test_that("A6: exactamente una fila por id_tramo de A2", {
  expect_true(setequal(a6$id_tramo, a2df$id_tramo) && !anyDuplicated(a6$id_tramo))
})

test_that("A6: unidad_geomorf solo toma valores que existen en la capa cruda FT-10", {
  skip_if(is.null(crudo), "sin capa cruda FT-10")
  fuera <- setdiff(unique(a6$unidad_geomorf[!es_nulo(a6$unidad_geomorf)]), unique(crudo$unidad))
  expect_true(length(fuera) == 0, info = resumen_vector(fuera))
})

test_that("A6: vertiente en dominio y coherente con la tabla de docs/esquema.md", {
  v <- a6$vertiente[!es_nulo(a6$vertiente)]
  expect_true(all(v %in% DOM_VERTIENTE), info = resumen_vector(setdiff(v, DOM_VERTIENTE)))
  ok <- !es_nulo(a6$unidad_geomorf)
  esperada <- rep("otra", sum(ok))
  for (k in names(VERT_ESQUEMA)) esperada[a6$unidad_geomorf[ok] %in% VERT_ESQUEMA[[k]]] <- k
  malas <- which(esperada != a6$vertiente[ok])
  expect_true(length(malas) == 0,
              info = resumen_vector(unique(a6$unidad_geomorf[ok][malas])))
})

test_that("A6: vertiente es NULL si y solo si unidad_geomorf es NULL", {
  expect_true(identical(es_nulo(a6$vertiente), es_nulo(a6$unidad_geomorf)))
})

test_that("A6: n_unidades_geomorf es 0 exactamente cuando unidad_geomorf es NULL", {
  expect_true(all((a6$n_unidades_geomorf == 0) == es_nulo(a6$unidad_geomorf)))
  expect_true(all(a6$n_unidades_geomorf >= 0))
})

test_that("A6: procedencia FT-10 / derivado / A6, una fila por celda con valor", {
  expect_true(all(proc$fuente == "FT-10" & proc$metodo == "derivado" & proc$agente == "A6"))
  for (cn in COLS_A6) {
    con_valor <- a6$id_tramo[!es_nulo(a6[[cn]])]
    expect_true(setequal(proc$id_tramo[proc$campo == cn], con_valor), info = cn)
  }
})

test_that("A6: todo NULL está en vacíos con motivo", {
  nulos <- a6$id_tramo[es_nulo(a6$unidad_geomorf)]
  expect_true(all(nulos %in% pend$id_tramo[pend$campo == "unidad_geomorf"]),
              info = resumen_vector(setdiff(nulos, pend$id_tramo)))
  expect_true(all(nzchar(pend$motivo)))
})

test_that("A6: manifest/A6.json registra FT-10 con sha256 del shapefile", {
  m <- jsonlite::fromJSON(rp("data/raw/manifest/A6.json"))
  expect_true(any(m$fuente == "FT-10"))
  expect_true(all(grepl("^[0-9a-f]{64}$", m$sha256)))
  if (length(shp)) expect_equal(m$sha256[m$fuente == "FT-10"][1],
                                digest::digest(shp[1], algo = "sha256", file = TRUE))
})
