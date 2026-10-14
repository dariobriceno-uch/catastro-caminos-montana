#!/usr/bin/env Rscript
# tests/run.R — corredor de validación por etapa (Regla 5: veto).
#
# Uso:  Rscript tests/run.R <etapa>      etapa ∈ a1 a2 a3 a4 a5 a6 a7 final visor
#
# Comportamiento:
#   - Si falta el insumo principal de la etapa, salta limpiamente (exit 0,
#     estado SKIP) y lo deja escrito en el log.
#   - Imprime PASS/FAIL/SKIP por aserción y un resumen.
#   - Exit code 1 si alguna aserción falla o si el archivo de tests aborta.
#   - Escribe logs/tests_<etapa>_<timestamp>.log

args <- commandArgs(trailingOnly = TRUE)
etapas_validas <- c("a1", "a2", "a3", "a4", "a5", "a6", "a7", "final", "visor")
if (length(args) != 1 || !(args[1] %in% etapas_validas)) {
  cat("Uso: Rscript tests/run.R <etapa>   etapa ∈ ", paste(etapas_validas, collapse = " "), "\n")
  quit(status = 2)
}
etapa <- args[1]

# Localizar raíz: el directorio que contiene tests/run.R
raiz <- tryCatch({
  f <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)[1])
  normalizePath(file.path(dirname(f), ".."), winslash = "/")
}, error = function(e) getwd())
if (is.na(raiz) || !file.exists(file.path(raiz, "REGLAS.md"))) raiz <- getwd()
# FONDEF_RAIZ permite apuntar a otra raíz (p. ej. fixtures sintéticos para probar el corredor).
env_raiz <- Sys.getenv("FONDEF_RAIZ", unset = "")
if (nzchar(env_raiz) && file.exists(file.path(env_raiz, "REGLAS.md"))) raiz <- normalizePath(env_raiz, winslash = "/")
Sys.setenv(FONDEF_RAIZ = raiz)
setwd(raiz)

if (!requireNamespace("testthat", quietly = TRUE)) {
  install.packages("testthat", repos = "https://cloud.r-project.org")
}
suppressPackageStartupMessages(library(testthat))
source(file.path(raiz, "tests", "helpers.R"))

dir.create(rp("logs"), showWarnings = FALSE)
ts <- format(Sys.time(), "%Y%m%d_%H%M%S")
log_path <- rp("logs", sprintf("tests_%s_%s.log", etapa, ts))
lineas <- character()
emitir <- function(...) {
  s <- paste0(...)
  cat(s, "\n", sep = "")
  lineas <<- c(lineas, s)
}
cerrar <- function(status, estado) {
  emitir(sprintf("ESTADO ETAPA %s: %s", toupper(etapa), estado))
  if (length(HALLAZGOS$lista) > 0) {
    emitir("Hallazgos (no bloqueantes):")
    for (h in HALLAZGOS$lista) emitir("  - ", h)
  }
  writeLines(lineas, log_path, useBytes = TRUE)
  cat("Log: ", log_path, "\n", sep = "")
  quit(status = status)
}

emitir(sprintf("== Validación etapa %s — %s ==", etapa, format(Sys.time(), "%Y-%m-%d %H:%M:%S")))
emitir("Raíz: ", basename(raiz))

# --- Salto limpio si faltan insumos ----------------------------------------
insumos <- INSUMOS[[etapa]]
faltan <- insumos[!file.exists(insumos)]
if (length(faltan) > 0) {
  emitir("SKIP: la etapa no puede validarse todavía; faltan insumos:")
  for (f in faltan) emitir("  - ", sub(paste0("^", raiz, "/?"), "", f))
  emitir("(Ninguna aserción ejecutada. Esto NO es un PASS: la etapa sigue abierta.)")
  cerrar(0, "SKIP (sin insumos)")
}

# --- Ejecutar el archivo de la etapa ---------------------------------------
archivo_test <- rp("tests", sprintf("test_%s.R", etapa))
rep <- testthat::ListReporter$new()
err_global <- NULL
res <- tryCatch(
  testthat::test_file(archivo_test, reporter = rep, env = new.env(parent = globalenv())),
  error = function(e) { err_global <<- conditionMessage(e); NULL }
)

if (!is.null(err_global)) {
  emitir("ERROR: el archivo de pruebas abortó antes de terminar: ", err_global)
  cerrar(1, "FAIL (abortado)")
}

tabla <- as.data.frame(res)
n_pass <- n_fail <- n_skip <- 0L
for (i in seq_len(nrow(tabla))) {
  fila <- tabla[i, ]
  fallo <- (fila$failed + fila$error) > 0
  saltado <- fila$skipped > 0 && !fallo
  estado <- if (fallo) "FAIL" else if (saltado) "SKIP" else "PASS"
  if (fallo) n_fail <- n_fail + 1L else if (saltado) n_skip <- n_skip + 1L else n_pass <- n_pass + 1L
  emitir(sprintf("[%s] %s", estado, fila$test))
  # Detalle de fallos / saltos
  resultados <- res[[i]]$results
  for (r in resultados) {
    if (inherits(r, "expectation_failure") || inherits(r, "expectation_error")) {
      msg <- gsub("\n", "\n         ", conditionMessage(r))
      emitir("         ", msg)
    } else if (inherits(r, "expectation_skip")) {
      emitir("         motivo: ", conditionMessage(r))
    }
  }
}

emitir("")
emitir(sprintf("Resumen %s: %d PASS, %d FAIL, %d SKIP (de %d aserciones)",
               etapa, n_pass, n_fail, n_skip, nrow(tabla)))

if (n_fail > 0) cerrar(1, "FAIL — etapa bloqueada (Regla 5)")
if (nrow(tabla) == 0) cerrar(1, "FAIL — no se ejecutó ninguna aserción")
cerrar(0, if (n_skip > 0) "PASS con saltos" else "PASS")
