# tests/test_a2.R — Validación del bloque A2 (subdivisión de tramos).

a2   <- leer_gpkg(rp("data/interim/a2_tramos.gpkg"))
a2df <- sin_geom(a2)
a1   <- leer_gpkg(rp("data/interim/a1_red_vial.gpkg"))
a1df <- sin_geom(a1)
proc <- leer_parquet(rp("data/interim/procedencia_a2.parquet"))
pend <- leer_csv(rp("data/interim/vacios_a2.csv"))

test_that("A2: columnas requeridas presentes (id_tramo, id_tramo_a1, bloque A2)", {
  req <- c("id_tramo", "id_tramo_a1", COLS_A2)
  expect_true(all(req %in% names(a2df)), info = resumen_vector(setdiff(req, names(a2df))))
})

test_that("A2: no escribe columnas de otros bloques (A3/A4/A5/ORQ)", {
  ajenas <- intersect(names(a2df), c(COLS_A3, COLS_A4, COLS_A5, "en_lista_colega"))
  expect_true(length(ajenas) == 0, info = resumen_vector(ajenas))
})

test_that("A2: id_tramo es único y no nulo", {
  ids <- a2df$id_tramo
  expect_true(!any(es_nulo(ids)) && !anyDuplicated(ids), info = resumen_vector(ids[duplicated(ids)]))
})

test_that("A2: todo id_tramo_a1 de A1 aparece al menos una vez", {
  falt <- setdiff(a1df$id_tramo_a1, a2df$id_tramo_a1)
  expect_true(length(falt) == 0, info = resumen_vector(falt))
})

test_that("A2: todo id_tramo_a1 de A2 existe en A1", {
  huer <- setdiff(a2df$id_tramo_a1, a1df$id_tramo_a1)
  expect_true(length(huer) == 0, info = resumen_vector(huer))
})

test_that("A2: utm_zona ∈ {18, 19}", {
  expect_true(all(a2df$utm_zona %in% DOM_UTM), info = resumen_vector(setdiff(a2df$utm_zona, DOM_UTM)))
})

test_that("A2: longitud_calc_m > 0 en toda fila", {
  expect_true(all(!is.na(a2df$longitud_calc_m) & a2df$longitud_calc_m > 0),
              info = sprintf("NA: %d, <=0: %d", sum(is.na(a2df$longitud_calc_m)),
                             sum(a2df$longitud_calc_m <= 0, na.rm = TRUE)))
})

test_that("A2: motivo_corte en dominio", {
  expect_true(all(a2df$motivo_corte %in% DOM_MOTIVO_CORTE),
              info = resumen_vector(setdiff(a2df$motivo_corte, DOM_MOTIVO_CORTE)))
})

test_that("A2: subdividido no nulo (booleano)", {
  expect_true(all(!is.na(a2df$subdividido)) && is.logical(as.logical(a2df$subdividido)))
})

test_that("A2: subdividido = FALSE ⇒ id_tramo == id_tramo_a1", {
  s <- !as.logical(a2df$subdividido)
  malos <- a2df$id_tramo[s][a2df$id_tramo[s] != a2df$id_tramo_a1[s]]
  expect_true(length(malos) == 0, info = resumen_vector(malos))
})

test_that("A2: subdividido = FALSE ⇒ motivo_corte == 'original'", {
  s <- !as.logical(a2df$subdividido)
  expect_true(all(a2df$motivo_corte[s] == "original"),
              info = resumen_vector(a2df$id_tramo[s][a2df$motivo_corte[s] != "original"]))
})

test_that("A2: subdividido = TRUE ⇒ id_tramo tiene formato <id_tramo_a1>-<k> y motivo != original", {
  s <- as.logical(a2df$subdividido)
  # Evaluación fila a fila (grepl con vector de patrones solo usa el primero).
  ok <- startsWith(a2df$id_tramo[s], paste0(a2df$id_tramo_a1[s], "-")) &
        grepl("-[0-9]+$", a2df$id_tramo[s]) & a2df$motivo_corte[s] != "original"
  expect_true(all(ok), info = resumen_vector(a2df$id_tramo[s][!ok]))
})

test_that("A2: suma de longitud_calc_m de hijos ≈ longitud del padre (±1 %)", {
  s <- as.logical(a2df$subdividido)
  skip_if(!any(s), "no hay tramos subdivididos")
  hijos <- aggregate(longitud_calc_m ~ id_tramo_a1, data = a2df[s, ], FUN = sum)
  zona  <- aggregate(utm_zona ~ id_tramo_a1, data = a2df[s, ], FUN = function(z) z[1])
  hijos <- merge(hijos, zona, by = "id_tramo_a1")
  padres <- a1[match(hijos$id_tramo_a1, a1df$id_tramo_a1), ]
  lp <- numeric(nrow(hijos))
  for (z in unique(hijos$utm_zona)) {
    i <- hijos$utm_zona == z
    lp[i] <- as.numeric(sf::st_length(sf::st_transform(padres[i, ], 32700 + as.integer(z))))
  }
  delta <- abs(hijos$longitud_calc_m - lp) / lp
  malos <- hijos$id_tramo_a1[delta > 0.01]
  expect_true(length(malos) == 0, info = sprintf("%d padres con delta > 1%%: %s", length(malos), resumen_vector(malos)))
})

test_that("A2: longitud_calc_m coincide con la geometría propia proyectada a su utm_zona (±1 %)", {
  lc <- numeric(nrow(a2))
  for (z in unique(a2df$utm_zona[!is.na(a2df$utm_zona)])) {
    i <- which(a2df$utm_zona == z)
    lc[i] <- as.numeric(sf::st_length(sf::st_transform(a2[i, ], 32700 + as.integer(z))))
  }
  delta <- abs(a2df$longitud_calc_m - lc) / pmax(lc, 1)
  malos <- a2df$id_tramo[delta > 0.01]
  expect_true(length(malos) == 0, info = sprintf("%d tramos: %s", length(malos), resumen_vector(malos)))
})

test_that("A2: delta_longitud_pct coherente con km_tramo de A1 cuando ambos existen", {
  km <- a1df$km_tramo[match(a2df$id_tramo_a1, a1df$id_tramo_a1)]
  s <- !as.logical(a2df$subdividido) & !is.na(km) & km > 0 & !is.na(a2df$delta_longitud_pct)
  skip_if(!any(s), "sin filas comparables")
  # km_tramo (KM_TRAMO de FT-01) viene en METROS pese al nombre; se copia literal (esquema A1).
  # Verificado: razón mediana st_length(UTM)/km_tramo = 0,999. Ver aserción de unidad más abajo.
  esperado <- (a2df$longitud_calc_m[s] - km[s]) / km[s] * 100
  malos <- a2df$id_tramo[s][abs(esperado - a2df$delta_longitud_pct[s]) > 0.5]
  expect_true(length(malos) == 0, info = sprintf("%d tramos con delta_longitud_pct inconsistente: %s",
                                         length(malos), resumen_vector(malos)))
})

test_that("A2: unidad de km_tramo es metros (razón mediana longitud_calc_m/km_tramo en [0.9, 1.1])", {
  km <- a1df$km_tramo[match(a2df$id_tramo_a1, a1df$id_tramo_a1)]
  s <- !as.logical(a2df$subdividido) & !is.na(km) & km > 0 & !is.na(a2df$longitud_calc_m)
  skip_if(sum(s) < 10, "sin filas comparables")
  r <- median(a2df$longitud_calc_m[s] / km[s])
  expect_true(r >= 0.9 && r <= 1.1,
              info = sprintf("razón mediana = %.4f (~1000 ⇒ km_tramo en km; ~0.001 ⇒ longitud en km)", r))
})

test_that("A2: coord_inicio y coord_fin no nulos", {
  expect_true(all(!es_nulo(a2df$coord_inicio)) && all(!es_nulo(a2df$coord_fin)))
})

test_that("A2: procedencia — columnas, dominio de metodo, fuente no vacía", {
  ok_cols <- setequal(names(proc), COLS_PROCEDENCIA)
  ok_met  <- all(proc$metodo %in% DOM_METODO)
  ok_fte  <- !any(proc$metodo == "derivado" & es_nulo(proc$fuente))
  expect_true(ok_cols && ok_met && ok_fte,
              info = sprintf("cols=%s metodo=%s fuente=%s", ok_cols, ok_met, ok_fte))
})

test_that("A2: toda celda no nula del bloque A2 tiene exactamente una fila de procedencia", {
  d <- diagnostico_procedencia(a2, proc, "id_tramo", COLS_A2)
  expect_true(nrow(d$faltantes) == 0 && length(d$duplicadas) == 0 && nrow(d$sobrantes) == 0,
              info = sprintf("celdas=%d proc=%d faltantes=%d duplicadas=%d sobrantes=%d campos_fuera=%s",
                             d$n_celdas, d$n_proc, nrow(d$faltantes), length(d$duplicadas),
                             nrow(d$sobrantes), resumen_vector(d$campos_fuera)))
})

test_that("A2: toda celda NULL del bloque A2 tiene fila en vacios_a2.csv", {
  falt <- character()
  for (cc in COLS_A2) {
    nul <- es_nulo(a2df[[cc]])
    if (any(nul)) {
      cub <- vacio_cubre(pend, a2df$id_tramo[nul], cc)
      if (any(!cub)) falt <- c(falt, sprintf("%s (%d)", cc, sum(!cub)))
    }
  }
  expect_true(length(falt) == 0, info = paste(falt, collapse = "; "))
})
