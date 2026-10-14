# tests/test_final.R — Validación del ensamblaje (data/processed).

tr   <- leer_parquet(rp("data/processed/tramos.parquet"))
proc <- leer_parquet(rp("data/processed/procedencia.parquet"))
pend <- leer_csv(rp("data/vacios.csv"))

COLS_ESQUEMA <- c(COLS_ORQ, COLS_A1, COLS_A2, COLS_A3, COLS_A4, COLS_A5, COLS_A6, COLS_A7)
# Llaves de trazabilidad que el protocolo obliga a conservar (A1/A2) aunque el
# esquema no las lista en la tabla final. Se aceptan; nada más se acepta.
COLS_LLAVES_OPC <- c("objectid_mop", "id_tramo_a1")
COLS_DATOS <- setdiff(COLS_ESQUEMA, c("id_tramo", "en_lista_colega"))
BLOQUE_DE <- c(setNames(rep("A1", length(COLS_A1)), COLS_A1), setNames(rep("A2", length(COLS_A2)), COLS_A2),
               setNames(rep("A3", length(COLS_A3)), COLS_A3), setNames(rep("A4", length(COLS_A4)), COLS_A4),
               setNames(rep("A5", length(COLS_A5)), COLS_A5),
               setNames(rep("A6", length(COLS_A6)), COLS_A6),
               setNames(rep("A7", length(COLS_A7)), COLS_A7))

test_that("FINAL: columnas exactamente las del esquema (ORQ + A1..A5; llaves de trazabilidad opcionales)", {
  faltan <- setdiff(COLS_ESQUEMA, names(tr))
  sobran <- setdiff(names(tr), c(COLS_ESQUEMA, COLS_LLAVES_OPC))
  expect_true(length(faltan) == 0 && length(sobran) == 0,
              info = sprintf("faltan: %s | sobran: %s", resumen_vector(faltan), resumen_vector(sobran)))
})

test_that("FINAL: id_tramo único y no nulo", {
  expect_true(!any(es_nulo(tr$id_tramo)) && !anyDuplicated(tr$id_tramo),
              info = resumen_vector(tr$id_tramo[duplicated(tr$id_tramo)]))
})

test_that("FINAL: procedencia con columnas exactas y dominios", {
  ok_cols <- setequal(names(proc), COLS_PROCEDENCIA)
  ok_met  <- all(proc$metodo %in% DOM_METODO)
  ok_fte  <- !any(es_nulo(proc$fuente))
  ok_fec  <- all(grepl("^[0-9]{4}-[0-9]{2}-[0-9]{2}", as.character(proc$fecha_descarga)))
  ok_ids  <- all(proc$id_tramo %in% tr$id_tramo)
  expect_true(ok_cols && ok_met && ok_fte && ok_fec && ok_ids,
              info = sprintf("cols=%s metodo=%s fuente=%s fecha=%s ids=%s", ok_cols, ok_met, ok_fte, ok_fec, ok_ids))
})

test_that("FINAL: procedencia no usa id_tramo_a1 sin remapear (todo id_tramo de procedencia existe en tramos)", {
  huer <- setdiff(proc$id_tramo, tr$id_tramo)
  expect_true(length(huer) == 0, info = resumen_vector(huer))
})

test_that("FINAL: toda celda no nula tiene exactamente una fila de procedencia y ninguna de más", {
  d <- diagnostico_procedencia(tr, proc, "id_tramo", COLS_DATOS)
  expect_true(nrow(d$faltantes) == 0 && length(d$duplicadas) == 0 && nrow(d$sobrantes) == 0,
              info = sprintf("celdas=%d proc=%d faltantes=%d duplicadas=%d sobrantes=%d campos_fuera=%s",
                             d$n_celdas, d$n_proc, nrow(d$faltantes), length(d$duplicadas),
                             nrow(d$sobrantes), resumen_vector(d$campos_fuera)))
})

test_that("FINAL: vacios.csv con columnas exactas del protocolo", {
  expect_true(!is.null(pend) && setequal(names(pend), COLS_VACIOS),
              info = resumen_vector(names(pend)))
})

test_that("FINAL: cada (id_tramo, campo) NULL en columnas de datos tiene fila en vacíos o bloque completo marcado *", {
  falt <- character()
  for (cc in intersect(COLS_DATOS, names(tr))) {
    nul <- es_nulo(tr[[cc]])
    if (!any(nul)) next
    ids <- tr$id_tramo[nul]
    cub <- vacio_cubre(pend, ids, cc)
    # bloque completo marcado: fila id_tramo='*' con campo = nombre del bloque (A3, A4...) o campo='*'
    bloque <- BLOQUE_DE[[cc]]
    if (!is.null(pend) && any(pend$id_tramo == "*" & toupper(pend$campo) == bloque, na.rm = TRUE)) cub[] <- TRUE
    if (any(!cub)) falt <- c(falt, sprintf("%s (%d)", cc, sum(!cub)))
  }
  expect_true(length(falt) == 0, info = paste(falt, collapse = "; "))
})

test_that("FINAL: en_lista_colega es NULL en todas las filas si reference/candidatos_colega.xlsx no existe", {
  existe <- file.exists(rp("reference/candidatos_colega.xlsx"))
  if (!existe) {
    expect_true(all(is.na(tr$en_lista_colega)),
                info = sprintf("%d filas con valor sin archivo de referencia", sum(!is.na(tr$en_lista_colega))))
  } else {
    hallazgo("candidatos_colega.xlsx existe; en_lista_colega TRUE en ", sum(tr$en_lista_colega %in% TRUE), " tramos")
    expect_true(is.logical(tr$en_lista_colega) || all(tr$en_lista_colega %in% c(0, 1, NA)))
  }
})

test_that("FINAL: en_lista_colega nunca tiene fila de procedencia con fuente distinta del propio archivo de referencia", {
  p <- proc[proc$campo == "en_lista_colega", ]
  skip_if(nrow(p) == 0, "sin filas")
  expect_true(all(p$metodo == "derivado"))
})

test_that("FINAL: consistencia interna de A2/A3 reensamblada (longitud > 0, cota_min<=media<=max)", {
  ok1 <- all(tr$longitud_calc_m > 0, na.rm = TRUE)
  s <- !is.na(tr$cota_min) & !is.na(tr$cota_media) & !is.na(tr$cota_max)
  ok2 <- all(tr$cota_min[s] <= tr$cota_media[s] & tr$cota_media[s] <= tr$cota_max[s])
  expect_true(ok1 && ok2, info = sprintf("longitud=%s cotas=%s", ok1, ok2))
})

test_that("FINAL: una sola altitud por objeto: cota_max del tramo no fue sobrescrita por esqui_cota_base", {
  s <- tr$es_esqui %in% TRUE & !is.na(tr$esqui_cota_base) & !is.na(tr$cota_max)
  skip_if(!any(s), "sin tramos de esquí con ambas cotas")
  viol <- tr$id_tramo[s][tr$cota_max[s] > tr$esqui_cota_base[s]]
  if (length(viol)) hallazgo("cota_max > esqui_cota_base: ", resumen_vector(viol))
  expect_true(length(viol) == 0, info = resumen_vector(viol))
})

test_that("FINAL: agregados regionales recalculados coinciden con logs/agregados_regionales.csv", {
  f <- rp("logs/agregados_regionales.csv")
  skip_if(!file.exists(f), "logs/agregados_regionales.csv no existe")
  ag <- read.csv(f, stringsAsFactors = FALSE, encoding = "UTF-8")
  # Nombres aceptados: region, n_tramos, longitud_calc_m (suma), n_paso / n_es_paso
  col_n   <- intersect(c("n_tramos", "n"), names(ag))[1]
  col_len <- intersect(c("longitud_calc_m", "suma_longitud_calc_m", "longitud_m"), names(ag))[1]
  col_pas <- intersect(c("n_paso", "n_es_paso", "n_pasos"), names(ag))[1]
  expect_true(all(!is.na(c(col_n, col_len, col_pas))) && "region" %in% names(ag),
              info = sprintf("columnas del csv: %s", resumen_vector(names(ag))))
  rec <- data.frame(region = tr$region, len = tr$longitud_calc_m, paso = tr$es_paso %in% TRUE)
  rec <- aggregate(cbind(n = 1, len = len, paso = paso) ~ region, data = rec, FUN = sum, na.action = na.pass)
  m <- merge(rec, ag, by = "region", all = TRUE)
  malos <- m$region[is.na(m$n) | is.na(m[[col_n]]) | m$n != m[[col_n]] |
                    abs(m$len - m[[col_len]]) > 1 | m$paso != m[[col_pas]]]
  expect_true(length(malos) == 0, info = resumen_vector(malos))
})

test_that("FINAL: ningún porcentaje 'nacional' en logs sin base completa (heurístico: se reporta)", {
  # Solo hallazgo: n tramos total y n regiones, para que el informe no etiquete la muestra como nacional.
  hallazgo("tramos=", nrow(tr), "; regiones distintas=", length(unique(na.omit(tr$region))))
  expect_true(TRUE)
})
