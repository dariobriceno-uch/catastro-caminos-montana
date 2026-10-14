# Libro de códigos — `data/processed/tramos.parquet`

Generado el 2026-08-26 por `src/04_ensamblaje/libro_codigos.R` a partir de la tabla final (18.368 filas, 63 columnas + `geometria`), `procedencia.parquet` y `docs/esquema.md`. Dominios, rangos y conteos son **observados**, no declarados.

Cada ficha empieza con una explicación en lenguaje llano (qué es la variable, de dónde sale y cómo leerla), pensada para quien no maneja vocabulario geográfico ni conoce las fuentes. Después vienen los datos técnicos: bloque del esquema, campo de origen, procedencia registrada, conteo de vacíos y valores observados.

## Glosario

- **Tramo.** La unidad de esta base. Un camino se guarda partido en pedazos (tramos), no como una sola fila. Cada fila describe un pedazo con inicio y fin definidos.
- **Rol.** Código oficial con que Vialidad identifica un camino público ("Ruta 5", "G-21"). Es el "apellido" del camino; el nombre de uso común puede ser otro.
- **Vialidad (MOP).** Dirección de Vialidad del Ministerio de Obras Públicas, organismo a cargo de los caminos públicos y fuente de la red vial usada aquí.
- **Carpeta.** Superficie de rodado del camino: pavimento, ripio (grava), suelo natural (tierra), etc.
- **msnm.** Metros sobre el nivel del mar: la altitud. Todas las cotas de la base están en msnm.
- **Cota.** Altitud de un punto. En esta base, siempre la del camino, nunca la de una cumbre cercana.
- **DEM / modelo digital de elevación.** Un mapa en cuadrícula donde cada celda tiene una altitud. Se usó Copernicus GLO-30, con celdas de 30 m. Es un modelo de superficie: en zonas boscosas puede leer la copa de los árboles en vez del suelo.
- **Perfil de altitud.** La secuencia de altitudes a lo largo del camino, obtenida leyendo el DEM cada 30 m sobre el trazado.
- **Pendiente.** Inclinación del camino, en grados. 5° ≈ 9 %, 10° ≈ 18 %, 15° ≈ 27 %.
- **Desnivel acumulado.** Suma de todo lo que se sube (o baja) a lo largo del tramo, contando cada cuesta.
- **Portezuelo.** Paso de montaña: punto alto del camino desde el que se desciende hacia ambos lados. Aquí se exige un descenso de más de 200 m a cada lado.
- **Clasificación de Kapos.** Sistema usado por Naciones Unidas (UNEP-WCMC) para definir qué es montaña, combinando altitud, pendiente y relieve del entorno. Clases 1 a 6; 1 es la más alta (sobre 4.500 m). En esta base, clase 0 significa "no cumple ninguna condición de montaña".
- **Orientación de ladera (aspecto).** Hacia qué punto cardinal mira la pendiente del terreno. En Chile, las laderas que miran al sur reciben menos sol.
- **Sinuosidad.** Cuánto serpentea el camino: longitud real dividida por la distancia en línea recta. 1 = recta.
- **Paso fronterizo.** Punto autorizado para cruzar la frontera, según DIFROL. No todos son vehiculares.
- **DIFROL.** Dirección Nacional de Fronteras y Límites del Estado, fuente de los pasos, el límite internacional y la zona fronteriza.
- **Zona fronteriza.** Franja del territorio junto a la frontera donde ciertos actos (compra de tierras, obras) requieren autorización de DIFROL. Es una categoría administrativa, no geográfica.
- **INE.** Instituto Nacional de Estadísticas, fuente de los límites comunales y de las localidades pobladas (Censo 2017).
- **Localidad poblada.** Entidad del INE con población: ciudad, pueblo, aldea o caserío, en orden decreciente de tamaño y servicios.
- **SERNATUR.** Servicio Nacional de Turismo, fuente del inventario de atractivos turísticos del que se tomaron los centros de esquí.
- **TMDA.** Tránsito Medio Diario Anual: promedio de vehículos por día que pasa por un punto de conteo. Lo mide Vialidad en su Plan Nacional de Censos, con muestras en febrero, junio y octubre.
- **Punto censal / estación de conteo.** Lugar fijo donde Vialidad cuenta vehículos. No está sobre cada camino; por eso se guarda la distancia entre el tramo y la estación.
- **Cruce espacial (spatial join).** Operación de mapas que relaciona dos capas por su posición: por ejemplo, "en qué comuna cae este tramo" o "qué paso está a menos de 500 m".
- **Buffer.** Radio alrededor de un objeto usado en un cruce espacial ("a menos de 500 m").
- **UTM.** Sistema de coordenadas en metros usado para medir distancias y longitudes con precisión. Chile continental abarca las zonas 18 y 19.
- **WGS84 / lon-lat.** Sistema de coordenadas en grados (el de los GPS y Google Maps).
- **Fuente FT-xx.** Código de cada fuente de datos en `docs/fuentes.md` (FT-01 Vialidad, FT-02 censos de tránsito, FT-03 DIFROL, FT-05 INE, FT-06 SERNATUR, FT-07 DEM, FT-09 Kapos).
- **Método.** Cómo se obtuvo cada valor: `declarado` (copiado tal cual de la fuente), `derivado` (calculado por código sobre la fuente), `estimado` (con un supuesto o geometría añadida, documentados).
- **NULL.** Celda vacía: el valor no se pudo obtener de ninguna fuente. Cada NULL tiene su motivo en `data/vacios.csv`. Una celda vacía es un resultado válido; una inventada invalidaría el catastro.
- **Procedencia.** Tabla que registra, para cada celda con valor, de qué fuente, en qué fecha y con qué método se obtuvo.

## Índice

- [`id_tramo`](#id-tramo)
- [`en_lista_colega`](#en-lista-colega)
- [`id_tramo_a1`](#id-tramo-a1)
- [`objectid_mop`](#objectid-mop)
- [`rol`](#rol)
- [`rol_id`](#rol-id)
- [`codigo_camino`](#codigo-camino)
- [`nombre_camino`](#nombre-camino)
- [`clasificacion`](#clasificacion)
- [`carpeta`](#carpeta)
- [`calzada`](#calzada)
- [`orientacion_ruta`](#orientacion-ruta)
- [`km_inicio`](#km-inicio)
- [`km_fin`](#km-fin)
- [`km_tramo`](#km-tramo)
- [`enrolado`](#enrolado)
- [`concesionado`](#concesionado)
- [`tuicion`](#tuicion)
- [`region`](#region)
- [`longitud_calc_m`](#longitud-calc-m)
- [`delta_longitud_pct`](#delta-longitud-pct)
- [`coord_inicio`](#coord-inicio)
- [`coord_fin`](#coord-fin)
- [`subdividido`](#subdividido)
- [`motivo_corte`](#motivo-corte)
- [`utm_zona`](#utm-zona)
- [`cota_min`](#cota-min)
- [`cota_max`](#cota-max)
- [`cota_media`](#cota-media)
- [`cota_culminante`](#cota-culminante)
- [`pendiente_media`](#pendiente-media)
- [`pendiente_max`](#pendiente-max)
- [`orientacion_ladera`](#orientacion-ladera)
- [`sinuosidad`](#sinuosidad)
- [`desnivel_subida_m`](#desnivel-subida-m)
- [`desnivel_bajada_m`](#desnivel-bajada-m)
- [`cruza_portezuelo`](#cruza-portezuelo)
- [`clase_kapos`](#clase-kapos)
- [`cota_max_z_mop`](#cota-max-z-mop)
- [`delta_z_m`](#delta-z-m)
- [`provincia`](#provincia)
- [`comuna`](#comuna)
- [`es_paso`](#es-paso)
- [`paso_nombre`](#paso-nombre)
- [`paso_pais`](#paso-pais)
- [`paso_trafico`](#paso-trafico)
- [`paso_habilitacion`](#paso-habilitacion)
- [`dist_limite_m`](#dist-limite-m)
- [`en_zona_fronteriza`](#en-zona-fronteriza)
- [`es_esqui`](#es-esqui)
- [`esqui_nombre`](#esqui-nombre)
- [`esqui_cota_base`](#esqui-cota-base)
- [`es_localidad`](#es-localidad)
- [`localidad_nombre`](#localidad-nombre)
- [`dist_servicios_km`](#dist-servicios-km)
- [`buffer_join_m`](#buffer-join-m)
- [`tmda`](#tmda)
- [`tmda_invierno`](#tmda-invierno)
- [`tmda_composicion`](#tmda-composicion)
- [`punto_censal_id`](#punto-censal-id)
- [`dist_punto_censal_m`](#dist-punto-censal-m)
- [`tmda_anio`](#tmda-anio)
- [`match_metodo`](#match-metodo)

## `id_tramo`

- **Qué es:** Identificador único de cada fila (cada tramo de camino). Se forma con el rol del camino y un número correlativo; si el tramo fue partido por cambio de comuna, lleva un tercer número.
- **De dónde sale:** Lo asigna el proceso de construcción de la base a partir del rol de Vialidad.
- **Cómo leerlo:** "Ruta 60 CH-12-3" es el tercer pedazo del tramo número 12 de la Ruta 60 CH. No tiene significado geográfico por sí mismo; sirve para buscar y cruzar tablas.
- **Bloque:** A5 · **Tipo:** texto
- **Procedencia:** sin filas (llave o columna vacía)
- **Válidos / NULL:** 18.368 / 0 (0.0 % NULL)
- **Valores distintos:** 18.368. Más frecuentes: `--1-1` (1), `--1-2` (1), `A-105-1` (1), `A-107-1` (1), `A-109-1` (1)

## `en_lista_colega`

- **Qué es:** Marca si este tramo coincide con alguna ruta de la lista de candidatos elaborada a mano por el equipo (archivo del colega).
- **De dónde sale:** Contraste contra reference/candidatos_colega.xlsx.
- **Cómo leerlo:** Hoy está vacía en todas las filas porque ese archivo no está en el repositorio. Cuando se agregue, TRUE significará que el tramo estaba en la lista manual; nunca es fuente de ningún otro valor.
- **Bloque:** ORQ · **Tipo:** booleano
- **Nota del esquema:** El tramo coincide con un candidato de `reference/candidatos_colega.xlsx`. Marca de trazabilidad, nunca fuente de un valor.
- **Procedencia:** sin filas (llave o columna vacía)
- **Válidos / NULL:** 0 / 18.368 (100.0 % NULL)

## `id_tramo_a1`

- **Qué es:** Identificador del tramo tal como venía de Vialidad, antes de partirlo por comuna.
- **De dónde sale:** Lo asigna el proceso a partir del rol y el orden por kilómetro.
- **Cómo leerlo:** Permite reagrupar los pedazos de un mismo tramo original: todas las filas con el mismo id_tramo_a1 forman un solo tramo de Vialidad.
- **Bloque:** ORQ/llave · **Tipo:** character
- **Procedencia:** sin filas (llave o columna vacía)
- **Válidos / NULL:** 18.368 / 0 (0.0 % NULL)
- **Valores distintos:** 13.945. Más frecuentes: `M-50-K-1` (68), `P-560-3` (59), `M-870-3` (55), `N-400-2` (55), `L-391-6` (46)

## `objectid_mop`

- **Qué es:** Número de registro interno del tramo en el servicio de mapas de Vialidad.
- **De dónde sale:** Copiado de la capa de Vialidad.
- **Cómo leerlo:** Llave técnica para volver a la fuente cruda guardada en data/raw/red_vial.
- **Bloque:** ORQ/llave · **Tipo:** integer
- **Procedencia:** sin filas (llave o columna vacía)
- **Válidos / NULL:** 18.368 / 0 (0.0 % NULL)
- **Rango:** mín 119.630 · p5 121.968 · mediana 135.005 · p95 147.546 · máx 148.242

## `rol`

- **Qué es:** Código oficial con que la Dirección de Vialidad (Ministerio de Obras Públicas) identifica cada camino público, por ejemplo "Ruta 5", "G-21" o "S-61". Es el equivalente al "nombre técnico" del camino.
- **De dónde sale:** Copiado tal cual de la capa de Vialidad.
- **Cómo leerlo:** Un mismo rol se repite en varias filas porque un camino se guarda en varios tramos. Los valores "S/R", "-" o que empiezan con "S/R-" significan "sin rol": son caminos que Vialidad todavía no ha codificado y no identifican un camino concreto.
- **Bloque:** A1 · **Tipo:** texto · **Campo origen:** `ROL`
- **Nota del esquema:** Rol oficial MOP. Llave de validación contra la capa cruda.
- **Procedencia:** FT-01 / declarado / A1 (18.368 celdas)
- **Válidos / NULL:** 18.368 / 0 (0.0 % NULL)
- **Valores distintos:** 8.084. Más frecuentes: `S/R` (1.009), `Ruta 5` (334), `L-391` (127), `N-70-M` (99), `Ruta 7` (78)

## `rol_id`

- **Qué es:** Identificador interno del rol dentro de su región, usado por Vialidad.
- **De dónde sale:** Copiado de la capa de Vialidad.
- **Cómo leerlo:** Solo sirve para volver a cruzar con la fuente original; no aporta información propia.
- **Bloque:** A1 · **Tipo:** texto · **Campo origen:** `ROL_ID`
- **Nota del esquema:** Identificador regional del rol.
- **Procedencia:** FT-01 / declarado / A1 (18.368 celdas)
- **Válidos / NULL:** 18.368 / 0 (0.0 % NULL)
- **Valores distintos:** 9.652. Más frecuentes: `N-70-M` (99), `Ruta 5_1` (96), `-` (95), `L-391_1` (76), `Ruta 5_2` (71)

## `codigo_camino`

- **Qué es:** Código interno del camino en el sistema de Vialidad.
- **De dónde sale:** Copiado de la capa de Vialidad.
- **Cómo leerlo:** Igual que rol_id: llave técnica de la fuente.
- **Bloque:** A1 · **Tipo:** texto · **Campo origen:** `CODIGO_CAMINO`
- **Procedencia:** FT-01 / declarado / A1 (18.368 celdas)
- **Válidos / NULL:** 18.368 / 0 (0.0 % NULL)
- **Valores distintos:** 8.681. Más frecuentes: `67D20391` (127), `76B00070` (99), `-` (95), `67B00050` (70), `68C10390` (69)

## `nombre_camino`

- **Qué es:** Nombre con que Vialidad describe el camino, normalmente como origen y destino ("Av. Las Condes - Farellones - La Parva").
- **De dónde sale:** Copiado de la capa de Vialidad.
- **Cómo leerlo:** Es el nombre administrativo, que puede diferir del nombre de uso común. Se conserva literal, incluidas abreviaturas y mayúsculas.
- **Bloque:** A1 · **Tipo:** texto · **Campo origen:** `NOMBRE_CAMINO`
- **Nota del esquema:** Nombre según Vialidad, no según uso común.
- **Procedencia:** FT-01 / declarado / A1 (18.368 celdas)
- **Válidos / NULL:** 18.368 / 0 (0.0 % NULL)
- **Valores distintos:** 8.703. Más frecuentes: `Cruce L-11 (La Unión) - El Melado` (127), `Cauquenes - Torrecillas - San Carlos, Sector: Límite Regional (Puente El Guindo) - San Carlos (Calle Luis Acevedo)` (99), `Cruce Ruta 128 (Cauquenes) - Chanco - Cruce L-30-K (Viñales)` (70), `Paso Superior Ruta 150 (Penco) - Cruce N-48-O (Florida)` (69), `Anillo Circunvalación Américo Vespucio` (68)

## `clasificacion`

- **Qué es:** Categoría administrativa del camino según Vialidad: nacional, regional principal, regional comunal, de acceso, etc. Indica la jerarquía del camino en la red, no su estado físico.
- **De dónde sale:** Copiado de la capa de Vialidad.
- **Cómo leerlo:** Los valores entre paréntesis ("En Proceso de Enrolamiento", "Conexión Vial Urbana") son variantes que trae la propia fuente. "Sin Información" es un valor real de la fuente, no un vacío.
- **Bloque:** A1 · **Tipo:** categórico · **Campo origen:** `CLASIFICACION`
- **Nota del esquema:** Trece valores codificados. Incluye "Camino Nacional con Carácter de Internacional".
- **Procedencia:** FT-01 / declarado / A1 (18.368 celdas)
- **Válidos / NULL:** 18.368 / 0 (0.0 % NULL)
- **Dominio observado (25 valores):**

| Valor | n |
|---|---:|
| Camino Regional Comunal | 7.304 |
| Camino Regional de Acceso | 2.303 |
| Sin Información | 2.247 |
| Camino Regional Comunal (En Proceso de Enrolamiento) | 1.668 |
| Camino Regional Principal | 1.339 |
| Camino Regional de Acceso (En Proceso de Enrolamiento) | 1.097 |
| Camino Regional Provincial | 1.017 |
| Camino Nacional | 423 |
| Camino Nacional Longitudinal | 411 |
| Camino Nacional con Carácter de Internacional | 172 |
| Camino Regional Comunal (Conexión Vial Urbana) | 112 |
| Camino Regional Principal (Conexión Vial Urbana) | 76 |
| Camino Regional Provincial (En Proceso de Enrolamiento) | 69 |
| Camino Regional Provincial (Conexión Vial Urbana) | 31 |
| Camino Nacional (Conexión Vial Urbana) | 27 |
| Camino Regional Principal (En Proceso de Enrolamiento) | 18 |
| Camino Regional de Acceso (Conexión Vial Urbana) | 14 |
| Conexión Vial Urbana | 14 |
| Camino Nacional Longitudinal (En Proceso de Enrolamiento) | 12 |
| Camino Regional Comunal  | 7 |
| Camino Privado | 2 |
| Camino Regional de Comunal (En Proceso de Enrolamiento) | 2 |
| Camino Nacional (En Proceso de Enrolamiento) | 1 |
| Camino por Enrolar | 1 |
| Camino Regional Comunal (En proceso de Enrolamiento) | 1 |


## `carpeta`

- **Qué es:** Tipo de superficie de rodado del camino: pavimento (asfalto u hormigón), doble calzada pavimentada, ripio (grava), suelo natural (tierra), etc.
- **De dónde sale:** Copiado de la capa de Vialidad.
- **Cómo leerlo:** Es la mejor aproximación disponible al "estándar" del camino. "Suelo Natural" y "Ripio" son caminos sin pavimentar.
- **Bloque:** A1 · **Tipo:** categórico · **Campo origen:** `CARPETA`
- **Nota del esquema:** Siete valores, de Pavimento Doble Calzada a Suelo Natural.
- **Procedencia:** FT-01 / declarado / A1 (18.368 celdas)
- **Válidos / NULL:** 18.368 / 0 (0.0 % NULL)
- **Dominio observado (7 valores):**

| Valor | n |
|---|---:|
| Ripio | 6.475 |
| Pavimento Básico | 4.747 |
| Pavimento | 3.349 |
| Suelo Natural | 1.959 |
| Pavimento Doble Calzada | 951 |
| Grava Tratada | 613 |
| Sin Información | 274 |


## `calzada`

- **Qué es:** Indica la calzada a la que corresponde el registro cuando el camino tiene dos separadas: I (izquierda), D (derecha), U o ÚNICA (una sola calzada).
- **De dónde sale:** Copiado de la capa de Vialidad.
- **Cómo leerlo:** En autopistas de doble calzada el mismo camino aparece dos veces (una por calzada, con los mismos kilómetros): no es un error ni un doble conteo del catastro. "-" es un valor literal de la fuente.
- **Bloque:** A1 · **Tipo:** categórico · **Campo origen:** `CALZADA`
- **Nota del esquema:** `I`, `D`, `U`.
- **Procedencia:** FT-01 / declarado / A1 (16.053 celdas)
- **Válidos / NULL:** 16.053 / 2.315 (12.6 % NULL)
- **Dominio observado (5 valores):**

| Valor | n |
|---|---:|
| U | 9.066 |
| ÚNICA | 3.816 |
| - | 2.188 |
| D | 564 |
| I | 419 |


## `orientacion_ruta`

- **Qué es:** Orientación administrativa que Vialidad asigna a la ruta (por ejemplo, norte-sur u oriente-poniente). Es una etiqueta de la fuente, no un cálculo.
- **De dónde sale:** Copiado de la capa de Vialidad.
- **Cómo leerlo:** No confundir con orientacion_ladera, que sí se calcula desde el relieve. "-" es un valor literal de la fuente.
- **Bloque:** A1 · **Tipo:** categórico · **Campo origen:** `ORIENTACION`
- **Nota del esquema:** Orientación administrativa de la ruta. **No confundir con `orientacion_ladera` del bloque A3.**
- **Procedencia:** FT-01 / declarado / A1 (15.821 celdas)
- **Válidos / NULL:** 15.821 / 2.547 (13.9 % NULL)
- **Dominio observado (7 valores):**

| Valor | n |
|---|---:|
| ÚNICA | 13.335 |
| - | 2.123 |
| SUR | 157 |
| NORTE | 146 |
| OESTE | 30 |
| ESTE | 26 |
| CENTRO | 4 |


## `km_inicio`

- **Qué es:** Punto kilométrico oficial donde empieza el tramo, medido desde el origen del camino. ATENCIÓN: la fuente lo entrega en metros aunque el nombre diga "km".
- **De dónde sale:** Copiado de la capa de Vialidad, sin convertir.
- **Cómo leerlo:** Un valor 32200 significa el kilómetro 32,2 del camino. Se conserva en metros para no alterar el dato original.
- **Bloque:** A1 · **Tipo:** entero · **Campo origen:** `KM_I`
- **Nota del esquema:** Kilometraje oficial. Declarado, no derivado. **Unidad verificada 2026-08-26: la capa entrega METROS pese al nombre.**
- **Unidad:** m (literal de la capa)
- **Procedencia:** FT-01 / declarado / A1 (18.368 celdas)
- **Válidos / NULL:** 18.368 / 0 (0.0 % NULL)
- **Rango:** mín 0 · p5 0 · mediana 0 · p95 38.000 · máx 2.079.405

## `km_fin`

- **Qué es:** Punto kilométrico oficial donde termina el tramo, en metros (ver km_inicio).
- **De dónde sale:** Copiado de la capa de Vialidad, sin convertir.
- **Cómo leerlo:** Para los tramos partidos por comuna, km_inicio y km_fin son los del tramo original completo (no del pedazo).
- **Bloque:** A1 · **Tipo:** entero · **Campo origen:** `KM_F`
- **Nota del esquema:** Declarado. En metros (ver `km_inicio`).
- **Unidad:** m (literal de la capa)
- **Procedencia:** FT-01 / declarado / A1 (18.368 celdas)
- **Válidos / NULL:** 18.368 / 0 (0.0 % NULL)
- **Rango:** mín 0 · p5 0 · mediana 5.031,5 · p95 73.837 · máx 2.080.116

## `km_tramo`

- **Qué es:** Longitud oficial del tramo declarada por Vialidad, en metros.
- **De dónde sale:** Copiado de la capa de Vialidad, sin convertir.
- **Cómo leerlo:** Compárese con longitud_calc_m, que es la longitud medida sobre la geometría. Un valor 0 significa que la fuente no lo informó.
- **Bloque:** A1 · **Tipo:** entero · **Campo origen:** `KM_TRAMO`
- **Nota del esquema:** Longitud oficial del tramo. Declarada. En metros (ver `km_inicio`).
- **Unidad:** m (literal de la capa)
- **Procedencia:** FT-01 / declarado / A1 (18.368 celdas)
- **Válidos / NULL:** 18.368 / 0 (0.0 % NULL)
- **Rango:** mín 0 · p5 0 · mediana 2.973 · p95 41.840 · máx 323.331

## `enrolado`

- **Qué es:** Indica si el camino está formalmente inscrito ("enrolado") en el registro de caminos públicos de Vialidad: Sí, No o Sin Revisar.
- **De dónde sale:** Copiado de la capa de Vialidad.
- **Cómo leerlo:** "Sin Revisar" es un valor real de la fuente y se conserva. Vialidad advierte que este campo es indicativo y no define la situación legal del camino.
- **Bloque:** A1 · **Tipo:** categórico · **Campo origen:** `ENROLADO`
- **Nota del esquema:** `Sí`, `No`, `Sin Revisar`.
- **Procedencia:** FT-01 / declarado / A1 (18.366 celdas)
- **Válidos / NULL:** 18.366 / 2 (0.0 % NULL)
- **Dominio observado (5 valores):**

| Valor | n |
|---|---:|
| Sí | 13.154 |
| No | 3.043 |
| Sin Revisar | 2.161 |
| Si | 7 |
| DRV | 1 |


## `concesionado`

- **Qué es:** Indica si el camino está entregado en concesión a un operador privado (autopistas de peaje): Sí, No o Sin Revisar.
- **De dónde sale:** Copiado de la capa de Vialidad.
- **Cómo leerlo:** Mismo carácter indicativo que enrolado.
- **Bloque:** A1 · **Tipo:** categórico · **Campo origen:** `CONCESIONADO`
- **Nota del esquema:** `Sí`, `No`, `Sin Revisar`.
- **Procedencia:** FT-01 / declarado / A1 (18.368 celdas)
- **Válidos / NULL:** 18.368 / 0 (0.0 % NULL)
- **Dominio observado (4 valores):**

| Valor | n |
|---|---:|
| No | 17.669 |
| Sí | 683 |
| Sin Revisar | 14 |
| Si | 2 |


## `tuicion`

- **Qué es:** Indica si el camino está bajo tuición (responsabilidad de mantención) de Vialidad.
- **De dónde sale:** Copiado de la capa de Vialidad.
- **Cómo leerlo:** La fuente entrega este campo vacío en todas las filas, por eso está NULL en toda la base.
- **Bloque:** A1 · **Tipo:** categórico · **Campo origen:** `TUICION`
- **Nota del esquema:** `Sí`, `No`, `Sin Revisar`.
- **Procedencia:** sin filas (llave o columna vacía)
- **Válidos / NULL:** 0 / 18.368 (100.0 % NULL)

## `region`

- **Qué es:** Región administrativa donde Vialidad registra el camino.
- **De dónde sale:** Copiado de la capa de Vialidad (es un atributo, no un cruce con mapas).
- **Cómo leerlo:** Provincia y comuna, en cambio, sí se calculan por cruce espacial; si alguna vez no coinciden con region, se reporta y no se corrige.
- **Bloque:** A1 · **Tipo:** categórico · **Campo origen:** `REGION`
- **Nota del esquema:** Atributo de la capa, no cruce espacial.
- **Procedencia:** FT-01 / declarado / A1 (18.368 celdas)
- **Válidos / NULL:** 18.368 / 0 (0.0 % NULL)
- **Dominio observado (16 valores):**

| Valor | n |
|---|---:|
| Región de La Araucanía | 2.450 |
| Región del Maule | 2.138 |
| Región del Libertador General Bernardo O'Higgins | 1.903 |
| Región de Valparaíso | 1.784 |
| Región de Los Lagos | 1.781 |
| Región del Biobío | 1.613 |
| Región de Ñuble | 1.553 |
| Región Metropolitana de Santiago | 1.146 |
| Región de Los Ríos | 1.004 |
| Región de Coquimbo | 879 |
| Región de Atacama | 734 |
| Región Aysén del General Carlos Ibáñez del Campo | 351 |
| Región de Antofagasta | 340 |
| Región de Tarapacá | 326 |
| Región de Magallanes y La Antártica Chilena | 199 |
| Región de Arica y Parinacota | 167 |


## `longitud_calc_m`

- **Qué es:** Longitud del tramo en metros, medida sobre su trazado en el mapa.
- **De dónde sale:** Calculada proyectando la geometría a coordenadas UTM y midiendo la línea.
- **Cómo leerlo:** Es la longitud real del dibujo del camino. Si difiere mucho de km_tramo, el kilometraje oficial y la geometría no cuadran (ver delta_longitud_pct).
- **Bloque:** A2 · **Tipo:** real
- **Nota del esquema:** Longitud calculada tras proyectar a UTM. Contraste contra `km_tramo`.
- **Unidad:** m
- **Procedencia:** FT-01 / derivado / A2 (18.368 celdas)
- **Válidos / NULL:** 18.368 / 0 (0.0 % NULL)
- **Rango:** mín 0,31 · p5 72,12 · mediana 2.040,33 · p95 18.932,06 · máx 194.693,8

## `delta_longitud_pct`

- **Qué es:** Diferencia porcentual entre la longitud medida (longitud_calc_m) y la longitud oficial (km_tramo).
- **De dónde sale:** (longitud_calc_m − km_tramo) / km_tramo × 100.
- **Cómo leerlo:** Cerca de 0 significa que ambas coinciden. Valores grandes (más de 10 %) señalan un kilometraje oficial dudoso. Está vacío en los pedazos partidos por comuna (no tienen km oficial propio) y donde km_tramo es 0.
- **Bloque:** A2 · **Tipo:** real
- **Nota del esquema:** Discrepancia porcentual entre longitud declarada y calculada.
- **Unidad:** %
- **Procedencia:** FT-01 / derivado / A2 (11.046 celdas)
- **Válidos / NULL:** 11.046 / 7.322 (39.9 % NULL)
- **Rango:** mín -97,79 · p5 -1,06 · mediana -0,12 · p95 0,04 · máx 377,1

## `coord_inicio`

- **Qué es:** Coordenadas del punto donde empieza el tramo, en longitud y latitud (grados decimales, sistema WGS84, el mismo de un GPS).
- **De dónde sale:** Primer vértice de la geometría.
- **Cómo leerlo:** Formato "POINT(lon lat)". Se puede pegar en Google Maps invirtiendo el orden (lat, lon).
- **Bloque:** A2 · **Tipo:** punto
- **Procedencia:** FT-01 / derivado / A2 (18.368 celdas)
- **Válidos / NULL:** 18.368 / 0 (0.0 % NULL)
- **Valores distintos:** 18.072. Más frecuentes: `POINT(   -70.940138667    -34.610555565)` (3), `POINT(   -71.473837088 -32.8024108399999)` (3), `POINT(-67.9982181889999    -23.408939629)` (2), `POINT(-68.0021291479999    -23.274102383)` (2), `POINT(-68.8116972189999    -54.506731992)` (2)

## `coord_fin`

- **Qué es:** Coordenadas del punto donde termina el tramo (ver coord_inicio).
- **De dónde sale:** Último vértice de la geometría.
- **Cómo leerlo:** Formato "POINT(lon lat)".
- **Bloque:** A2 · **Tipo:** punto
- **Procedencia:** FT-01 / derivado / A2 (18.368 celdas)
- **Válidos / NULL:** 18.368 / 0 (0.0 % NULL)
- **Valores distintos:** 18.151. Más frecuentes: `POINT(-70.6441037119999    -33.960182286)` (3), `POINT(-72.0003978139999 -35.9529995189999)` (3), `POINT(-73.0039390379999 -39.1192823819999)` (3), `POINT(   -68.916002982    -22.432951987)` (3), `POINT(   -72.972450378    -38.697787234)` (3)

## `subdividido`

- **Qué es:** Indica si el tramo original de Vialidad fue partido en pedazos porque cruzaba más de una comuna.
- **De dónde sale:** Resultado del cruce con los límites comunales del INE.
- **Cómo leerlo:** TRUE: esta fila es un pedazo de un tramo mayor (ver id_tramo_a1). FALSE: la fila es el tramo tal como lo entrega Vialidad.
- **Bloque:** A2 · **Tipo:** booleano
- **Nota del esquema:** El tramo original de Vialidad se partió.
- **Procedencia:** FT-01 / derivado / A2 (12.446 celdas); FT-05 / derivado / A2 (5.922 celdas)
- **Válidos / NULL:** 18.368 / 0 (0.0 % NULL)
- **Dominio observado:** TRUE 5.922 · FALSE 12.446

## `motivo_corte`

- **Qué es:** Razón por la que la fila existe como tramo separado: "original" (tal como viene de Vialidad) o "cambio_comuna" (partido en el límite entre dos comunas).
- **De dónde sale:** Asignado durante la segmentación.
- **Cómo leerlo:** Los valores "cambio_carpeta" y "punto_control" están previstos en el diseño pero no se usaron en esta fase.
- **Bloque:** A2 · **Tipo:** categórico
- **Nota del esquema:** `original`, `cambio_comuna`, `cambio_carpeta`, `punto_control`.
- **Procedencia:** FT-01 / derivado / A2 (12.446 celdas); FT-05 / derivado / A2 (5.922 celdas)
- **Válidos / NULL:** 18.368 / 0 (0.0 % NULL)
- **Dominio observado (2 valores):**

| Valor | n |
|---|---:|
| original | 12.446 |
| cambio_comuna | 5.922 |


## `utm_zona`

- **Qué es:** Zona del sistema de coordenadas UTM usada para medir distancias y longitudes en este tramo: 18 (oeste de −72° de longitud) o 19 (este).
- **De dónde sale:** Según la longitud del centro del tramo.
- **Cómo leerlo:** Dato técnico para reproducir los cálculos; Chile continental cae en dos zonas UTM y hay que elegir una por tramo para medir bien.
- **Bloque:** A2 · **Tipo:** entero
- **Nota del esquema:** 18 o 19. Chile cruza ambas.
- **Unidad:** zona UTM sur
- **Procedencia:** FT-01 / derivado / A2 (18.368 celdas)
- **Válidos / NULL:** 18.368 / 0 (0.0 % NULL)
- **Rango:** mín 18 · p5 18 · mediana 19 · p95 19 · máx 19
- **Dominio observado:**

| Valor | n |
|---|---:|
| 19 | 9.744 |
| 18 | 8.624 |


## `cota_min`

- **Qué es:** Altitud más baja del camino a lo largo del tramo, en metros sobre el nivel del mar (msnm).
- **De dónde sale:** Se muestrea el trazado cada 30 m y se lee la altura del modelo digital de elevación Copernicus GLO-30 en cada punto; es el mínimo de esas lecturas.
- **Cómo leerlo:** Describe el punto más bajo por el que pasa el camino. Valores cercanos a 0, incluso levemente negativos, corresponden a tramos costeros: el modelo de elevación tiene un error vertical de unos pocos metros.
- **Bloque:** A3 · **Tipo:** real
- **Nota del esquema:** msnm
- **Unidad:** msnm
- **Procedencia:** FT-07 / derivado / A3 (18.368 celdas)
- **Válidos / NULL:** 18.368 / 0 (0.0 % NULL)
- **Rango:** mín -10,6 · p5 5,41 · mediana 194,04 · p95 1.082,07 · máx 5.175,29

## `cota_max`

- **Qué es:** Altitud más alta del camino a lo largo del tramo, en msnm.
- **De dónde sale:** Máximo de las mismas lecturas del modelo de elevación que cota_min.
- **Cómo leerlo:** Es la altura máxima que alcanza el vehículo en ese tramo. Nunca es la cota de una cumbre cercana ni la de un centro de esquí: solo del camino.
- **Bloque:** A3 · **Tipo:** real
- **Nota del esquema:** msnm
- **Unidad:** msnm
- **Procedencia:** FT-07 / derivado / A3 (18.368 celdas)
- **Válidos / NULL:** 18.368 / 0 (0.0 % NULL)
- **Rango:** mín 0 · p5 39,61 · mediana 249,94 · p95 1.307,22 · máx 5.201,8

## `cota_media`

- **Qué es:** Altitud promedio del camino en el tramo, en msnm.
- **De dónde sale:** Promedio de las lecturas del modelo de elevación.
- **Cómo leerlo:** Siempre está entre cota_min y cota_max.
- **Bloque:** A3 · **Tipo:** real
- **Nota del esquema:** msnm
- **Unidad:** msnm
- **Procedencia:** FT-07 / derivado / A3 (18.368 celdas)
- **Válidos / NULL:** 18.368 / 0 (0.0 % NULL)
- **Rango:** mín 0 · p5 24,38 · mediana 223,67 · p95 1.174,37 · máx 5.186,4

## `cota_culminante`

- **Qué es:** Altitud del punto más alto "interior" del tramo: la cima de una subida seguida de bajada dentro del tramo. Si el tramo sube todo el tiempo, coincide con cota_max.
- **De dónde sale:** Máximo local de mayor prominencia en el perfil de altitud, suavizado.
- **Cómo leerlo:** Sirve para detectar cuestas o pasos dentro del tramo. Nunca supera cota_max.
- **Bloque:** A3 · **Tipo:** real
- **Nota del esquema:** Cota del punto más alto del tramo. Coincide con `cota_max` salvo tramos con más de un máximo local.
- **Unidad:** msnm
- **Procedencia:** FT-07 / derivado / A3 (18.368 celdas)
- **Válidos / NULL:** 18.368 / 0 (0.0 % NULL)
- **Rango:** mín 0 · p5 32,52 · mediana 238,17 · p95 1.237,28 · máx 5.201,8

## `pendiente_media`

- **Qué es:** Inclinación promedio del camino a lo largo del tramo, en grados.
- **De dónde sale:** Promedio de la pendiente entre puntos consecutivos del perfil de altitud (cada 30 m), ponderado por longitud.
- **Cómo leerlo:** 0° es plano; 5° equivale aproximadamente a un 9 % de pendiente; 10° a un 18 %. Es la pendiente a lo largo del camino, no la del cerro.
- **Bloque:** A3 · **Tipo:** real
- **Nota del esquema:** Grados
- **Unidad:** grados
- **Procedencia:** FT-07 / derivado / A3 (18.368 celdas)
- **Válidos / NULL:** 18.368 / 0 (0.0 % NULL)
- **Rango:** mín 0 · p5 0,14 · mediana 1,17 · p95 4,12 · máx 22,62

## `pendiente_max`

- **Qué es:** Inclinación más fuerte encontrada en el tramo, en grados.
- **De dónde sale:** Máximo de la pendiente entre puntos consecutivos del perfil, suavizado en ventanas de unos 150 m.
- **Cómo leerlo:** Indica el trecho más empinado. Valores muy altos en tramos cortos pueden deberse a la resolución del modelo de elevación (30 m).
- **Bloque:** A3 · **Tipo:** real
- **Nota del esquema:** Grados
- **Unidad:** grados
- **Procedencia:** FT-07 / derivado / A3 (18.368 celdas)
- **Válidos / NULL:** 18.368 / 0 (0.0 % NULL)
- **Rango:** mín 0 · p5 0,35 · mediana 4,7 · p95 19,47 · máx 89,76

## `orientacion_ladera`

- **Qué es:** Hacia qué punto cardinal mira la ladera sobre la que va el camino (N, NE, E, SE, S, SO, O, NO).
- **De dónde sale:** Aspecto (orientación de la pendiente del terreno) calculado desde el modelo de elevación bajo el trazado; se guarda el rumbo predominante.
- **Cómo leerlo:** En el hemisferio sur, las laderas que miran al sur (S, SE, SO) reciben menos sol y conservan más nieve y hielo. No confundir con orientacion_ruta.
- **Bloque:** A3 · **Tipo:** categórico
- **Nota del esquema:** Aspecto predominante de la ladera, ocho rumbos. Derivada del DEM.
- **Procedencia:** FT-07 / derivado / A3 (18.367 celdas)
- **Válidos / NULL:** 18.367 / 1 (0.0 % NULL)
- **Dominio observado (8 valores):**

| Valor | n |
|---|---:|
| O | 3.623 |
| NO | 2.924 |
| N | 2.679 |
| SO | 2.256 |
| NE | 1.955 |
| S | 1.839 |
| E | 1.771 |
| SE | 1.320 |


## `sinuosidad`

- **Qué es:** Cuánto serpentea el camino: longitud real del tramo dividida por la distancia en línea recta entre sus extremos.
- **De dónde sale:** longitud_calc_m / distancia recta inicio–fin.
- **Cómo leerlo:** 1,0 es una recta perfecta; 2,0 significa que el camino recorre el doble de lo que avanza. Los caminos de montaña con curvas de retorno tienen valores altos.
- **Bloque:** A3 · **Tipo:** real
- **Nota del esquema:** Longitud real dividida por distancia entre extremos.
- **Unidad:** adimensional
- **Procedencia:** FT-07 / derivado / A3 (18.362 celdas)
- **Válidos / NULL:** 18.362 / 6 (0.0 % NULL)
- **Rango:** mín 1 · p5 1 · mediana 1,08 · p95 1,6 · máx 45,1

## `desnivel_subida_m`

- **Qué es:** Suma de todos los metros que el camino sube a lo largo del tramo, en la dirección de recorrido de la geometría.
- **De dónde sale:** Acumulado de las subidas del perfil de altitud suavizado.
- **Cómo leerlo:** Un tramo que sube 300 m, baja 100 y vuelve a subir 50 tiene desnivel_subida_m = 350.
- **Bloque:** A3 · **Tipo:** real
- **Nota del esquema:** Acumulado
- **Unidad:** m
- **Procedencia:** FT-07 / derivado / A3 (18.368 celdas)
- **Válidos / NULL:** 18.368 / 0 (0.0 % NULL)
- **Rango:** mín 0 · p5 0 · mediana 17,77 · p95 392,33 · máx 3.349,75

## `desnivel_bajada_m`

- **Qué es:** Suma de todos los metros que el camino baja a lo largo del tramo.
- **De dónde sale:** Acumulado de las bajadas del perfil suavizado.
- **Cómo leerlo:** Junto con desnivel_subida_m describe cuánto "sube y baja" el tramo, más allá de la diferencia entre cota_min y cota_max.
- **Bloque:** A3 · **Tipo:** real
- **Nota del esquema:** Acumulado
- **Unidad:** m
- **Procedencia:** FT-07 / derivado / A3 (18.368 celdas)
- **Válidos / NULL:** 18.368 / 0 (0.0 % NULL)
- **Rango:** mín 0 · p5 0 · mediana 13,24 · p95 284,2 · máx 2.273,49

## `cruza_portezuelo`

- **Qué es:** Indica si dentro del tramo hay un portezuelo: un punto alto del camino desde el cual se desciende más de 200 m hacia ambos lados.
- **De dónde sale:** Detectado sobre el perfil de altitud del camino.
- **Cómo leerlo:** TRUE marca tramos que atraviesan un paso de montaña propiamente tal (cruzan una divisoria). Es uno de los dos indicadores del criterio geomorfológico de inclusión.
- **Bloque:** A3 · **Tipo:** booleano
- **Nota del esquema:** Máximo local con descenso superior a 200 m hacia ambos lados.
- **Procedencia:** FT-07 / derivado / A3 (18.368 celdas)
- **Válidos / NULL:** 18.368 / 0 (0.0 % NULL)
- **Dominio observado:** TRUE 232 · FALSE 18.136

## `clase_kapos`

- **Qué es:** Clase de montaña según la clasificación de Kapos (usada por Naciones Unidas para definir zonas de montaña), evaluada en el punto más alto del tramo. Va de 1 (más de 4.500 m) a 6 (300 a 1.000 m con relieve marcado); 0 significa que no cumple ninguna condición de montaña.
- **De dónde sale:** Umbrales de altitud, pendiente y desnivel del entorno (radio 7 km) aplicados sobre el modelo de elevación.
- **Cómo leerlo:** Clases 1 a 5 son montaña por altitud (sobre 1.000 m con relieve); clase 6 es relieve montañoso bajo (cerros costeros, precordillera baja). La clase 7 (mesetas interiores aisladas) no se puede calcular con este método y no aparece.
- **Bloque:** A3 · **Tipo:** entero
- **Nota del esquema:** 0 a 7. Fuente FT-09, replicada sobre FT-07.
- **Procedencia:** FT-07;FT-09 / derivado / A3 (18.368 celdas)
- **Válidos / NULL:** 18.368 / 0 (0.0 % NULL)
- **Rango:** mín 0 · p5 0 · mediana 0 · p95 6 · máx 6
- **Dominio observado:**

| Valor | n |
|---|---:|
| 0 | 11.101 |
| 6 | 5.947 |
| 5 | 645 |
| 2 | 216 |
| 4 | 216 |
| 3 | 181 |
| 1 | 62 |


## `cota_max_z_mop`

- **Qué es:** Altitud máxima del tramo según la propia geometría de Vialidad (sus vértices traen una altura, medida con GPS entre 2000 y 2003).
- **De dónde sale:** Máximo de la coordenada Z de la capa de Vialidad.
- **Cómo leerlo:** Solo sirve como contraste con cota_max; no es la fuente de altitud de la base. Está vacío donde Vialidad entrega altura 0 en todos los vértices.
- **Bloque:** A3 · **Tipo:** real
- **Nota del esquema:** Cota máxima leída del Z de la geometría de A1. **Control cruzado, no fuente.**
- **Unidad:** msnm
- **Procedencia:** FT-07;FT-01 / derivado / A3 (16.153 celdas)
- **Válidos / NULL:** 16.153 / 2.215 (12.1 % NULL)
- **Rango:** mín -3,17 · p5 50 · mediana 250 · p95 1.414,68 · máx 5.188,34

## `delta_z_m`

- **Qué es:** Diferencia en metros entre la altitud máxima calculada con el modelo de elevación (cota_max) y la que trae Vialidad (cota_max_z_mop).
- **De dónde sale:** cota_max − cota_max_z_mop.
- **Cómo leerlo:** Valores cercanos a 0 dan confianza. Diferencias grandes (más de 50 m) sugieren un problema de geometría o que el modelo de elevación está leyendo la copa de los árboles sobre el camino; se reportan, no se corrigen.
- **Bloque:** A3 · **Tipo:** real
- **Nota del esquema:** `cota_max` menos `cota_max_z_mop`.
- **Unidad:** m
- **Procedencia:** FT-07;FT-01 / derivado / A3 (16.153 celdas)
- **Válidos / NULL:** 16.153 / 2.215 (12.1 % NULL)
- **Rango:** mín -970,42 · p5 -31,93 · mediana 0,4 · p95 20,76 · máx 604,62

## `provincia`

- **Qué es:** Provincia en la que se ubica el tramo.
- **De dónde sale:** Cruce espacial con los límites provinciales del INE (Censo 2017); si el tramo toca dos, se asigna la de mayor longitud.
- **Cómo leerlo:** A diferencia de region, sale de un cruce con mapas, no de un atributo de Vialidad.
- **Bloque:** A4 · **Tipo:** categórico
- **Nota del esquema:** Cruce espacial, no atributo declarado.
- **Procedencia:** FT-05 / derivado / A4 (18.360 celdas)
- **Válidos / NULL:** 18.360 / 8 (0.0 % NULL)
- **Valores distintos:** 55. Más frecuentes: `CAUTÍN` (1.580), `MALLECO` (851), `LINARES` (787), `CACHAPOAL` (781), `ITATA` (680)

## `comuna`

- **Qué es:** Comuna en la que se ubica el tramo.
- **De dónde sale:** Cruce espacial con los límites comunales del INE (Censo 2017); mayor longitud si toca más de una.
- **Cómo leerlo:** Está vacía en 8 pedazos muy cortos que caen fuera de todo polígono comunal (bordes costeros o de límite).
- **Bloque:** A4 · **Tipo:** categórico
- **Nota del esquema:** Cruce espacial.
- **Procedencia:** FT-05 / derivado / A4 (18.360 celdas)
- **Válidos / NULL:** 18.360 / 8 (0.0 % NULL)
- **Valores distintos:** 341. Más frecuentes: `COPIAPÓ` (235), `SAN CARLOS` (185), `LA UNIÓN` (157), `LINARES` (157), `PETORCA` (154)

## `es_paso`

- **Qué es:** Indica si el tramo pasa a menos de 500 m de un paso fronterizo oficial según DIFROL (Dirección Nacional de Fronteras y Límites).
- **De dónde sale:** Cruce espacial con la capa de pasos fronterizos de DIFROL, buffer de 500 m.
- **Cómo leerlo:** TRUE no significa que el paso sea vehicular ni que esté abierto: revísese paso_trafico y paso_habilitacion. Un camino cuyo trazado termina a más de 500 m del punto del paso queda FALSE.
- **Bloque:** A4 · **Tipo:** booleano
- **Procedencia:** FT-03a / derivado / A4 (18.368 celdas)
- **Válidos / NULL:** 18.368 / 0 (0.0 % NULL)
- **Dominio observado:** TRUE 50 · FALSE 18.318

## `paso_nombre`

- **Qué es:** Nombre oficial chileno del paso fronterizo asociado.
- **De dónde sale:** Copiado de la capa DIFROL.
- **Cómo leerlo:** Solo tiene valor cuando es_paso es TRUE.
- **Bloque:** A4 · **Tipo:** texto
- **Nota del esquema:** Denominación chilena oficial.
- **Procedencia:** FT-03a / declarado / A4 (50 celdas)
- **Válidos / NULL:** 50 / 18.318 (99.7 % NULL)
- **Valores distintos:** 43. Más frecuentes: `Concordia` (2), `Futaleufú` (2), `Las Pampas / Lago Verde` (2), `Pehuenche` (2), `Pino Hachado` (2)

## `paso_pais`

- **Qué es:** País con el que conecta el paso (Argentina, Bolivia o Perú).
- **De dónde sale:** Copiado de la capa DIFROL.
- **Cómo leerlo:** Solo cuando es_paso es TRUE.
- **Bloque:** A4 · **Tipo:** categórico
- **Procedencia:** FT-03a / declarado / A4 (50 celdas)
- **Válidos / NULL:** 50 / 18.318 (99.7 % NULL)
- **Dominio observado (3 valores):**

| Valor | n |
|---|---:|
| Argentina | 40 |
| Bolivia | 7 |
| Perú | 3 |


## `paso_trafico`

- **Qué es:** Tipo de tránsito permitido en el paso según DIFROL: personas, vehículos y carga; solo peatones; solo ganado y arrieros; gasoducto; etc.
- **De dónde sale:** Copiado de la capa DIFROL.
- **Cómo leerlo:** Permite distinguir pasos vehiculares de los que no lo son. La base conserva todos; el filtro se hace en el análisis.
- **Bloque:** A4 · **Tipo:** texto
- **Nota del esquema:** Tipo de tráfico permitido.
- **Procedencia:** FT-03a / declarado / A4 (50 celdas)
- **Válidos / NULL:** 50 / 18.318 (99.7 % NULL)
- **Dominio observado (7 valores):**

| Valor | n |
|---|---:|
| Personas, vehículos y carga | 41 |
| Paso de gasoducto | 2 |
| Solo cruce de peatones | 2 |
| Solo cruce de peatones y vehículos particulares | 2 |
| Solo a personal peruano de canales Uchusuma y Mauri | 1 |
| Solo paso de personas y operaciones de admisión y salida temporal de mercancías por turistas | 1 |
| Solo peatones e importación de mineral de azufre boliviano | 1 |


## `paso_habilitacion`

- **Qué es:** Régimen de apertura del paso: Permanente, Temporal (solo parte del año) u Ocasional.
- **De dónde sale:** Copiado de la capa DIFROL (Acuerdo de Apertura y Cierre).
- **Cómo leerlo:** "Temporal" suele corresponder a pasos que cierran en invierno.
- **Bloque:** A4 · **Tipo:** texto
- **Nota del esquema:** Según Acuerdo de Apertura y Cierre.
- **Procedencia:** FT-03a / declarado / A4 (50 celdas)
- **Válidos / NULL:** 50 / 18.318 (99.7 % NULL)
- **Dominio observado (2 valores):**

| Valor | n |
|---|---:|
| Permanente | 47 |
| Temporal | 3 |


## `dist_limite_m`

- **Qué es:** Distancia en metros desde el extremo más cercano del tramo hasta la línea del límite internacional.
- **De dónde sale:** Distancia mínima de los extremos del tramo a la capa de límite internacional de DIFROL (escala 1:50.000).
- **Cómo leerlo:** Valores pequeños indican tramos que llegan hasta la frontera. La precisión del límite es de unas decenas de metros.
- **Bloque:** A4 · **Tipo:** real
- **Nota del esquema:** Distancia del extremo del tramo al límite internacional.
- **Unidad:** m
- **Procedencia:** FT-03b / derivado / A4 (18.368 celdas)
- **Válidos / NULL:** 18.368 / 0 (0.0 % NULL)
- **Rango:** mín 0,2 · p5 33.567,93 · mediana 99.877,1 · p95 168.652 · máx 257.870,1

## `en_zona_fronteriza`

- **Qué es:** Indica si el tramo está dentro de la "zona fronteriza", franja administrativa donde DIFROL debe autorizar ciertos actos (compra de tierras, obras).
- **De dónde sale:** Cruce con un polígono construido a partir de la línea de zona fronteriza de DIFROL, cerrado con el límite internacional; como esa construcción añade segmentos que no vienen en la fuente, el método es "estimado".
- **Cómo leerlo:** Es contexto administrativo, no un indicador de montaña ni de nieve. No se usa como criterio de inclusión.
- **Bloque:** A4 · **Tipo:** booleano
- **Nota del esquema:** FT-03c se entrega como líneas, no polígonos. El polígono se construye cerrando la línea interior con FT-03b, más un segmento recto de 62 km en el hueco del límite argentino y un cierre marítimo al norte; por esa geometría añadida el método es `estimado` (decisión del orquestador 2026-08-26, detalle en `src/03_derivacion/a4_destinos.R`).
- **Procedencia:** FT-03c / estimado / A4 (18.368 celdas)
- **Válidos / NULL:** 18.368 / 0 (0.0 % NULL)
- **Dominio observado:** TRUE 2.783 · FALSE 15.585

## `es_esqui`

- **Qué es:** Indica si el tramo pasa a menos de 500 m de un centro de esquí registrado en el inventario de atractivos turísticos de SERNATUR.
- **De dónde sale:** Cruce espacial con puntos de SERNATUR (subtipo "Área Nevada" con nombre de centro de esquí).
- **Cómo leerlo:** Marca los caminos de acceso a centros de esquí. Los caminos internos del centro (no enrolados) no están en la base.
- **Bloque:** A4 · **Tipo:** booleano
- **Procedencia:** FT-06 / derivado / A4 (18.368 celdas)
- **Válidos / NULL:** 18.368 / 0 (0.0 % NULL)
- **Dominio observado:** TRUE 16 · FALSE 18.352

## `esqui_nombre`

- **Qué es:** Nombre del centro de esquí asociado.
- **De dónde sale:** Copiado del inventario de SERNATUR.
- **Cómo leerlo:** Solo cuando es_esqui es TRUE.
- **Bloque:** A4 · **Tipo:** texto
- **Procedencia:** FT-06 / declarado / A4 (16 celdas)
- **Válidos / NULL:** 16 / 18.352 (99.9 % NULL)
- **Dominio observado (12 valores):**

| Valor | n |
|---|---:|
| Centro De Esqui Farellones | 4 |
| Centro De Esqui El Colorado | 2 |
| Centro De Esqui Antillanca | 1 |
| Centro De Esqui Antuco | 1 |
| Centro De Esqui El Fraile | 1 |
| Centro De Esqui Lagunillas | 1 |
| Centro De Esqui Las Araucarias | 1 |
| Centro De Esqui Los Arenales | 1 |
| Centro De Esqui Valle Nevado | 1 |
| Centro De Esqui Volcan Osorno | 1 |
| Centro Esqui Termas Chillan | 1 |
| Complejo Invernal Portillo | 1 |


## `esqui_cota_base`

- **Qué es:** Altitud de la base del centro de esquí según SERNATUR. NO es una altitud del camino: se guarda solo para comprobar que la cota del camino no la supere.
- **De dónde sale:** Debía copiarse del inventario de SERNATUR.
- **Cómo leerlo:** La fuente no trae este dato, por eso está vacía en todas las filas y la comprobación de coherencia no pudo hacerse.
- **Bloque:** A4 · **Tipo:** real
- **Nota del esquema:** **No es una cota del camino.** Se guarda solo para la aserción de coherencia.
- **Unidad:** msnm
- **Procedencia:** sin filas (llave o columna vacía)
- **Válidos / NULL:** 0 / 18.368 (100.0 % NULL)

## `es_localidad`

- **Qué es:** Indica si el tramo pasa a menos de 500 m de una localidad poblada del INE (ciudad, pueblo, aldea o caserío del Censo 2017).
- **De dónde sale:** Cruce espacial con las entidades pobladas del INE.
- **Cómo leerlo:** TRUE en aproximadamente la mitad de los tramos; no distingue el tamaño de la localidad.
- **Bloque:** A4 · **Tipo:** booleano
- **Procedencia:** FT-05 / derivado / A4 (18.368 celdas)
- **Válidos / NULL:** 18.368 / 0 (0.0 % NULL)
- **Dominio observado:** TRUE 9.290 · FALSE 9.078

## `localidad_nombre`

- **Qué es:** Nombre de la localidad poblada asociada.
- **De dónde sale:** Copiado de la capa del INE.
- **Cómo leerlo:** Solo cuando es_localidad es TRUE.
- **Bloque:** A4 · **Tipo:** texto
- **Procedencia:** FT-05 / declarado / A4 (9.290 celdas)
- **Válidos / NULL:** 9.290 / 9.078 (49.4 % NULL)
- **Valores distintos:** 2.502. Más frecuentes: `CHUPALLAR ALTO` (55), `LIMACHE` (52), `LAS CONDES` (44), `HUECHURABA` (34), `SAN JUAN` (32)

## `dist_servicios_km`

- **Qué es:** Distancia en kilómetros desde el tramo hasta la localidad con servicios más cercana, entendiendo por "con servicios" las entidades que el INE clasifica como CIUDAD o PUEBLO (no aldeas ni caseríos).
- **De dónde sale:** Distancia mínima del tramo a los polígonos de ciudades y pueblos del INE.
- **Cómo leerlo:** Indicador del criterio funcional de inclusión: cuánto hay que recorrer para encontrar abastecimiento, salud o auxilio. 0 significa que el tramo toca la ciudad o pueblo.
- **Bloque:** A4 · **Tipo:** real
- **Nota del esquema:** Distancia a la localidad con servicios más cercana. Nivel 3 del criterio de inclusión.
- **Unidad:** km
- **Procedencia:** FT-05 / derivado / A4 (18.368 celdas)
- **Válidos / NULL:** 18.368 / 0 (0.0 % NULL)
- **Rango:** mín 0 · p5 0 · mediana 5,82 · p95 39,24 · máx 179,04

## `buffer_join_m`

- **Qué es:** Radio en metros usado para decidir si un paso, centro de esquí o localidad "está sobre" el tramo.
- **De dónde sale:** Parámetro fijado en 500 m (escala de las fuentes DIFROL).
- **Cómo leerlo:** Se guarda para que cualquiera pueda reproducir el resultado. Cambiar el radio cambia es_paso, es_esqui y es_localidad.
- **Bloque:** A4 · **Tipo:** entero
- **Nota del esquema:** Radio usado en el cruce. Se guarda para poder reproducir el resultado.
- **Unidad:** m
- **Procedencia:** — / derivado / A4 (18.368 celdas)
- **Válidos / NULL:** 18.368 / 0 (0.0 % NULL)
- **Rango:** mín 500 · p5 500 · mediana 500 · p95 500 · máx 500
- **Dominio observado:**

| Valor | n |
|---|---:|
| 500 | 18.368 |


## `tmda`

- **Qué es:** Tránsito Medio Diario Anual: cantidad promedio de vehículos que pasan por día en el punto de conteo asociado al tramo, según el Plan Nacional de Censos de Vialidad.
- **De dónde sale:** Del punto censal más cercano que mide el mismo rol; año más reciente disponible (planillas 2024/2025 o servicio REST 2014–2023).
- **Cómo leerlo:** Vacío en el 90 % de los tramos: la mayoría no tiene un punto de conteo sobre su propio camino, o el punto mide dos sentidos sin poder distinguirlos. Mírese siempre junto con dist_punto_censal_m.
- **Bloque:** A5 · **Tipo:** entero
- **Nota del esquema:** Del punto censal asociado.
- **Unidad:** veh/día
- **Procedencia:** FT-02 / declarado / A5 (1.850 celdas)
- **Válidos / NULL:** 1.850 / 16.518 (89.9 % NULL)
- **Rango:** mín 0 · p5 56,45 · mediana 783 · p95 8.885,1 · máx 45.390

## `tmda_invierno`

- **Qué es:** Vehículos promedio por día medidos en la muestra de junio (invierno) del mismo punto censal.
- **De dónde sale:** Muestra "I" (invierno) de las planillas del Plan Nacional de Censos.
- **Cómo leerlo:** Es el tránsito en la época de nieve, de interés prioritario para caminos de montaña. Solo existe donde el dato viene de planilla (2024/2025).
- **Bloque:** A5 · **Tipo:** entero
- **Nota del esquema:** Muestra de junio.
- **Unidad:** veh/día
- **Procedencia:** FT-02 / declarado / A5 (1.369 celdas)
- **Válidos / NULL:** 1.369 / 16.999 (92.5 % NULL)
- **Rango:** mín 0 · p5 32,8 · mediana 620 · p95 5.407,4 · máx 33.727

## `tmda_composicion`

- **Qué es:** Desglose del tránsito por tipo de vehículo (autos, camionetas, buses, camiones de 2 ejes, de más de 2 ejes, etc.).
- **De dónde sale:** Copiado de la planilla del Plan Nacional de Censos.
- **Cómo leerlo:** Texto con los conteos por categoría tal como los entrega la planilla.
- **Bloque:** A5 · **Tipo:** texto
- **Nota del esquema:** Desglose por tipo de vehículo, si la planilla lo trae.
- **Procedencia:** FT-02 / declarado / A5 (1.363 celdas)
- **Válidos / NULL:** 1.363 / 17.005 (92.6 % NULL)
- **Valores distintos:** 665. Más frecuentes: `AUTOS=60.09|CAMIONETAS=27.02|CAMIONES 2 EJES=6.73|CAMIONES MAS 2 EJES=0.50|SEMI REMOLQUE=0.00|REMOLQUE=0.06|LOCOMOCION COLECTIVA=1.92|MOTOS=2.04|BICICLETAS=0.96|TRACCION ANIMAL=0.31|VARIOS=0.37` (49), `AUTOS=25.88|CAMIONETAS=47.40|CAMIONES 2 EJES=11.65|CAMIONES MAS 2 EJES=2.67|SEMI REMOLQUE=3.38|REMOLQUE=3.21|LOCOMOCION COLECTIVA=0.74|MOTOS=0.74|BICICLETAS=1.98|TRACCION ANIMAL=1.98|VARIOS=0.37` (27), `AUTOS=38.83|CAMIONETAS=45.74|CAMIONES 2 EJES=6.75|CAMIONES MAS 2 EJES=4.01|SEMI REMOLQUE=0.88|REMOLQUE=1.44|LOCOMOCION COLECTIVA=1.04|MOTOS=0.50|BICICLETAS=0.27|TRACCION ANIMAL=0.00|VARIOS=0.55` (27), `AUTOS=23.24|CAMIONETAS=40.21|CAMIONES 2 EJES=4.96|CAMIONES MAS 2 EJES=8.09|SEMI REMOLQUE=1.04|REMOLQUE=22.45|LOCOMOCION COLECTIVA=0.00|MOTOS=0.00|BICICLETAS=0.00|TRACCION ANIMAL=0.00|VARIOS=0.00` (22), `AUTOS=42.64|CAMIONETAS=42.62|CAMIONES 2 EJES=5.68|CAMIONES MAS 2 EJES=4.15|SEMI REMOLQUE=0.00|REMOLQUE=1.57|LOCOMOCION COLECTIVA=0.00|MOTOS=0.80|BICICLETAS=1.74|TRACCION ANIMAL=0.00|VARIOS=0.80` (18)

## `punto_censal_id`

- **Qué es:** Código de la estación de conteo de tránsito asociada al tramo (formato región-número, por ejemplo "07-159").
- **De dónde sale:** Estación más cercana al tramo entre las del servicio de Vialidad.
- **Cómo leerlo:** Siempre está lleno, aunque tmda esté vacío: identifica cuál estación se consideró.
- **Bloque:** A5 · **Tipo:** texto
- **Procedencia:** FT-02 / declarado / A5 (18.368 celdas)
- **Válidos / NULL:** 18.368 / 0 (0.0 % NULL)
- **Valores distintos:** 2.130. Más frecuentes: `05-140` (193), `05-125` (157), `13-160` (124), `05-150` (106), `01-036` (101)

## `dist_punto_censal_m`

- **Qué es:** Distancia en metros entre el tramo y la estación de conteo asociada.
- **De dónde sale:** Distancia mínima del tramo al punto de la estación.
- **Cómo leerlo:** Fundamental para juzgar el TMDA: una estación a 200 m describe bien el tramo; una a 40 km, no. La base no filtra por distancia; el análisis debe hacerlo.
- **Bloque:** A5 · **Tipo:** real
- **Nota del esquema:** **Crítica.** Un punto censal a 40 km no describe este tramo.
- **Unidad:** m
- **Procedencia:** FT-02 / derivado / A5 (18.368 celdas)
- **Válidos / NULL:** 18.368 / 0 (0.0 % NULL)
- **Rango:** mín 0 · p5 3,05 · mediana 4.766,87 · p95 19.667,21 · máx 127.578,5

## `tmda_anio`

- **Qué es:** Año en que se midió el tránsito registrado en tmda.
- **De dónde sale:** De la planilla o capa de origen.
- **Cómo leerlo:** Los conteos se hacen cada dos años por zona (norte en años impares, sur en pares); los datos van de 2014 a 2025.
- **Bloque:** A5 · **Tipo:** entero
- **Nota del esquema:** Año del levantamiento.
- **Procedencia:** FT-02 / declarado / A5 (4.558 celdas)
- **Válidos / NULL:** 4.558 / 13.810 (75.2 % NULL)
- **Rango:** mín 2.014 · p5 2.016 · mediana 2.024 · p95 2.025 · máx 2.025
- **Dominio observado:**

| Valor | n |
|---|---:|
| 2024 | 2.106 |
| 2025 | 1.068 |
| 2016 | 930 |
| 2017 | 168 |
| 2020 | 118 |
| 2023 | 69 |
| 2022 | 38 |
| 2018 | 27 |
| 2014 | 21 |
| 2021 | 12 |
| 2019 | 1 |


## `match_metodo`

- **Qué es:** Cómo se asoció la estación de conteo al tramo: "espacial" (la más cercana en el mapa) o "rol_kilometraje" (por código de camino y kilómetro).
- **De dónde sale:** Asignado durante el cruce.
- **Cómo leerlo:** En esta fase todos los cruces fueron espaciales.
- **Bloque:** A5 · **Tipo:** categórico
- **Nota del esquema:** `espacial` o `rol_kilometraje`.
- **Procedencia:** FT-02 / derivado / A5 (18.368 celdas)
- **Válidos / NULL:** 18.368 / 0 (0.0 % NULL)
- **Dominio observado (1 valores):**

| Valor | n |
|---|---:|
| espacial | 18.368 |


