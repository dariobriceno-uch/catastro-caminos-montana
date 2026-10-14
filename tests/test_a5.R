# tests/test_a5.R — Validación del bloque A5 (tránsito, FT-02).

a5   <- leer_parquet(rp("data/interim/a5_transito.parquet"))
a2df <- sin_geom(leer_gpkg(rp("data/interim/a2_tramos.gpkg")))
proc <- leer_parquet(rp("data/interim/procedencia_a5.parquet"))
pend <- leer_csv(rp("data/interim/vacios_a5.csv"))
VIGENCIA_FT02 <- 2025L   # docs/fuentes.md: planillas 2024/2025, REST 2014-2025 (verificado por A5)

test_that("A5: columnas requeridas presentes (id_tramo + bloque A5)", {
  req <- c("id_tramo", COLS_A5)
  expect_true(all(req %in% names(a5)), info = resumen_vector(setdiff(req, names(a5))))
})

test_that("A5: no escribe columnas de otros bloques", {
  ajenas <- intersect(names(a5), c(COLS_A1, COLS_A2, COLS_A3, COLS_A4, "en_lista_colega"))
  expect_true(length(ajenas) == 0, info = resumen_vector(ajenas))
})

test_that("A5: exactamente una fila por id_tramo de A2", {
  expect_true(setequal(a5$id_tramo, a2df$id_tramo) && !anyDuplicated(a5$id_tramo),
              info = sprintf("faltan=%s sobran=%s dup=%d",
                             resumen_vector(setdiff(a2df$id_tramo, a5$id_tramo)),
                             resumen_vector(setdiff(a5$id_tramo, a2df$id_tramo)),
                             sum(duplicated(a5$id_tramo))))
})

test_that("A5: tmda no nulo ⇒ punto_censal_id, tmda_anio, dist_punto_censal_m, match_metodo no nulos", {
  s <- !is.na(a5$tmda)
  falt <- character()
  for (cc in c("punto_censal_id", "tmda_anio", "dist_punto_censal_m", "match_metodo")) {
    n <- sum(es_nulo(a5[[cc]][s]))
    if (n > 0) falt <- c(falt, sprintf("%s (%d)", cc, n))
  }
  expect_true(length(falt) == 0, info = paste(falt, collapse = "; "))
})

test_that("A5: tmda_invierno o tmda_composicion no nulos ⇒ punto_censal_id no nulo", {
  s <- (!is.na(a5$tmda_invierno) | !es_nulo(a5$tmda_composicion)) & es_nulo(a5$punto_censal_id)
  expect_equal(sum(s), 0, info = resumen_vector(a5$id_tramo[s]))
})

test_that("A5: match_metodo en dominio {espacial, rol_kilometraje}", {
  v <- a5$match_metodo[!es_nulo(a5$match_metodo)]
  expect_true(all(v %in% DOM_MATCH), info = resumen_vector(setdiff(v, DOM_MATCH)))
})

test_that("A5: tmda_anio <= 2025 (vigencia verificada FT-02); años mayores se reportan como hallazgo", {
  v <- a5$tmda_anio[!is.na(a5$tmda_anio)]
  mayores <- v[v > VIGENCIA_FT02]
  if (length(mayores)) hallazgo("tmda_anio > ", VIGENCIA_FT02, " en ", length(mayores),
                                " filas (años: ", resumen_vector(sort(unique(mayores))),
                                "). Actualizar vigencia en docs/fuentes.md si la planilla es más nueva.")
  # Veto solo sobre años imposibles; la vigencia se reporta.
  expect_true(all(v >= 1990 & v <= as.integer(format(Sys.Date(), "%Y"))),
              info = resumen_vector(v[!(v >= 1990 & v <= as.integer(format(Sys.Date(), "%Y")))]))
})

test_that("A5: tmda, tmda_invierno >= 0 y enteros cuando no nulos", {
  ok <- all(a5$tmda >= 0, na.rm = TRUE) && all(a5$tmda_invierno >= 0, na.rm = TRUE) &&
        all(a5$tmda == round(a5$tmda), na.rm = TRUE)
  expect_true(ok)
})

test_that("A5: dist_punto_censal_m >= 0 cuando no nulo; distancias > 10 km se reportan", {
  v <- a5$dist_punto_censal_m[!is.na(a5$dist_punto_censal_m)]
  if (any(v > 10000)) hallazgo(sum(v > 10000), " tramos con punto censal a más de 10 km (se conserva, se descarta en análisis)")
  expect_true(all(v >= 0))
})

test_that("A5: match_metodo = espacial ⇒ dist_punto_censal_m no nulo", {
  s <- a5$match_metodo == "espacial" & !is.na(a5$match_metodo)
  expect_true(all(!is.na(a5$dist_punto_censal_m[s])))
})

test_that("A5: procedencia — columnas, dominio de metodo, fuente FT-02", {
  ok_cols <- setequal(names(proc), COLS_PROCEDENCIA)
  ok_met  <- all(proc$metodo %in% DOM_METODO)
  ok_fte  <- all(grepl("^FT-02", proc$fuente))
  expect_true(ok_cols && ok_met && ok_fte,
              info = sprintf("cols=%s metodo=%s fuente=%s (%s)", ok_cols, ok_met, ok_fte, resumen_vector(unique(proc$fuente))))
})

test_that("A5: metodo por campo según esquema", {
  derivados <- c("dist_punto_censal_m", "match_metodo")
  m1 <- proc$campo %in% derivados & proc$metodo != "derivado"
  m2 <- proc$campo %in% setdiff(COLS_A5, derivados) & proc$metodo != "declarado"
  expect_true(sum(m1) + sum(m2) == 0, info = sprintf("derivados mal=%d declarados mal=%d", sum(m1), sum(m2)))
})

test_that("A5: toda celda no nula del bloque A5 tiene exactamente una fila de procedencia", {
  d <- diagnostico_procedencia(a5, proc, "id_tramo", COLS_A5)
  expect_true(nrow(d$faltantes) == 0 && length(d$duplicadas) == 0 && nrow(d$sobrantes) == 0,
              info = sprintf("celdas=%d proc=%d faltantes=%d duplicadas=%d sobrantes=%d campos_fuera=%s",
                             d$n_celdas, d$n_proc, nrow(d$faltantes), length(d$duplicadas),
                             nrow(d$sobrantes), resumen_vector(d$campos_fuera)))
})

test_that("A5: toda celda NULL del bloque A5 tiene fila en vacios_a5.csv", {
  falt <- character()
  for (cc in COLS_A5) {
    nul <- es_nulo(a5[[cc]])
    if (any(nul)) {
      cub <- vacio_cubre(pend, a5$id_tramo[nul], cc)
      if (any(!cub)) falt <- c(falt, sprintf("%s (%d)", cc, sum(!cub)))
    }
  }
  expect_true(length(falt) == 0, info = paste(falt, collapse = "; "))
})
