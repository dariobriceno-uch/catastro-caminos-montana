# Esquema de la base — Fase 1

Contrato de columnas al que apunta la Regla 4 de `REGLAS.md`. Cada agente escribe
únicamente las columnas de su bloque.

La unidad de la tabla es el **tramo**. Toda columna admite `NULL`, y `NULL` es un
resultado válido cuando el valor no se pudo derivar.

---

## Tabla principal — `data/processed/tramos.parquet`

### Bloque ORQ — orquestador

| Columna | Tipo | Método | Descripción |
|---|---|---|---|
| `id_tramo` | texto | derivado | Llave primaria. Formato `<rol>-<n>`, correlativo dentro del rol. |
| `en_lista_colega` | booleano | derivado | El tramo coincide con un candidato de `reference/candidatos_colega.xlsx`. Marca de trazabilidad, nunca fuente de un valor. |

### Bloque A1 — Red Vial

Fuente única: FT-01, capa 3. Todos `declarado`, salvo `geometria`.

La capa ya viene segmentada por tramos con kilometraje oficial. Esos campos se
copian tal cual y no se recalculan.

| Columna | Campo origen | Tipo | Descripción |
|---|---|---|---|
| `rol` | `ROL` | texto | Rol oficial MOP. Llave de validación contra la capa cruda. |
| `rol_id` | `ROL_ID` | texto | Identificador regional del rol. |
| `codigo_camino` | `CODIGO_CAMINO` | texto | |
| `nombre_camino` | `NOMBRE_CAMINO` | texto | Nombre según Vialidad, no según uso común. |
| `clasificacion` | `CLASIFICACION` | categórico | Trece valores codificados. Incluye "Camino Nacional con Carácter de Internacional". |
| `carpeta` | `CARPETA` | categórico | Siete valores, de Pavimento Doble Calzada a Suelo Natural. |
| `calzada` | `CALZADA` | categórico | `I`, `D`, `U`. |
| `orientacion_ruta` | `ORIENTACION` | categórico | Orientación administrativa de la ruta. **No confundir con `orientacion_ladera` del bloque A3.** |
| `km_inicio` | `KM_I` | entero | Kilometraje oficial. Declarado, no derivado. **Unidad verificada 2026-08-26: la capa entrega METROS pese al nombre.** |
| `km_fin` | `KM_F` | entero | Declarado. En metros (ver `km_inicio`). |
| `km_tramo` | `KM_TRAMO` | entero | Longitud oficial del tramo. Declarada. En metros (ver `km_inicio`). |
| `enrolado` | `ENROLADO` | categórico | `Sí`, `No`, `Sin Revisar`. |
| `concesionado` | `CONCESIONADO` | categórico | `Sí`, `No`, `Sin Revisar`. |
| `tuicion` | `TUICION` | categórico | `Sí`, `No`, `Sin Revisar`. |
| `region` | `REGION` | categórico | Atributo de la capa, no cruce espacial. |
| `geometria` | `SHAPE` | LineString Z | Viene con Z. Ver bloque A3. |

**Regla sobre `Sin Revisar`.** Es un valor real y se conserva literal. Está
prohibido colapsarlo a `No` o a `NULL`.

**Advertencia jurídica.** El servicio declara que la capa no representa la
naturaleza jurídica de los caminos graficados. `enrolado`, `concesionado` y
`tuicion` son indicativos y no sirven como fuente legal.

### Bloque A2 — Validación y subdivisión de tramos

Sin fuente externa. Opera sobre la geometría y el kilometraje de A1.

La segmentación ya existe. Este bloque la verifica y subdivide solo donde el
tramo declarado cruza más de una comuna o cambia de carpeta.

| Columna | Tipo | Descripción |
|---|---|---|
| `longitud_calc_m` | real | Longitud calculada tras proyectar a UTM. Contraste contra `km_tramo`. |
| `delta_longitud_pct` | real | Discrepancia porcentual entre longitud declarada y calculada. |
| `coord_inicio` | punto | |
| `coord_fin` | punto | |
| `subdividido` | booleano | El tramo original de Vialidad se partió. |
| `motivo_corte` | categórico | `original`, `cambio_comuna`, `cambio_carpeta`, `punto_control`. |
| `utm_zona` | entero | 18 o 19. Chile cruza ambas. |

### Bloque A3 — Altimetría

Fuente única: FT-07. Todos `derivado`. **Origen exclusivo de cualquier cota.**

| Columna | Tipo | Descripción |
|---|---|---|
| `cota_min` | real | msnm |
| `cota_max` | real | msnm |
| `cota_media` | real | msnm |
| `cota_culminante` | real | Cota del punto más alto del tramo. Coincide con `cota_max` salvo tramos con más de un máximo local. |
| `pendiente_media` | real | Grados |
| `pendiente_max` | real | Grados |
| `orientacion_ladera` | categórico | Aspecto predominante de la ladera, ocho rumbos. Derivada del DEM. |
| `sinuosidad` | real | Longitud real dividida por distancia entre extremos. |
| `desnivel_subida_m` | real | Acumulado |
| `desnivel_bajada_m` | real | Acumulado |
| `cruza_portezuelo` | booleano | Máximo local con descenso superior a 200 m hacia ambos lados. |
| `clase_kapos` | entero | 0 a 7. Fuente FT-09, replicada sobre FT-07. |
| `cota_max_z_mop` | real | Cota máxima leída del Z de la geometría de A1. **Control cruzado, no fuente.** |
| `delta_z_m` | real | `cota_max` menos `cota_max_z_mop`. |

**Decisión sobre el Z.** La geometría de FT-01 trae Z, pero proviene de un
levantamiento GNSS de 2000-2003 y la precisión vertical de GNSS es
sensiblemente peor que la horizontal. El DEM es la fuente autoritativa. El Z se
guarda solo como contraste.

Un `delta_z_m` alto no se corrige. Se reporta. Es una señal de problema en la
geometría o de dosel vegetal sobre el camino, y ambas cosas interesan.

Si el Z resulta ser cero en todas las filas, `cota_max_z_mop` y `delta_z_m` van
`NULL` y se registra el hallazgo en el informe.

### Bloque A4 — Destinos y contexto

Fuentes: FT-03 (pasos, límite y zona fronteriza), FT-05 (localidades y límites
administrativos), FT-06 (esquí).

| Columna | Tipo | Fuente | Método | Descripción |
|---|---|---|---|---|
| `provincia` | categórico | FT-05 | derivado | Cruce espacial, no atributo declarado. |
| `es_esqui` | booleano | FT-06;FT-12 | derivado | Hay un centro de esquí (FT-06 o FT-12) a ≤ 2.500 m del tramo, en cualquiera de los dos sentidos del cruce: el tramo elige su centro más cercano y cada centro elige su tramo más cercano. Buffer propio (`BUFFER_ESQUI_M`), mayor que `buffer_join_m` porque las fuentes ubican el punto en el dominio esquiable, no en el estacionamiento. |
| `esqui_nombre` | texto | FT-06 / FT-12 | declarado | Nombres de los centros asociados, separados por `; ` cuando son varios (Farellones, El Colorado, La Parva y Valle Nevado comparten acceso). |
| `comuna` | categórico | FT-05 | derivado | Cruce espacial. |
| `es_paso` | booleano | FT-03a | derivado | |
| `paso_nombre` | texto | FT-03a | declarado | Denominación chilena oficial. |
| `paso_pais` | categórico | FT-03a | declarado | |
| `paso_trafico` | texto | FT-03a | declarado | Tipo de tráfico permitido. |
| `paso_habilitacion` | texto | FT-03a | declarado | Según Acuerdo de Apertura y Cierre. |
| `dist_limite_m` | real | FT-03b | derivado | Distancia del extremo del tramo al límite internacional. |
| `en_zona_fronteriza` | booleano | FT-03c | estimado | FT-03c se entrega como líneas, no polígonos. El polígono se construye cerrando la línea interior con FT-03b, más un segmento recto de 62 km en el hueco del límite argentino y un cierre marítimo al norte; por esa geometría añadida el método es `estimado` (decisión del orquestador 2026-08-26, detalle en `src/03_derivacion/a4_destinos.R`). |
| `es_esqui` | booleano | FT-06 | derivado | |
| `esqui_nombre` | texto | FT-06 | declarado | |
| `esqui_cota_base` | real | FT-06 | declarado | **No es una cota del camino.** Se guarda solo para la aserción de coherencia. |
| `es_localidad` | booleano | FT-05 | derivado | |
| `localidad_nombre` | texto | FT-05 | declarado | |
| `dist_servicios_km` | real | FT-05 | derivado | Distancia a la localidad con servicios más cercana. Nivel 3 del criterio de inclusión. |
| `buffer_join_m` | entero | — | derivado | Radio usado en el cruce. Se guarda para poder reproducir el resultado. |

### Bloque A5 — Tránsito

Fuente: FT-02. Planillas descargadas como fuente primaria, servicio REST como
respaldo geométrico.

| Columna | Tipo | Método | Descripción |
|---|---|---|---|
| `tmda` | entero | declarado | Del punto censal asociado. |
| `tmda_invierno` | entero | declarado | Muestra de junio. |
| `tmda_composicion` | texto | declarado | Desglose por tipo de vehículo, si la planilla lo trae. |
| `punto_censal_id` | texto | declarado | |
| `dist_punto_censal_m` | real | derivado | **Crítica.** Un punto censal a 40 km no describe este tramo. |
| `tmda_anio` | entero | declarado | Año del levantamiento. |
| `match_metodo` | categórico | derivado | `espacial` o `rol_kilometraje`. |

**Verificar antes de codificar el cruce.** Que el rol venga escrito igual en la
planilla y en la capa vectorial, y que el punto censal traiga coordenadas. Si
solo trae rol y kilometraje, confirmar que ambos kilometrajes tengan el mismo
origen.

### Bloque A6 — Geomorfología

Fuente: FT-10 (unidades geomorfológicas de Chile, Börgel). Cruce espacial de la
geometría del tramo contra los 116 polígonos; cuando el tramo toca más de uno,
gana el que contiene la mayor longitud (mismo criterio que `comuna`).

| Columna | Tipo | Fuente | Método | Descripción |
|---|---|---|---|---|
| `unidad_geomorf` | categórico | FT-10 | derivado | Nombre de la unidad tal cual viene en la fuente (41 valores). |
| `n_unidades_geomorf` | entero | FT-10 | derivado | Cuántas unidades toca el tramo. Si es 0, `unidad_geomorf` es `NULL`. |
| `vertiente` | categórico | FT-10 | derivado | Reagrupación de `unidad_geomorf` según la tabla de abajo: `andina`, `costera`, `transversal`, `otra`. |

**Para qué existe `vertiente`.** La clase 6 de Kapos (300–1.000 m con relieve
local) la cumplen por igual la precordillera andina y la Cordillera de la Costa.
`vertiente` permite distinguirlas sin filtrar: `clase_kapos = 6 ∧ vertiente =
andina` es la precordillera. El corte se decide sobre la base completa, como
todo el criterio de inclusión.

**Tabla de reagrupación.** Es una decisión de este proyecto sobre los nombres
de la fuente, no un atributo de FT-10. Se discute aquí; el código la copia.

| `vertiente` | unidades de FT-10 |
|---|---|
| `andina` | Cordillera prealtiplanica · Altiplano · Precordillera rio Lauca · Precordillera rio Loa superior · Precordillera de Domeyko · Precordillera · Cordillera andina de retencion crionival · Cordillera volcanica activa · Precordillera morrenica · Cordillera patagonica de lagos y rios de control tectonico · Cordillera patagonica de fiordos y rios de control tectonico · Cordillera patagonica de ventisqueros del Pacifico · Cordillera patagonica insular |
| `costera` | Cordillera de la costa · Cordillera de la costa con tectonica de hundimiento · Farellon costero · Planicie marina o fluviomarina · Cuencas graniticas marginales · Cuenca granitica marginal |
| `transversal` | Cordones transversales (Norte Chico: unen ambas cordilleras; no se asignan a ninguna) |
| `otra` | Depresiones, fosas, pampas, llanos, cuencas, salares, desierto, lagos de barrera morrénica |

Una unidad que no esté en la tabla deja `vertiente` en `NULL` y va a
`vacios`. La tabla se corrige; el valor no se adivina.

**Discutible.** `Gran fosa prealtiplanica` está en `otra` por ser depresión,
aunque queda entre precordillera y altiplano. `Cordillera patagonica insular`
está en `andina` por ser cordillera patagónica, aunque es litoral.

### Bloque A7 — Cobertura nival

Fuente: FT-08 (MOD10A1, MODIS Terra, NDSI de nieve diario a 500 m, vía Google
Earth Engine). Nivel 2 del criterio de inclusión. Decisiones fijadas el
2026-08-27 con el investigador responsable.

| Columna | Tipo | Fuente | Método | Descripción |
|---|---|---|---|---|
| `dias_nieve_mediana` | real | FT-08 | derivado | Mediana, sobre los años válidos, de los días con nieve por año escalados a 365. |
| `dias_nieve_media` | real | FT-08 | derivado | Media de lo mismo. |
| `dias_nieve_sd` | real | FT-08 | derivado | Desviación estándar interanual. |
| `meses_nieve` | entero | FT-08 | derivado | Meses del año (0–12) en que la mediana interanual de días con nieve supera 5. |
| `n_anios_validos` | entero | FT-08 | derivado | Años de la serie que entraron al cálculo. |
| `dias_validos_mediana` | entero | FT-08 | derivado | Mediana anual de días con observación sin nube. Fiabilidad del valor. |
| `serie_inicio` | entero | FT-08 | derivado | 2010. |
| `serie_fin` | entero | FT-08 | derivado | 2024. |

**Método.**
1. Producto `MODIS/061/MOD10A1`, banda `NDSI_Snow_Cover`, 2010-01-01 a 2024-12-31 (15 años).
2. Día **válido**: valor 0–100. Los códigos 200–255 (nube, noche, agua, sin decisión, relleno) se excluyen.
3. Día **con nieve**: `NDSI_Snow_Cover ≥ 40`, el umbral de la máscara binaria de nieve de NASA.
4. Por píxel, por año y por mes: número de días con nieve y número de días válidos.
5. Por tramo: **mediana de los píxeles** dentro de un buffer de 500 m sobre la geometría (simplificada a 50 m). Se reduce en el servidor (`reduceRegions`) y se exporta por región a Drive; los CSV se guardan intactos en `data/raw/nieve/`.
6. En `a7_nieve.R`: un año es válido si tiene ≥ 60 días observados (con 120, el 13,9 % de los tramos quedaba `NULL` por nubosidad del sur; donde ambos umbrales dan valor, la diferencia mediana es 0 días); días por año = nieve / válidos × 365; un tramo recibe valor si tiene ≥ 10 años válidos. Si no, `NULL` y `pendientes`.

**Limitaciones declaradas.** 500 m de píxel describe el entorno del tramo, no la
calzada. El escalado a 365 supone que los días nublados se reparten como los
observados. Terra pasa una vez al día (~10:30 local); no se combina con Aqua.

---

## Tabla de procedencia — `data/processed/procedencia.parquet`

Formato largo, una fila por par tramo-campo. Reemplaza el esquema de tres
columnas por variable, que en una tabla de cuarenta campos produce ciento veinte
columnas y se vuelve inmanejable.

| Columna | Tipo | Descripción |
|---|---|---|
| `id_tramo` | texto | |
| `campo` | texto | Nombre de la columna en `tramos`. |
| `fuente` | texto | Identificador en `docs/fuentes.md`. |
| `fecha_descarga` | fecha | Del insumo del que se derivó. |
| `metodo` | categórico | `derivado`, `declarado`, `estimado`. |
| `agente` | texto | Quién lo escribió. |

Toda celda no nula de `tramos` debe tener exactamente una fila acá. Es la
aserción de completitud de procedencia.

---

## Criterio de inclusión en esta fase

De los tres niveles definidos en `REGLAS.md`, en fase 1 se implementan dos.

1. **Geomorfológico.** `clase_kapos` y `cruza_portezuelo`, bloque A3.
2. **Nival.** Postergado. No se implementa en esta fase.
3. **Funcional.** `dist_servicios_km`, bloque A4.

El nivel nival queda como columna prevista y vacía. No se sustituye por un
proxy altimétrico ni por ninguna otra aproximación.

---

## Fuera de alcance en fase 1

Se documenta para que nadie lo agregue por su cuenta a mitad de camino.

**Postergado por decisión de proyecto.**

- Cobertura nival y días con nieve al año. Requiere Earth Engine, cuyo registro
  todavía no está resuelto. Reservado como FT-08.

**No derivable de ninguna fuente disponible.** Va a `data/vacios.csv`.

- Función minera, energética, turística no-esquí y longitudinal
- Administrador efectivo cuando no es Vialidad
- Túneles, puentes, cobertizos anti-avalancha
- Existencia y costo de ruta alternativa
- Régimen operativo real, estacionalidad y restricciones de tracción

**Fase de riesgo, no de catastro.**

- Historial de cierres y sus causas
- Sendas de avalancha
- Susceptibilidad a remociones en masa
- Series meteorológicas y nivológicas de estación

**Caminos no enrolados.** FT-01 cubre caminos de tuición del MOP. Accesos
mineros privados, caminos internos de centros de esquí y huellas comunales no
están en la capa y no se pueden derivar. Se registran como brecha conocida en el
informe final, no se completan a mano dentro de la base.
