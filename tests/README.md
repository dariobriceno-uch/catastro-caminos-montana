# tests/ — Validación con veto (Regla 5)

Pruebas en R (`testthat`) que corren después de cada etapa. Si una aserción
está en rojo la etapa no se cierra. No se relajan ni se desactivan aserciones.

## Cómo correr

Desde la raíz del repositorio:

```
Rscript tests/run.R a1      # bloque A1 — Red Vial (FT-01)
Rscript tests/run.R a2      # bloque A2 — subdivisión de tramos
Rscript tests/run.R a3      # bloque A3 — altimetría (FT-07)
Rscript tests/run.R a4      # bloque A4 — destinos y contexto (FT-03/05/06)
Rscript tests/run.R a5      # bloque A5 — tránsito (FT-02)
Rscript tests/run.R final   # ensamblaje data/processed
```

Requiere R 4.5 con `testthat`, `sf`, `arrow`, `jsonlite`, `digest`. Si falta
`testthat`, `run.R` lo instala desde CRAN.

## Comportamiento

- Si falta el insumo principal de la etapa, salta limpiamente: imprime la
  lista de archivos faltantes, estado `SKIP (sin insumos)` y sale con código 0.
  Un SKIP **no** es un PASS: la etapa sigue abierta.
- Imprime `[PASS] / [FAIL] / [SKIP]` por aserción (un `test_that` = una
  aserción) y un resumen final.
- Código de salida `1` si alguna aserción falla o si el archivo de pruebas
  aborta; `0` si todo pasa; `2` si la etapa no es válida.
- Escribe todo en `logs/tests_<etapa>_<timestamp>.log`, incluidos los
  **hallazgos** (líneas `[HALLAZGO]`), que son observaciones no bloqueantes
  que el orquestador debe llevar al informe (p. ej. conteo de pasos vs 64,
  `tmda_anio` posterior a la vigencia, `delta_z_m` alto).

## Insumos por etapa

| Etapa | Archivos que deben existir |
|---|---|
| a1 | `data/interim/a1_red_vial.gpkg`, `data/interim/procedencia_a1.parquet`, `data/raw/manifest/A1.json`, `data/raw/red_vial/*_pNNN.json` (páginas con features; `count_total.json` se usa como contraste) |
| a2 | `data/interim/a2_tramos.gpkg`, `data/interim/procedencia_a2.parquet`, `data/interim/a1_red_vial.gpkg` |
| a3 | `data/interim/a3_altimetria.parquet`, `data/interim/procedencia_a3.parquet`, `data/interim/a2_tramos.gpkg` |
| a4 | `data/interim/a4_destinos.parquet`, `data/interim/procedencia_a4.parquet`, `data/interim/a2_tramos.gpkg` (+ `a3_altimetria.parquet` para la aserción de esquí) |
| a5 | `data/interim/a5_transito.parquet`, `data/interim/procedencia_a5.parquet`, `data/interim/a2_tramos.gpkg` |
| final | `data/processed/tramos.parquet`, `data/processed/procedencia.parquet`, `data/vacios.csv` (+ `logs/agregados_regionales.csv` opcional) |

Los archivos opcionales (`vacios_aX.csv`, `a1_excluidos.csv`,
`agregados_regionales.csv`) hacen que la aserción correspondiente se salte o
asuma cero, y eso queda anotado como hallazgo.

## Archivos

- `run.R` — corredor, resumen, log y código de salida.
- `helpers.R` — contrato de columnas transcrito de `docs/esquema.md`, dominios,
  lectores de gpkg/parquet/manifest/JSON crudo y el diagnóstico de procedencia.
- `test_<etapa>.R` — aserciones de cada etapa.

## Convenciones que las pruebas asumen

- Capa `tramos` en los gpkg (si no existe, se toma la primera capa).
- La columna de geometría del gpkg cuenta como `geometria` del esquema, sea
  cual sea su nombre físico (`geom`, `geometry`, `geometria`).
- `vacios_aX.csv` cubre una celda si tiene fila `(id_tramo, campo)`,
  `(id_tramo, *)`, `(*, campo)` o `(*, *)`. En `final` también se acepta
  `(*, <bloque>)` con bloque en `A1..A5`.
- Filas excluidas por A1 (p. ej. Isla de Pascua) se leen de
  `data/interim/a1_excluidos.csv`, una fila por registro excluido.
- La altitud de un paso fronterizo se toma del campo `cota` de la capa cruda
  FT-03a y debe ser única por `paso_nombre`.
