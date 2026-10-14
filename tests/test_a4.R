# tests/test_a4.R — Validación del bloque A4 (destinos y contexto, FT-03/05/06).

a4   <- leer_parquet(rp("data/interim/a4_destinos.parquet"))
a2df <- sin_geom(leer_gpkg(rp("data/interim/a2_tramos.gpkg")))
proc <- leer_parquet(rp("data/interim/procedencia_a4.parquet"))
pend <- leer_csv(rp("data/interim/pendientes_a4.csv"))
a3   <- if (file.exists(rp("data/interim/a3_altimetria.parquet"))) leer_parquet(rp("data/interim/a3_altimetria.parquet")) else NULL

# Capa cruda FT-03a (pasos), para la altitud del paso extraída una sola vez.
pasos_crudo <- tryCatch({
  suppressPackageStartupMessages(library(sf))
  f <- list.files(rp("data/raw/Pasos Fronterizos"), pattern = "[.]shp$", recursive = TRUE, full.names = TRUE)
  if (length(f)) sf::st_drop_geometry(sf::st_read(f[1], quiet = TRUE)) else NULL
}, error = function(e) NULL)

lg <- function(v) { x <- as.logical(v); x[is.na(x)] <- FALSE; x }

test_that("A4: columnas requeridas presentes (id_tramo + bloque A4)", {
  req <- c("id_tramo", COLS_A4)
  expect_true(all(req %in% names(a4)), info = resumen_vector(setdiff(req, names(a4))))
})

test_that("A4: no escribe columnas de otros bloques (en particular ninguna cota del camino)", {
  ajenas <- intersect(names(a4), c(COLS_A1, COLS_A2, COLS_A3, COLS_A5, "en_lista_colega"))
  expect_true(length(ajenas) == 0, info = resumen_vector(ajenas))
})

test_that("A4: exactamente una fila por id_tramo de A2", {
  expect_true(setequal(a4$id_tramo, a2df$id_tramo) && !anyDuplicated(a4$id_tramo),
              info = sprintf("faltan=%s sobran=%s dup=%d",
                             resumen_vector(setdiff(a2df$id_tramo, a4$id_tramo)),
                             resumen_vector(setdiff(a4$id_tramo, a2df$id_tramo)),
                             sum(duplicated(a4$id_tramo))))
})

test_that("A4: buffer_join_m no nulo en toda fila", {
  expect_true(all(!is.na(a4$buffer_join_m)), info = sprintf("NA: %d", sum(is.na(a4$buffer_join_m))))
})

test_that("A4: es_paso = TRUE ⇒ paso_nombre no nulo", {
  s <- lg(a4$es_paso)
  malos <- a4$id_tramo[s][es_nulo(a4$paso_nombre[s])]
  expect_true(length(malos) == 0, info = resumen_vector(malos))
})

test_that("A4: paso_nombre no nulo ⇒ es_paso = TRUE (y análogo para esquí y localidad)", {
  p <- !es_nulo(a4$paso_nombre) & !lg(a4$es_paso)
  e <- !es_nulo(a4$esqui_nombre) & !lg(a4$es_esqui)
  l <- !es_nulo(a4$localidad_nombre) & !lg(a4$es_localidad)
  expect_true(sum(p) + sum(e) + sum(l) == 0,
              info = sprintf("paso=%d esqui=%d localidad=%d", sum(p), sum(e), sum(l)))
})

test_that("A4: todo paso_nombre existe en la capa cruda FT-03a", {
  skip_if(is.null(pasos_crudo), "no se pudo leer FT-03a")
  usados <- unique(na.omit(a4$paso_nombre))
  falt <- setdiff(trimws(usados), trimws(pasos_crudo$nombre))
  expect_true(length(falt) == 0, info = resumen_vector(falt))
})

test_that("A4: la altitud de cada paso (cota de FT-03a) es única por paso_nombre", {
  skip_if(is.null(pasos_crudo) || !("cota" %in% names(pasos_crudo)), "FT-03a sin campo cota")
  usados <- unique(na.omit(trimws(a4$paso_nombre)))
  sub <- pasos_crudo[trimws(pasos_crudo$nombre) %in% usados, ]
  ncot <- tapply(sub$cota, trimws(sub$nombre), function(x) length(unique(x)))
  multi <- names(ncot)[ncot > 1]
  # Un paso en varios tramos se reporta; la unicidad aplica a la altitud del paso.
  rep <- table(a4$paso_nombre[!es_nulo(a4$paso_nombre)])
  if (any(rep > 1)) hallazgo("pasos que aparecen en varios tramos: ", resumen_vector(names(rep)[rep > 1]))
  # Si A4 guardó alguna columna de cota de paso (fuera de esquema), también debe ser única por nombre.
  col_cota <- grep("^paso_.*cota|^cota_paso", names(a4), value = TRUE)
  if (length(col_cota)) {
    for (cc in col_cota) {
      nc <- tapply(a4[[cc]], a4$paso_nombre, function(x) length(unique(na.omit(x))))
      multi <- c(multi, paste0(cc, ":", names(nc)[nc > 1]))
    }
  }
  expect_true(length(multi) == 0, info = sprintf("pasos con más de una altitud: %s", resumen_vector(multi)))
})

test_that("A4: atributos declarados del paso coinciden con FT-03a (pais, trafico, habilitacion)", {
  skip_if(is.null(pasos_crudo), "no se pudo leer FT-03a")
  s <- !es_nulo(a4$paso_nombre)
  idx <- match(trimws(a4$paso_nombre[s]), trimws(pasos_crudo$nombre))
  cmp <- function(a, b) { a <- trimws(as.character(a)); b <- trimws(as.character(b)); a[is.na(a)] <- ""; b[is.na(b)] <- ""; sum(a != b) }
  d <- c(pais = cmp(a4$paso_pais[s], pasos_crudo$pais[idx]),
         trafico = cmp(a4$paso_trafico[s], pasos_crudo$trafico[idx]),
         habilitacion = cmp(a4$paso_habilitacion[s], pasos_crudo$habilitacn[idx]))
  expect_true(all(d == 0), info = paste(names(d), d, sep = "=", collapse = "; "))
})

test_that("A4: conteo de pasos distintos identificados vs 64 habilitados (se reporta, no veta)", {
  n <- length(unique(na.omit(a4$paso_nombre)))
  traf <- unique(na.omit(a4$paso_trafico))
  hallazgo("pasos distintos identificados: ", n, " / referencia nacional: ", N_PASOS_HABILITADOS_REF,
           " (diferencia ", N_PASOS_HABILITADOS_REF - n, "); tipos de tráfico presentes: ", resumen_vector(traf, 6))
  if (!is.null(pasos_crudo)) hallazgo("pasos en capa cruda FT-03a: ", nrow(pasos_crudo),
                                      "; nombres únicos: ", length(unique(trimws(pasos_crudo$nombre))))
  expect_true(TRUE)
})

test_that("A4: es_esqui = TRUE y esqui_cota_base no nulo ⇒ cota_max del tramo (A3) <= esqui_cota_base", {
  skip_if(is.null(a3), "a3_altimetria.parquet no existe todavía")
  s <- lg(a4$es_esqui) & !is.na(a4$esqui_cota_base)
  skip_if(!any(s), "no hay tramos de esquí con cota base")
  cm <- a3$cota_max[match(a4$id_tramo[s], a3$id_tramo)]
  comp <- !is.na(cm)
  viol <- a4$id_tramo[s][comp][cm[comp] > a4$esqui_cota_base[s][comp]]
  if (length(viol)) hallazgo("violaciones cota_max > esqui_cota_base (no se corrigen): ", resumen_vector(viol))
  expect_true(length(viol) == 0, info = sprintf("%d violaciones: %s", length(viol), resumen_vector(viol)))
})

test_that("A4: ninguna cota de esquí fue copiada a una columna de altitud (esqui_cota_base solo en A4)", {
  skip_if(is.null(a3), "sin A3")
  s <- lg(a4$es_esqui) & !is.na(a4$esqui_cota_base)
  skip_if(!any(s), "no hay tramos de esquí con cota base")
  cm <- a3$cota_max[match(a4$id_tramo[s], a3$id_tramo)]
  # cota_max idéntica a esqui_cota_base es sospechosa de copia; se reporta.
  iguales <- a4$id_tramo[s][!is.na(cm) & abs(cm - a4$esqui_cota_base[s]) < 0.5]
  if (length(iguales)) hallazgo("cota_max == esqui_cota_base (revisar copia): ", resumen_vector(iguales))
  expect_true(TRUE)
})

test_that("A4: dist_limite_m, dist_servicios_km >= 0 cuando no nulos", {
  ok <- all(a4$dist_limite_m >= 0, na.rm = TRUE) && all(a4$dist_servicios_km >= 0, na.rm = TRUE)
  expect_true(ok)
})

test_that("A4: en_zona_fronteriza, es_paso, es_esqui, es_localidad son booleanos", {
  ok <- all(vapply(c("en_zona_fronteriza", "es_paso", "es_esqui", "es_localidad"),
                   function(cc) is.logical(a4[[cc]]) || all(a4[[cc]] %in% c(0, 1, NA)), logical(1)))
  expect_true(ok)
})

test_that("A4: procedencia — columnas, dominio de metodo, fuente no vacía, fuentes FT-03/05/06/12", {
  ok_cols <- setequal(names(proc), COLS_PROCEDENCIA)
  ok_met  <- all(proc$metodo %in% DOM_METODO)
  ok_fte  <- !any(es_nulo(proc$fuente))
  ok_cod  <- all(grepl("^FT-0(3[abc]?|5|6)$|^FT-12$|^FT-06;FT-12$|^-$|^—$", proc$fuente) | proc$campo == "buffer_join_m")
  expect_true(ok_cols && ok_met && ok_fte && ok_cod,
              info = sprintf("cols=%s metodo=%s fuente=%s codigos=%s (%s)", ok_cols, ok_met, ok_fte, ok_cod,
                             resumen_vector(unique(proc$fuente))))
})

test_that("A4: metodo por campo según esquema (declarado vs derivado)", {
  declarados <- c("paso_nombre", "paso_pais", "paso_trafico", "paso_habilitacion",
                  "esqui_nombre", "esqui_cota_base", "localidad_nombre")
  # en_zona_fronteriza es `estimado`: FT-03c viene como líneas y el polígono se construye
  # con geometría añadida (docs/esquema.md bloque A4, decisión orquestador 2026-08-26).
  estimados  <- c("en_zona_fronteriza")
  derivados  <- setdiff(COLS_A4, c(declarados, estimados))
  m1 <- proc$campo %in% declarados & proc$metodo != "declarado"
  m2 <- proc$campo %in% derivados  & proc$metodo != "derivado"
  m3 <- proc$campo %in% estimados  & proc$metodo != "estimado"
  expect_true(sum(m1) + sum(m2) + sum(m3) == 0,
              info = sprintf("declarados mal=%d derivados mal=%d estimados mal=%d", sum(m1), sum(m2), sum(m3)))
})

test_that("A4: toda celda no nula del bloque A4 tiene exactamente una fila de procedencia", {
  d <- diagnostico_procedencia(a4, proc, "id_tramo", COLS_A4)
  expect_true(nrow(d$faltantes) == 0 && length(d$duplicadas) == 0 && nrow(d$sobrantes) == 0,
              info = sprintf("celdas=%d proc=%d faltantes=%d duplicadas=%d sobrantes=%d campos_fuera=%s",
                             d$n_celdas, d$n_proc, nrow(d$faltantes), length(d$duplicadas),
                             nrow(d$sobrantes), resumen_vector(d$campos_fuera)))
})

test_that("A4: toda celda NULL del bloque A4 tiene fila en pendientes_a4.csv", {
  falt <- character()
  for (cc in COLS_A4) {
    nul <- es_nulo(a4[[cc]])
    if (any(nul)) {
      cub <- pendiente_cubre(pend, a4$id_tramo[nul], cc)
      if (any(!cub)) falt <- c(falt, sprintf("%s (%d)", cc, sum(!cub)))
    }
  }
  expect_true(length(falt) == 0, info = paste(falt, collapse = "; "))
})
