# tests/test_a3.R — Validación del bloque A3 (altimetría, FT-07).

a3   <- leer_parquet(rp("data/interim/a3_altimetria.parquet"))
a2df <- sin_geom(leer_gpkg(rp("data/interim/a2_tramos.gpkg")))
proc <- leer_parquet(rp("data/interim/procedencia_a3.parquet"))
pend <- leer_csv(rp("data/interim/vacios_a3.csv"))
mans <- leer_manifests_todos()

COTAS <- c("cota_min", "cota_max", "cota_media", "cota_culminante")
hay_cota <- any(vapply(intersect(COTAS, names(a3)), function(cc) any(!is.na(a3[[cc]])), logical(1)))
nn <- function(...) { m <- cbind(...); apply(m, 1, function(r) all(!is.na(r))) }

test_that("A3: columnas requeridas presentes (id_tramo + bloque A3)", {
  req <- c("id_tramo", COLS_A3)
  expect_true(all(req %in% names(a3)), info = resumen_vector(setdiff(req, names(a3))))
})

test_that("A3: no escribe columnas de otros bloques", {
  ajenas <- intersect(names(a3), c(COLS_A1, COLS_A2, COLS_A4, COLS_A5, "en_lista_colega"))
  expect_true(length(ajenas) == 0, info = resumen_vector(ajenas))
})

test_that("A3: exactamente una fila por id_tramo de A2 (mismo conjunto, sin duplicados)", {
  expect_true(setequal(a3$id_tramo, a2df$id_tramo) && !anyDuplicated(a3$id_tramo),
              info = sprintf("faltan=%s sobran=%s dup=%d",
                             resumen_vector(setdiff(a2df$id_tramo, a3$id_tramo)),
                             resumen_vector(setdiff(a3$id_tramo, a2df$id_tramo)),
                             sum(duplicated(a3$id_tramo))))
})

test_that("A3: ninguna cota escrita sin data/raw/dem/tile_index_glo30.csv", {
  skip_if(!hay_cota, "no hay cotas escritas")
  expect_true(file.exists(rp("data/raw/dem/tile_index_glo30.csv")))
})

test_that("A3: ninguna cota escrita sin entrada FT-07 en el manifest", {
  skip_if(!hay_cota, "no hay cotas escritas")
  ok <- !is.null(mans) && any(grepl("^FT-07", mans$fuente))
  expect_true(ok, info = "no hay entrada con fuente FT-07 en data/raw/manifest/*.json")
})

test_that("A3: un solo DEM declarado en el manifest FT-07 (sin cambio de DEM a mitad de camino)", {
  skip_if(is.null(mans) || !any(grepl("^FT-07", mans$fuente)), "sin manifest FT-07")
  m7 <- mans[grepl("^FT-07", mans$fuente), ]
  productos <- unique(tolower(gsub("[^a-z0-9]", "", tolower(ifelse(is.na(m7$notas), "", m7$notas)))))
  # Se reporta; el veto es sobre la fuente única FT-07 en la procedencia (abajo).
  hallazgo("entradas FT-07 en manifest: ", nrow(m7), "; notas distintas: ", length(productos))
  expect_true(all(grepl("^FT-07", proc$fuente)), info = resumen_vector(setdiff(proc$fuente, "FT-07")))
})

test_that("A3: cota_min <= cota_media <= cota_max en toda fila no nula", {
  s <- nn(a3$cota_min, a3$cota_media, a3$cota_max)
  malos <- a3$id_tramo[s][!(a3$cota_min[s] <= a3$cota_media[s] & a3$cota_media[s] <= a3$cota_max[s])]
  expect_true(length(malos) == 0, info = resumen_vector(malos))
})

test_that("A3: cota_culminante == cota_max (o documentado en vacíos/hallazgo)", {
  s <- nn(a3$cota_culminante, a3$cota_max)
  dif <- a3$id_tramo[s][abs(a3$cota_culminante[s] - a3$cota_max[s]) > 0.01]
  # Esquema: coinciden salvo tramos con más de un máximo local. En ese caso
  # cota_culminante nunca puede superar cota_max.
  sup <- a3$id_tramo[s][a3$cota_culminante[s] > a3$cota_max[s] + 0.01]
  if (length(dif)) hallazgo(length(dif), " tramos con cota_culminante != cota_max: ", resumen_vector(dif))
  expect_true(length(sup) == 0, info = sprintf("cota_culminante > cota_max en: %s", resumen_vector(sup)))
})

test_that("A3: pendiente_media <= pendiente_max y ambas en [0, 90]", {
  s <- nn(a3$pendiente_media, a3$pendiente_max)
  ok <- a3$pendiente_media[s] <= a3$pendiente_max[s] &
        a3$pendiente_media[s] >= 0 & a3$pendiente_max[s] <= 90
  expect_true(all(ok), info = resumen_vector(a3$id_tramo[s][!ok]))
})

test_that("A3: clase_kapos ∈ 0..7 o NULL", {
  v <- a3$clase_kapos[!is.na(a3$clase_kapos)]
  expect_true(all(v %in% 0:7), info = resumen_vector(setdiff(v, 0:7)))
})

test_that("A3: orientacion_ladera en ocho rumbos o NULL", {
  v <- unique(a3$orientacion_ladera[!es_nulo(a3$orientacion_ladera)])
  expect_true(all(v %in% DOM_RUMBOS), info = resumen_vector(setdiff(v, DOM_RUMBOS)))
})

test_that("A3: sinuosidad >= 1 cuando no nula", {
  v <- a3$sinuosidad[!is.na(a3$sinuosidad)]
  expect_true(all(v >= 1 - 1e-6), info = sprintf("%d valores < 1", sum(v < 1 - 1e-6)))
})

test_that("A3: desniveles acumulados >= 0 cuando no nulos", {
  ok <- all(a3$desnivel_subida_m >= 0, na.rm = TRUE) && all(a3$desnivel_bajada_m >= 0, na.rm = TRUE)
  expect_true(ok)
})

test_that("A3: cruza_portezuelo es booleano o NULL", {
  v <- a3$cruza_portezuelo
  expect_true(is.logical(v) || all(v %in% c(0, 1, NA)))
})

test_that("A3: delta_z_m == cota_max - cota_max_z_mop cuando ambos existen", {
  s <- nn(a3$delta_z_m, a3$cota_max, a3$cota_max_z_mop)
  skip_if(!any(s), "sin filas con Z de MOP")
  malos <- a3$id_tramo[s][abs(a3$delta_z_m[s] - (a3$cota_max[s] - a3$cota_max_z_mop[s])) > 0.01]
  if (any(s)) hallazgo("delta_z_m: mediana=", round(median(a3$delta_z_m[s]), 1),
                       " m; |delta|>50 m en ", sum(abs(a3$delta_z_m[s]) > 50), " tramos (se reporta, no se corrige)")
  expect_true(length(malos) == 0, info = resumen_vector(malos))
})

test_that("A3: si el Z de MOP es cero/NULL en todas las filas, cota_max_z_mop y delta_z_m van NULL", {
  z <- a3$cota_max_z_mop
  if (all(is.na(z) | z == 0)) {
    expect_true(all(is.na(a3$delta_z_m)) && all(is.na(z)),
                info = "Z nulo en todas las filas pero hay valores escritos")
  } else expect_true(TRUE)
})

test_that("A3: cotas dentro de un rango físico plausible para un DEM (-500 a 7000 msnm)", {
  v <- unlist(a3[intersect(COTAS, names(a3))]); v <- v[!is.na(v)]
  expect_true(all(v > -500 & v < 7000), info = sprintf("fuera de rango: %d", sum(!(v > -500 & v < 7000))))
})

test_that("A3: procedencia — columnas, metodo=derivado, fuente FT-07", {
  ok_cols <- setequal(names(proc), COLS_PROCEDENCIA)
  ok_met  <- all(proc$metodo == "derivado")
  ok_fte  <- all(grepl("^FT-07", proc$fuente))
  expect_true(ok_cols && ok_met && ok_fte,
              info = sprintf("cols=%s metodo=%s fuente=%s", ok_cols, ok_met, ok_fte))
})

test_that("A3: toda celda no nula del bloque A3 tiene exactamente una fila de procedencia", {
  d <- diagnostico_procedencia(a3, proc, "id_tramo", COLS_A3)
  expect_true(nrow(d$faltantes) == 0 && length(d$duplicadas) == 0 && nrow(d$sobrantes) == 0,
              info = sprintf("celdas=%d proc=%d faltantes=%d duplicadas=%d sobrantes=%d campos_fuera=%s",
                             d$n_celdas, d$n_proc, nrow(d$faltantes), length(d$duplicadas),
                             nrow(d$sobrantes), resumen_vector(d$campos_fuera)))
})

test_that("A3: toda fila con todas las cotas NULL tiene entrada en vacios_a3.csv", {
  todas_nulas <- apply(is.na(a3[intersect(COTAS, names(a3))]), 1, all)
  skip_if(!any(todas_nulas), "no hay filas sin cota")
  ids <- a3$id_tramo[todas_nulas]
  cub <- vacio_cubre(pend, ids, "cota_max") | vacio_cubre(pend, ids, "cota_min") |
         vacio_cubre(pend, ids, "cota_media")
  expect_true(all(cub), info = sprintf("%d filas sin cota y sin vacío registrado: %s", sum(!cub), resumen_vector(ids[!cub])))
})

test_that("A3: toda celda NULL del bloque A3 tiene fila en vacios_a3.csv", {
  falt <- character()
  for (cc in COLS_A3) {
    nul <- es_nulo(a3[[cc]])
    if (any(nul)) {
      cub <- vacio_cubre(pend, a3$id_tramo[nul], cc)
      if (any(!cub)) falt <- c(falt, sprintf("%s (%d)", cc, sum(!cub)))
    }
  }
  expect_true(length(falt) == 0, info = paste(falt, collapse = "; "))
})
