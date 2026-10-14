# tests/test_a7.R — Validación del bloque A7 (cobertura nival, FT-08).

a7   <- leer_parquet(rp("data/interim/a7_nieve.parquet"))
base <- leer_parquet(rp("data/processed/tramos.parquet"))
proc <- leer_parquet(rp("data/interim/procedencia_a7.parquet"))
pend <- leer_csv(rp("data/interim/vacios_a7.csv"))
crudos <- list.files(rp("data/raw/nieve"), pattern = "^nieve_.*[.]csv$", full.names = TRUE)

SERIE_INI <- 2010L; SERIE_FIN <- 2024L; MIN_VALIDOS <- 60L; MIN_ANIOS <- 10L

test_that("A7: columnas requeridas y ninguna ajena", {
  expect_true(all(c("id_tramo", COLS_A7) %in% names(a7)),
              info = resumen_vector(setdiff(c("id_tramo", COLS_A7), names(a7))))
  ajenas <- intersect(names(a7), c(COLS_A1, COLS_A2, COLS_A3, COLS_A4, COLS_A5, COLS_A6, "en_lista_colega"))
  expect_true(length(ajenas) == 0, info = resumen_vector(ajenas))
})

test_that("A7: exactamente una fila por id_tramo de la base", {
  expect_true(setequal(a7$id_tramo, base$id_tramo) && !anyDuplicated(a7$id_tramo))
})

test_that("A7: rangos físicos — días en [0, 365], meses en [0, 12], sd >= 0", {
  d <- a7$dias_nieve_mediana[!es_nulo(a7$dias_nieve_mediana)]
  expect_true(all(d >= 0 & d <= 365), info = resumen_vector(range(d)))
  m <- a7$meses_nieve[!es_nulo(a7$meses_nieve)]
  expect_true(all(m >= 0 & m <= 12))
  s <- a7$dias_nieve_sd[!es_nulo(a7$dias_nieve_sd)]
  expect_true(all(s >= 0))
  v <- a7$dias_validos_mediana[!es_nulo(a7$dias_validos_mediana)]
  expect_true(all(v >= 0 & v <= 366))
})

test_that("A7: serie declarada 2010-2024 y NULL coherente con n_anios_validos", {
  ok <- !es_nulo(a7$dias_nieve_mediana)
  expect_true(all(a7$serie_inicio[ok] == SERIE_INI & a7$serie_fin[ok] == SERIE_FIN))
  expect_true(all(a7$n_anios_validos[ok] >= MIN_ANIOS))
  sin <- !ok & !es_nulo(a7$n_anios_validos)
  expect_true(all(a7$n_anios_validos[sin] < MIN_ANIOS),
              info = "hay tramos con años suficientes y sin valor")
  expect_true(all(es_nulo(a7$serie_inicio[!ok]) & es_nulo(a7$meses_nieve[!ok])))
})

test_that("A7: la mediana se reproduce desde el CSV crudo (muestra de 200 tramos)", {
  skip_if(length(crudos) == 0, "sin CSV crudos")
  cr <- do.call(rbind, lapply(crudos, function(f) read.csv(f, check.names = FALSE)))
  cr <- cr[cr$id_tramo %in% a7$id_tramo[!es_nulo(a7$dias_nieve_mediana)], ]
  set.seed(7); cr <- cr[sample(nrow(cr), min(200, nrow(cr))), ]
  anios <- SERIE_INI:SERIE_FIN
  rec <- vapply(seq_len(nrow(cr)), function(i) {
    n <- as.numeric(cr[i, paste0("nieve_", anios)]); v <- as.numeric(cr[i, paste0("valido_", anios)])
    ok <- !is.na(v) & v >= MIN_VALIDOS & !is.na(n)
    if (sum(ok) < MIN_ANIOS) NA_real_ else round(median(n[ok] / v[ok] * 365), 1)
  }, numeric(1))
  esp <- a7$dias_nieve_mediana[match(cr$id_tramo, a7$id_tramo)]
  expect_true(all(abs(rec - esp) < 0.051, na.rm = TRUE) && !any(is.na(rec) != is.na(esp)),
              info = sprintf("%d discrepancias", sum(abs(rec - esp) >= 0.051 | is.na(rec) != is.na(esp))))
})

test_that("A7: procedencia FT-08 / derivado / A7, una fila por celda con valor", {
  expect_true(all(proc$fuente == "FT-08" & proc$metodo == "derivado" & proc$agente == "A7"))
  for (cn in COLS_A7)
    expect_true(setequal(proc$id_tramo[proc$campo == cn], a7$id_tramo[!es_nulo(a7[[cn]])]), info = cn)
})

test_that("A7: todo NULL de dias_nieve_mediana está en vacíos con motivo", {
  nulos <- a7$id_tramo[es_nulo(a7$dias_nieve_mediana)]
  expect_true(all(nulos %in% pend$id_tramo[pend$campo == "dias_nieve_mediana"]),
              info = resumen_vector(setdiff(nulos, pend$id_tramo)))
})

test_that("A7: manifest/A7.json registra cada CSV crudo con su sha256", {
  m <- jsonlite::fromJSON(rp("data/raw/manifest/A7.json"))
  expect_equal(sort(basename(m$archivo)), sort(basename(crudos)))
  for (i in seq_len(nrow(m)))
    expect_equal(m$sha256[i], digest::digest(rp(m$archivo[i]), algo = "sha256", file = TRUE), info = m$archivo[i])
})

test_that("A7: coherencia física — en el centro-sur hay mucha más nieve sobre 1.500 m que bajo 500 m", {
  # No se usa correlación: el 90 % de los tramos tiene 0 días a cualquier cota y
  # los empates anulan a Spearman aunque la media suba con claridad. Tampoco se
  # mira el Norte Grande: sobre 3.000 m en el altiplano desértico da 0 días.
  ok <- !es_nulo(a7$dias_nieve_mediana)
  reg <- base$region[match(a7$id_tramo, base$id_tramo)]
  norte <- c("Región de Arica y Parinacota", "Región de Tarapacá", "Región de Antofagasta",
             "Región de Atacama", "Región de Coquimbo")
  sel <- ok & !reg %in% norte
  cm <- base$cota_max[match(a7$id_tramo, base$id_tramo)]
  alto <- mean(a7$dias_nieve_mediana[sel & cm >= 1500], na.rm = TRUE)
  bajo <- mean(a7$dias_nieve_mediana[sel & cm < 500], na.rm = TRUE)
  expect_true(is.finite(alto) && is.finite(bajo) && alto > 5 * bajo,
              info = sprintf("media sobre 1.500 m = %.2f días; bajo 500 m = %.2f", alto, bajo))
})

test_that("A7: los tramos de centros de esquí tienen más nieve que la mediana nacional", {
  # Verificación de alineación id-geometría con un patrón conocido de la propia base.
  esq <- base$id_tramo[base$es_esqui %in% TRUE]
  v <- a7$dias_nieve_mediana[match(esq, a7$id_tramo)]
  v <- v[!is.na(v)]
  skip_if(length(v) < 5, "menos de 5 tramos de esquí con valor")
  med_nac <- median(a7$dias_nieve_mediana, na.rm = TRUE)
  expect_true(mean(v > med_nac) >= 0.8,
              info = sprintf("%d de %d tramos de esquí sobre la mediana nacional (%.1f)", sum(v > med_nac), length(v), med_nac))
})
