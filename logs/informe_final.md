# Informe de construcción — Catastro de caminos de montaña, fase 1

Fecha de ejecución: 2026-08-26. Orquestador + subagentes A1–A5, A7. Todas las
cifras salen de los logs de cada etapa (`logs/`) y de los tests (`tests/run.R`).

## 1. Tramos derivados

- Capa cruda de Vialidad (FT-01, capa 3): **14.003** registros descargados
  (16 regiones, 765 MB de Esri JSON crudo, sha256 en `data/raw/manifest.json`).
- Excluidos: **58** tramos de Isla de Pascua (`data/interim/a1_excluidos.csv`).
- Tramos A1: **13.945**. Tras subdivisión por comuna (A2): **18.368 tramos**
  en la base (1.499 padres cortados en 5.922 hijos; 12.446 sin cortar).
- Altimetría (A3, Copernicus GLO-30 vía COG): 18.368 filas con cota, 0 NULL
  en `cota_min/max/media`; 3,06 M de puntos muestreados en 113 teselas.
  `clase_kapos`: 0 → 11.101 · 1 → 62 · 2 → 216 · 3 → 181 · 4 → 216 ·
  5 → 645 · 6 → 5.947 (clase 7 no derivable). `cruza_portezuelo`: **232**.
  Contraste con el Z de Vialidad: mediana |Δ| 0,4 m, p95 20,8 m, **163 tramos
  con |Δ| > 50 m** (revisión: geometría o dosel); 2.215 sin contraste (Z = 0).
- Destinos (A4): `es_paso` en **50 tramos** (43 vehiculares, 7 no vehiculares,
  conservados con `paso_trafico` literal); **43 pasos distintos** de los 82 de
  la capa DIFROL. `es_esqui` en 16 tramos (12 centros). `es_localidad` 9.290.
  `dist_servicios_km` (CIUDAD + PUEBLO INE): mediana 5,8 km, p95 39 km,
  máx 179 km. `en_zona_fronteriza` 2.783 (método `estimado`, polígono construido).
- Tránsito (A5): `tmda` poblado en **1.850 tramos (10,1 %)**; 1.366 con muestra
  de junio. Distancia mediana al punto censal 4,8 km; 3.761 tramos a > 10 km.

## 1b. Conteo informativo del nivel geomorfológico (no es el corte definitivo)

Sobre la tabla final, `clase_kapos` 1–5 o `cruza_portezuelo`: **1.458 tramos**
(22.073 km), pertenecientes a **643 caminos con rol identificable** (218 tramos
sin rol). Con `cota_max ≥ 1.500 m`: 738 tramos, 305 roles. Detalle por región en
`logs/conteo_geomorfologico.txt`. La red enrolada completa tiene 6.250 roles
identificables en 18.368 tramos. El corte de inclusión se decide después, sobre
los tres niveles; el nival está vacío en esta fase.

## 2. Lista del colega (Regla 6)

`reference/candidatos_colega.xlsx` **no existe en el repositorio**. No se pudo
confirmar ni descartar ningún candidato. `en_lista_colega` es NULL en las
18.368 filas. Confirmados: 0. No aparecidos: 0 (no evaluable). Cuando el archivo
se agregue, el contraste se corre sobre `data/processed/tramos.parquet` sin
rehacer ninguna etapa.

## 3. Aserciones

| Etapa | PASS | FAIL | SKIP | Log |
|---|---|---|---|---|
| a1 | 27 | 0 | 0 | `logs/tests_a1_20260826_154911.log` |
| a2 | 20 | 0 | 0 | `logs/tests_a2_20260826_154649.log` |
| a3 | 20 | 0 | 1 | filas sin cota: no hay (SKIP trivial) |
| a4 | 16 | 0 | 2 | coherencia esquí: FT-06 no trae cota base (no evaluable) |
| a5 | 14 | 0 | 0 | `logs/tests_a5_20260826_164244.log` |
| final | 11 | 0 | 2 | `en_lista_colega` sin archivo de referencia; cota base esquí inexistente |

**Ninguna aserción falló en las etapas cerradas.** Dos aserciones de `test_a2`
tenían bugs (un `grepl` con vector de patrones; una suposición de que
`km_tramo` viene en km cuando la capa entrega metros); A7 las corrigió y agregó
una aserción que protege la unidad. `en_zona_fronteriza` pasó de `derivado` a
`estimado` en el esquema por geometría construida; el test se ajustó al
contrato documentado. Ningún test fue relajado ni desactivado.

Control de completitud de pasos: 43 identificados vs. 64 habilitados de
referencia → **diferencia de 21**, reportada, no corregida (parte de los 64 son
fluviales/lacustres y parte de los caminos de acceso no están enrolados en FT-01).

## 4. Fuentes: qué se descargó y qué no

| Código | Estado | Nota |
|---|---|---|
| FT-01 Red Vial | OK | Servidor ArcGIS 10.21 sin `resultOffset`; paginado por región + rango de OBJECTID. Magallanes en 12 páginas de 15 (HTTP 500 con bloques mayores). |
| FT-02 Censos | OK | 16 planillas (2024/2025) + 7 capas REST (2014–2025). Vigencia real hasta 2025, no 2019. |
| FT-03a/b/c DIFROL | OK | Descarga manual previa; sha256 registrado. FT-03c viene como líneas. |
| FT-05 INE | OK | Comunas, provincias, ciudades, pueblos, aldeas, caseríos (Censo 2017). `geoportal.cl` devolvió 404; se usó el REST/geodatos del INE. |
| FT-06 SERNATUR | Parcial | No existe dataset de centros de esquí; se usó "Atractivos Turísticos" (4.853 puntos). **No trae cota base** → `esqui_cota_base` NULL en todo. |
| FT-07 DEM GLO-30 | OK | 323 teselas cubren Chile continental sin huecos interiores; lectura remota COG. Lista oficial de teselas no liberadas inaccesible (servidor caído). |
| FT-08 Nieve (GEE) | **NO EJECUTADO** | Postergado por decisión de proyecto (registro GEE pendiente). Sin cliente ni credenciales. Nivel nival vacío. |
| FT-09 Kapos | OK | Replicado sobre FT-07; clase 7 no derivable. |

## 5. NULL: resultado, no defecto

Principales vacíos (detalle por celda en `data/pendientes.csv`):
`tuicion` 100 % (la capa lo trae vacío) · `esqui_cota_base` 100 % ·
`tmda` 90 % (13.800 tramos cuya estación más cercana censa otro rol; 1.694 con
rama ambigua listada para revisión; 1.011 sin rol identificable) ·
`delta_longitud_pct` en hijos (sin km oficial) · `cota_max_z_mop` 2.215 (Z = 0) ·
`comuna`/`provincia` 8 hijos fuera de todo polígono INE ·
`en_lista_colega` y nivel nival: bloques completos.

## 6. Hallazgos para el equipo

- `km_inicio/km_fin/km_tramo` vienen en **metros** en la capa (anotado en esquema).
- 76 tramos con |delta_longitud_pct| > 10 % (kilometraje oficial inconsistente).
- 17 hijos (Ruta 5) conservan ≥ 20 m en una segunda comuna tras el corte.
- Dominios reales de FT-01 más amplios que los codificados (25 clasificaciones; `Si`/`DRV` en `enrolado`).
- 6 centros de esquí de FT-06 sin tramo enrolado a ≤ 500 m: brecha de cobertura de FT-01, no se completa a mano.
- Documentos `esquema.md`/`fuentes.md` estaban en la raíz; se copiaron a `docs/`.
