# Catastro de caminos de montaña de Chile

Este repositorio contiene un catastro nacional de la red vial de montaña de Chile, construido tramo a tramo desde fuentes oficiales para el proyecto FONDEF sobre caminos de alta montaña. La base divide la Red Vial Nacional de la Dirección de Vialidad (MOP) en 18.368 tramos y a cada uno le agrega altimetría, pendiente y clasificación de montaña, cobertura de nieve histórica, cruce de portezuelos, pasos fronterizos, centros de esquí, localidades y tránsito.

## Visor

El visor es un archivo HTML autocontenido: [`docs/visor_tramos.html`](docs/visor_tramos.html). Muestra los 18.368 tramos con tabla filtrable, mapa y ficha por tramo, y cada valor indica su fuente, fecha y método de obtención. Se abre con doble clic en cualquier navegador moderno y no necesita servidor, internet ni instalación.

GitHub no muestra un HTML como página. Para verlo hay que descargar el archivo (botón *Download raw file*) y abrirlo en el navegador.

## Construcción

La construcción sigue una regla de procedencia estricta. Ningún valor entra a la base si no se deriva por código de un archivo descargado de la fuente oficial, y cada celda registra la fuente, la fecha de descarga y el método con que se obtuvo. Cuando un valor no puede derivarse, la celda queda vacía y el caso se registra con su motivo en `data/pendientes.csv`. Cada etapa se cerró solo después de superar un conjunto de pruebas automáticas.

Con el criterio geomorfológico (clases 1 a 5 de Kapos o cruce de un portezuelo), 1.458 tramos califican como tramos de montaña. Suman 22.073 km y pertenecen a 643 caminos con rol identificable.

Las reglas de construcción están en [`REGLAS.md`](REGLAS.md), el esquema de columnas en [`docs/esquema.md`](docs/esquema.md), las fuentes en [`docs/fuentes.md`](docs/fuentes.md) y el libro de códigos en [`docs/libro_codigos.md`](docs/libro_codigos.md).

## Estructura del repositorio

```
.
├── REGLAS.md            reglas de construcción y criterio de inclusión
├── src/                 código por etapa
│   ├── 01_descarga/     descarga de las fuentes oficiales
│   ├── 02_segmentacion/ división de la red vial en tramos
│   ├── 03_derivacion/   altimetría, destinos, tránsito, geomorfología y nieve
│   └── 04_ensamblaje/   base final, libro de códigos y visor
├── tests/               pruebas de validación por etapa (R, testthat)
├── data/
│   ├── raw/             insumos descargados de las fuentes oficiales
│   ├── processed/       base final: tramos.parquet, tramos.gpkg, tramos.xlsx, procedencia.parquet
│   └── pendientes.csv   valores que no pudieron derivarse, con su motivo
├── docs/                esquema, fuentes, glosario, libro de códigos y visor
└── logs/                registros de ejecución y de pruebas
```

Los productos intermedios de cada etapa (`data/interim/`) no se publican. Se regeneran corriendo las etapas en orden.

## Reproducir

**Requisitos.** R 4.3 o superior con `sf`, `terra`, `arrow`, `readxl`, `httr2`, `jsonlite`, `dplyr` y `testthat`. Python 3.10 o superior con `pandas`, `numpy` y `requests`. La etapa de nieve usa además `earthengine-api` y una cuenta de Google Earth Engine.

Todos los scripts se corren desde la raíz del repositorio. Las pruebas de una etapa se corren con `Rscript tests/run.R <etapa>` (`a1` a `a7`, `final` o `visor`). El visor se regenera en dos pasos y se valida después.

```
Rscript src/04_ensamblaje/visor_payload.R
python  src/04_ensamblaje/visor_html.py
Rscript tests/run.R visor
```

## Datos

Los datos van en el repositorio con Git LFS (cerca de 1,5 GB). Para descargarlos completos hay que tener Git LFS instalado antes de clonar.

```
git lfs install
git clone https://github.com/dariobriceno-uch/catastro-caminos-montana.git
```

Las fuentes principales son las siguientes.

- Red Vial Nacional y Plan Nacional de Censos, Dirección de Vialidad, Ministerio de Obras Públicas.
- Pasos fronterizos, límite internacional y zona fronteriza, DIFROL.
- Centros invernales, SERNATUR, y centros de esquí de OpenStreetMap (© colaboradores de OpenStreetMap, licencia ODbL 1.0).
- Copernicus DEM GLO-30.
- Cobertura de nieve MODIS (MOD10A1), procesada en Google Earth Engine.
- Unidades geomorfológicas de Chile (Börgel).
- Límites administrativos del INE.

El detalle de cada fuente, con su vigencia y limitaciones, está en [`docs/fuentes.md`](docs/fuentes.md).

## Proyectos relacionados

[SAM-Cordillera](https://github.com/dariobriceno-uch/sam-cordillera) usa la geometría de este catastro para estimar el estado operacional de las rutas 60-CH y G-21 en bloques de 6 horas.
