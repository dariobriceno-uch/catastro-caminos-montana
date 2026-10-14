# Catastro de caminos de montaña — FONDEF IDeA

Repositorio de construcción de la base de datos nacional de caminos de montaña.
Este archivo define reglas obligatorias. Aplican a todos los agentes, en todas
las tareas, sin excepción.

---

## Regla 1 — Prohibición de dato no derivado

**Ningún valor puede escribirse en la base si no proviene de un archivo presente
en `data/raw/`.**

Esto incluye, explícitamente:

- Altitudes, cotas, pendientes. Solo salen del DEM sobre la geometría descargada.
- Roles, nombres de ruta, clasificaciones. Solo salen de la capa de Vialidad.
- Pasos fronterizos y sus atributos. Solo salen de la capa de DIFROL.
- Regiones, provincias, comunas. Solo salen del cruce espacial con límites INE.

Está prohibido usar conocimiento propio sobre geografía, rutas o infraestructura
de Chile para completar, corregir o estimar un valor. Si sabes que Valle Nevado
está a 3.025 m, ese conocimiento no entra a la base.

**Si un valor no se puede derivar, se escribe `NULL` y se registra la fila en
`data/vacios.csv` con el motivo.** Una celda vacía es un resultado válido y
esperado. Una celda inventada invalida el catastro completo.

## Regla 2 — Procedencia por campo

Toda variable derivada lleva tres columnas asociadas:

- `<campo>_fuente` — identificador de la fuente en `docs/fuentes.md`
- `<campo>_fecha` — fecha de descarga del insumo del que se derivó
- `<campo>_metodo` — uno de: `derivado` | `declarado` | `estimado`

`derivado` significa calculado por código sobre un raster o vector.
`declarado` significa copiado tal cual de un atributo de la fuente.
`estimado` requiere que el método esté documentado en el commit.

No existe un cuarto valor. Si no calza en ninguno, el campo va `NULL`.

## Regla 3 — `data/raw/` es de solo lectura

Los agentes descargan a `data/raw/` y nunca la modifican después. Cada descarga
registra en `data/raw/manifest.json` la URL exacta, el timestamp, el número de
registros y el hash SHA-256 del archivo.

Toda transformación va a `data/interim/`. El producto final va a
`data/processed/`.

## Regla 4 — Propiedad de columnas

Cada agente escribe únicamente el conjunto de columnas que le corresponde, según
`docs/esquema.md`. Ningún agente modifica columnas ajenas, ni siquiera para
corregir un valor que considere erróneo. Los errores se reportan, no se arreglan
fuera de dominio.

## Regla 5 — La validación tiene veto

`tests/` corre después de cada etapa. Si una aserción falla, la etapa no se da
por cerrada. No se avanza a la siguiente etapa con aserciones en rojo, y no se
desactiva ni se relaja una aserción para poder avanzar.

## Regla 6 — El archivo del colega es hipótesis, no dato

`reference/candidatos_colega.xlsx` contiene una lista de rutas propuesta a mano,
con errores demostrados en sus altitudes. Se usa **solo** como lista de
candidatos a verificar. Nunca como fuente de un valor, ni para completar celdas,
ni para decidir qué es correcto cuando hay discrepancia.

Cuando un tramo derivado coincida con un candidato de esa lista, se marca
`en_lista_colega = TRUE`. Cuando un candidato no aparezca en el resultado
derivado, se registra en `data/vacios.csv` para revisión humana.

---

## Unidad de análisis

La fila es el **tramo**, no el camino. Un rol se segmenta cuando cambia la
comuna, cambia el tipo de carpeta, o hay un punto de control identificado.
Nunca se guarda una ruta completa como una sola fila.

## Estructura

```
├── REGLAS.md
├── docs/
│   ├── esquema.md              diccionario de variables y propiedad por agente
│   ├── fuentes.md              catálogo de fuentes con URL y vigencia
│   ├── libro_codigos.md        libro de códigos de la base final
│   └── visor_tramos.html       visor autocontenido de los tramos
├── data/
│   ├── raw/                    descargas intactas + manifest.json
│   ├── interim/                productos intermedios (no se publican; se regeneran)
│   ├── processed/
│   └── vacios.csv              todo lo que no se pudo derivar
├── src/
│   ├── 01_descarga/
│   ├── 02_segmentacion/
│   ├── 03_derivacion/
│   └── 04_ensamblaje/
├── tests/
└── logs/
```

## Criterio de inclusión

Tres niveles, todos como columna. Ninguno descarta filas, todos etiquetan.

1. **Geomorfológico.** Cota máxima del tramo en clases Kapos 1–5, o el tramo
   cruza un portezuelo (máximo local con descenso superior a 200 m hacia ambos
   lados).
2. **Nival.** Días al año con cobertura de nieve sobre el tramo, mediana de una
   serie de 15 años o más.
3. **Funcional.** Distancia entre localidades con servicios a lo largo del
   tramo.

El corte se decide después, sobre la base completa. No se filtra durante la
construcción.

## Fallas conocidas a evitar

Estas ya ocurrieron en la versión manual del catastro.

- Asignar al camino la cota de cumbre de un centro de esquí. El camino termina
  en la base, no en el punto más alto del andarivel.
- Registrar altitudes distintas para el mismo objeto en tablas distintas.
- Escribir una metodología SIG que no se ejecutó y publicar una tabla sin
  geometría, sin kilometraje y sin longitud.
- Incluir pasos no vehiculares en un catastro vial.
- Etiquetar un porcentaje calculado sobre la muestra como porcentaje nacional.
