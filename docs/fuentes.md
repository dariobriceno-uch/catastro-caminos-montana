# Catálogo de fuentes

Identificadores a los que apunta la Regla 2 de `REGLAS.md`. Toda celda de la base
declara uno de estos códigos.

Antes de usar cualquier fuente, verificar la URL y anotar la fecha real de
descarga en `data/raw/manifest.json`. Las vigencias declaradas abajo son las que
publica cada organismo y pueden haber cambiado.

## Estado

| Código | Fuente | Estado |
|---|---|---|
| FT-01 | Red Vial Nacional | Vía REST, no requiere descarga previa |
| FT-02 | Plan Nacional de Censos | Descargado |
| FT-03a | Pasos fronterizos | Descargado |
| FT-03b | Límite internacional | Descargado |
| FT-03c | Zona fronteriza | Descargado |
| FT-04 | Complejos fronterizos | No usado en fase 1 |
| FT-05 | Localidades y límites INE | **Pendiente de descarga** |
| FT-06 | Centros invernales | **Pendiente de descarga** |
| FT-07 | DEM | Lo baja el script |
| FT-08 | Cobertura nival | En curso (EE, por regiones) |
| FT-09 | Clasificación Kapos | Se replica sobre FT-07 |
| FT-10 | Unidades geomorfológicas | Descargado (manual); URL pendiente en manifest |
| FT-12 | Centros de esquí OSM | Descargado (Overpass), complementa FT-06 |

---

## FT-01 — Red Vial Nacional (Dirección de Vialidad, MOP)

- **Endpoint:** `https://rest-sit.mop.gob.cl/arcgis/rest/services/VIALIDAD/Red_Vial_Chile/MapServer`
- **Capa a usar:** la 3. Las capas 0, 1 y 2 son generalizaciones para despliegue a distintas escalas y tienen geometría simplificada.
- **Visor:** `https://sitministerial.maps.arcgis.com/apps/webappviewer/index.html?id=ccc8ce73d80d4b48a4cbce97ff89d74c`
- **Alimenta:** bloque A1.

**Parámetros técnicos verificados.**

- `MaxRecordCount` es 1000. La paginación va de mil en mil con `resultOffset`.
- Formatos soportados: JSON y AMF. **No hay GeoJSON.** Pedir `f=json` en Esri JSON y convertir.
- Proyección EPSG:5360 (SIRGAS-Chile), en **grados decimales**. Es geográfica, no proyectada. Toda longitud o pendiente exige proyectar antes a UTM 18S o 19S.
- `HasZ: true` y `HasM: true`. La geometría trae cota. Ver la decisión sobre el Z en `esquema.md`, bloque A3.
- El extent llega a -109° de longitud, o sea incluye Isla de Pascua. Filtrarla.

**Vigencia y limitaciones.** El levantamiento base es GNSS entre 2000 y 2003, con
los Caminos Básicos actualizados a agosto de 2015 y la red actualizada al año
2017. Escala aproximada entre 1:10.000 y 1:25.000 según región. El MOP declara la
capa como documento de trabajo y base dinámica en depuración permanente, y
declara además que **no representa la naturaleza jurídica de los caminos
graficados**.

**Limitación de cobertura, la más importante.** Contiene caminos de tuición del
Ministerio de Obras Públicas. Accesos mineros privados, caminos internos de
centros de esquí y huellas comunales no están.

---

## FT-02 — Plan Nacional de Censos (Dirección de Vialidad, MOP)

- **Planillas:** descargadas, en la carpeta de censo nacional. Fuente primaria.
- **Endpoint de respaldo:** `https://rest-sit.mop.gob.cl/arcgis/rest/services/VIALIDAD/Plan_Nacional_de_Censos/MapServer`
- **Ficha:** `https://vialidad.mop.gob.cl/plan-nacional-de-censo-vial/`
- **Alimenta:** bloque A5.

Las planillas suelen traer el detalle por muestra y por composición de flujo, que
el servicio REST no expone. El REST queda como respaldo para obtener las
coordenadas de los puntos censales si las planillas no las traen.

**Vigencia.** Levantamientos entre 2014 y 2018, información actualizada a julio
de 2019. Anotarlo en `tmda_anio` y no presentarlo como dato actual.

**Vigencia verificada 2026-08-26 (A5).** Las planillas descargadas corresponden a
los años 2024 (zona sur) y 2025 (zona norte), y el servicio REST expone siete capas
por bienio entre 2014 y 2025. La ficha oficial está desactualizada; `tmda_anio`
registra el año real de cada dato.

**Diseño del muestreo.** Los datos se recopilan en años pares en la zona sur
(Maule a Magallanes) y en años impares en la zona norte (Arica y Parinacota a
O'Higgins). Cada año contempla tres muestras, en febrero, junio y octubre. La
muestra de junio es tránsito invernal medido y es la de mayor interés para el
proyecto.

**Advertencia de uso.** El punto censal no coincide con el tramo. Guardar siempre
`dist_punto_censal_m` y descartar asociaciones lejanas en el análisis, no en la
base.

---

## FT-03 — Capas territoriales (DIFROL)

- **Descarga:** `https://www.difrol.cl/mapas/`
- **Formato:** shapefile. Escala autorizada 1:50.000.
- **Estado:** las tres capas están descargadas.

### FT-03a — Pasos fronterizos

Alimenta `es_paso` y atributos asociados, bloque A4.

Trae nombre del paso según denominación chilena, habilitación según Acuerdo de
Apertura y Cierre, tipo de tráfico permitido y país limítrofe.

**Referencia de cobertura.** Chile tiene 64 pasos fronterizos habilitados con
Argentina, Bolivia y Perú, incluyendo terrestres, fluviales y fluviales con
puente. Solo los terrestres corresponden a este catastro. La cifra sirve como
control de completitud, no como meta a alcanzar.

### FT-03b — Límite internacional

Alimenta `dist_limite_m`, bloque A4.

### FT-03c — Zona fronteriza

Alimenta `en_zona_fronteriza`, bloque A4.

Es una capa administrativa. Delimita dónde DIFROL debe autorizar ciertos actos
jurídicos. No es indicador de montaña ni de exposición nival, y no debe usarse
como criterio de inclusión. Se guarda porque es contexto barato de agregar.

---

## FT-04 — Complejos Fronterizos (Unidad de Pasos Fronterizos, Ministerio del Interior)

- **Sitio:** `https://www.pasosfronterizos.gov.cl/complejos-fronterizos/`
- **Formato:** web, sin API conocida.
- **Alimenta:** nada en fase 1.

Es la fuente del régimen operativo real de cada complejo. No es descargable de
forma estructurada, así que queda fuera de la derivación automática. Se registra
acá para que quede claro que existe y por qué no se usó todavía.

---

## FT-05 — Geoportal IDE Chile

- **Sitio:** `https://geoportal.cl/`
- **Estado:** pendiente de descarga.
- **Alimenta:** bloque A4.

Capas de interés: localidades pobladas del INE, límites comunales y
provinciales, áreas protegidas SNASPE.

**Advertencia.** `region` viene declarada desde FT-01 y `provincia` y `comuna`
salen de cruce espacial con esta fuente. Si hay discrepancia entre ambas, se
reporta, no se corrige.

---

## FT-06 — Centros invernales (SERNATUR)

- **Estado:** pendiente de descarga.
- **Alimenta:** bloque A4.

**Advertencia crítica, y es el error que hay que evitar.** La cota base y la cota
máxima de un centro de esquí describen el dominio esquiable, no el camino. El
camino termina en la base. La cota máxima corresponde al punto más alto servido
por andariveles y no es accesible en vehículo. Nunca asignar una de estas cifras
a una columna de altitud del tramo.

En la versión manual del catastro, once de quince caminos a centros de esquí
tenían la cota de cumbre del centro escrita como altitud del camino. Esa es la
falla que esta advertencia existe para prevenir.

---

## FT-07 — Modelo digital de elevación

- **Producto:** Copernicus DEM GLO-30.
- **Acceso:** bucket público de AWS, sin autenticación. `aws s3 ls s3://copernicus-dem-30m/`
- **Formato:** Cloud Optimized GeoTIFF.
- **Alimenta:** bloque A3, en exclusiva.

Toda cota, pendiente, orientación y desnivel de este repositorio nace acá.

**Implementación recomendada.** Al ser COG, no hace falta descargar teselas
completas. Leer con `/vsicurl/` solo los píxeles bajo la traza del camino. Evita
arrastrar varios gigas de ráster en el repositorio y hace el proceso reproducible.

**Tres advertencias.**

GLO-30 Public tiene cobertura mundial limitada, porque un subconjunto de teselas
de ciertos países todavía no se libera al público. Verificar que Chile esté
completo antes de asumirlo. Hay una lista publicada de teselas no liberadas.

Es un modelo digital de **superficie**, no de terreno. Incluye vegetación y
edificaciones. Sobre la línea de árboles da igual, pero en tramos del sur con
bosque denso sobre el camino puede estar leyendo dosel en vez de calzada. Es
precisamente lo que debería detectar el contraste con el Z de FT-01.

La alternativa ALOS PALSAR de 12,5 m requiere cuenta de NASA Earthdata y su DEM
podría estar remuestreado desde fuentes de 30 m, lo que haría aparente la
resolución extra. Verificarlo antes de preferirla sobre GLO-30.

Registrar en el manifest qué DEM se usó. Cambiar de DEM a mitad de camino produce
discontinuidades que después nadie sabe explicar.

---

## FT-08 — Cobertura nival

**En curso desde 2026-08-27.** Proyecto EE `earth-engine-nieve`, registrado para
uso no comercial con correo institucional. Método y columnas en `docs/esquema.md`,
bloque A7. Scripts: `src/01_descarga/a7_nieve_ee.py` (lanza y exporta a Drive) y
`src/03_derivacion/a7_nieve.R` (deriva las columnas desde los CSV crudos).

Lo que sigue es el texto original de la postergación, conservado como historia.

El producto previsto era MOD10A1 vía Google Earth Engine, con serie mínima de 15
años, para alimentar el nivel 2 del criterio de inclusión.

El bloqueo es el registro. Earth Engine exige un proyecto de Google Cloud con la
API habilitada y registrado para uso no comercial, con cuestionario obligatorio
desde el 26 de septiembre de 2025. El uso académico califica como no comercial y
es gratuito, y conviene usar correo institucional para la verificación.

Al retomarlo, considerar que los proyectos no comerciales quedan por defecto en
el Community Tier y que las cuotas por tier rigen desde el 27 de abril de 2026.
Una reducción de veinte años de MODIS diario sobre toda la red nacional puede
exceder esa cuota. Mitigación: procesar por región y guardar resultados
parciales.

Limitación conocida del producto. La resolución de MODIS es de 500 m, gruesa
frente al ancho de un camino. El valor describe el entorno del tramo, no la
calzada.

Mientras esté postergado, el nivel nival del criterio de inclusión queda vacío.
No se sustituye por un proxy altimétrico.

---

## FT-09 — Clasificación de montaña (Kapos / UNEP-WCMC)

- **Alimenta:** `clase_kapos`, bloque A3.

Umbrales. Clase 1 sobre 4.500 m. Clase 2 entre 3.500 y 4.500. Clase 3 entre 2.500
y 3.500. Clase 4 entre 1.500 y 2.500 con pendiente mayor o igual a 2°. Clase 5
entre 1.000 y 1.500 con pendiente mayor o igual a 5° o rango altitudinal local en
radio de 7 km superior a 300 m. Clase 6 entre 300 y 1.000 m con rango altitudinal
local superior a 300 m. Clase 7 para cuencas y mesetas interiores aisladas
menores a 25 km² rodeadas de montañas.

**Decisión de implementación.** Replicar la regla sobre FT-07 en vez de usar el
raster global. El original se derivó de GTOPO30 a 1 km, demasiado grueso para
tramos viales.

## FT-10 — Unidades geomorfológicas de Chile (Börgel)

- **Alimenta:** `unidad_geomorf`, `n_unidades_geomorf`, `vertiente`, bloque A6.
- **Formato:** Shapefile, 116 multipolígonos, 41 unidades, EPSG:3857.
- **Ubicación:** `data/raw/Unidades Geomorfologicas/`.
- **Descarga:** manual, 2026-08-27. **URL exacta pendiente de registrar en
  `data/raw/manifest/A6.json`** (exportación ArcGIS Hub; el CSV de atributos
  del mismo origen está en `data/raw/` y no sirve solo: no trae geometría).
- **Metadato:** el XML adjunto declara el título y fecha 2020-06-30, sin autor
  ni URL. Es la clasificación de macroformas de Börgel (1983).

**Decisión de implementación.** Se guarda el nombre de la unidad tal cual. La
agrupación en vertientes es del proyecto y vive en `docs/esquema.md`, bloque A6.
8 de los 116 polígonos vienen inválidos y se reparan con `st_make_valid` antes
del cruce.

## FT-12 — Centros de esquí en OpenStreetMap (complementaria de FT-06)

- **Alimenta:** `es_esqui`, `esqui_nombre`, bloque A4, sólo para completar lo
  que FT-06 omite. Donde ambas tienen el mismo centro (a menos de 1,5 km),
  manda FT-06.
- **Formato:** JSON de Overpass API; nodos y áreas con `landuse=winter_sports`
  o `sport=skiing` con nombre, y estaciones de andarivel.
- **Ubicación:** `data/raw/osm_esqui/`, consulta exacta y sha256 en
  `data/raw/manifest/A4_osm.json`. Script: `src/01_descarga/a4_descarga_osm_esqui.py`.
- **Licencia:** ODbL 1.0, © colaboradores de OpenStreetMap. Reutilizable con
  atribución.
- **Vigencia:** la del timestamp de la base OSM registrado en el manifiesto.

**Por qué existe.** FT-06 (2020) no trae La Parva como punto propio y ubica
Corralco, Villarrica, Chapa Verde y Cerro Mirador lejos del camino de acceso.
OSM trae 15 centros con coordenadas. Ninguna de las dos fuentes abiertas
incluye Bosque Nevado Huilo Huilo, que queda en `vacios`.

**Fuente descartada: Snow-Forecast (Meteo365 Ltd).** Trae los 17 centros con
cota base y cumbre, pero sus términos de uso prohíben reutilizar y redistribuir
el contenido. Se usa sólo como lista de hipótesis a verificar, igual que
`reference/candidatos_colega.xlsx` (Regla 6). Ningún valor sale de ahí.

---

## Fuentes descartadas en fase 1

Se documentan para que nadie las incorpore sin discusión previa.

- **SERNAGEOMIN**, susceptibilidad a remociones en masa. Fase de riesgo.
- **DGA**, rutas de nieve y estaciones nivométricas. Fase de riesgo.
- **DMC**, series meteorológicas. Fase de riesgo.
- **Aduanas**, carga por paso fronterizo. Útil para criticidad, pero requiere
  gestión institucional y no está disponible como descarga directa.
