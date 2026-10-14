# Visor de tramos — `docs/visor_tramos.html`

Un solo archivo HTML con los 18.368 tramos de `data/processed/tramos.parquet`:
tabla filtrable, mapa y ficha por tramo. Se abre con doble clic. **No necesita
servidor, ni internet, ni instalar nada.**

El visor **no deriva ningún valor**. Copia lo que ya está en la base y muestra la
procedencia de cada campo. Una celda vacía en el visor es un `NULL` en la base.

---

## Abrirlo

Doble clic en `docs/visor_tramos.html`. Pesa 7,0 MB y tarda unos 0,4 s en quedar
usable. Se puede mandar por correo o copiar a un pendrive: no tiene dependencias.

Requiere un navegador con `DecompressionStream` (Chrome/Edge 80+, Firefox 113+,
Safari 16.4+). En uno más antiguo muestra un mensaje explícito, no una página en
blanco.

## Regenerarlo

Dos pasos, en orden:

```
Rscript src/04_ensamblaje/visor_payload.R     # parquet + gpkg -> data/interim/visor_payload.json(.gz)
python  src/04_ensamblaje/visor_html.py       # payload + módulos -> docs/visor_tramos.html
Rscript tests/run.R visor                     # validación con veto (Regla 5)
```

Hay que rehacerlo cada vez que cambie `tramos.parquet`, `procedencia.parquet` o
cualquier archivo de `src/04_ensamblaje/visor/`. La aserción *«el HTML no es más
antiguo que los módulos que lo componen»* lo detecta: sin ella, el visor se
quedó una vez publicado con módulos vacíos mientras las pruebas daban verde.

Comprobación rápida en un navegador headless, sin correr toda la validación:

```
python src/04_ensamblaje/visor_check.py --shot salida.png --js "V.n"
```

Falla si hay un solo error de consola, si la tabla no monta filas o si el lienzo
del mapa no pinta.

## Qué contiene

- **Tabla** virtualizada, 63 columnas, orden, búsqueda sin tildes, facetas,
  rangos numéricos y conmutadores de tres estados. Cada filtro ofrece *incluir
  sin dato (NULL)*, activo por omisión.
- **Criterio geomorfológico de inclusión**, arriba del panel de filtros: *todos*,
  *tramos de montaña* (`clase_kapos` 1–5 o `cruza_portezuelo` = Sí) o *resto de
  la red*. Es una condición O entre dos columnas, que las facetas por separado
  no pueden expresar. Con él activo, la tabla muestra 1.458 tramos.
- **Contador con totales de la selección**: tramos, km (suma de
  `longitud_calc_m`) y caminos con rol identificable (se excluyen `-` y los
  que empiezan con `S/R`). Los mismos totales van en la cabecera del CSV.
- **Columnas sin ningún valor fuera del visor.** `visor_html.py` omite al
  incrustar las columnas 100% NULL en la base (hoy `en_lista_colega`, `tuicion`
  y `esqui_cota_base`). El payload de `data/interim/` y el parquet las
  conservan; si una fuente llega a poblarlas, vuelven a aparecer solas. La
  cabecera del CSV las nombra.
- **Mapa** en `<canvas>`, sin mapa base: no hay tiles porque necesitarían red, y
  a esta densidad la propia red vial dibuja el contorno del país. Color por
  variable, con los NULL en su propia clase declarada.
- **Ficha** con las 63 variables agrupadas por bloque, cada una con su fuente,
  fecha, método y agente, más las descripciones de
  `docs/descripciones_columnas.csv`.
- **Exportación a CSV** de lo filtrado, con una cabecera que declara el criterio
  usado, los totales de la selección, el sha256 del parquet de origen y cuántas
  filas son sobre el total.

## Qué NO contiene

- Ningún valor que no esté en `data/processed/`.
- Perfil de altura vértice a vértice: no está en la base. La ficha dibuja un
  esquema de tres cotas (mín, media, máx) y lo dice en el propio panel.
- Mapa base, ortofotos o topónimos de referencia: exigirían red.

## Formato del payload

`visor_payload.R` escribe `data/interim/visor_payload.json`, que
`visor_html.py` incrusta comprimido y en base64.

- **Atributos** en columnas. Las de texto con ≤ 2000 valores distintos van como
  diccionario más códigos enteros. Los números viajan con `digits = 22`, la
  precisión completa del double: el CSV que exporte el visor tiene que
  reproducir el parquet bit a bit, y la prueba lo exige con identidad exacta.
- **Geometría** simplificada a 5 m, por debajo del espaciado nativo de vértices
  (10,5 m). Baja de 10.573.271 vértices a 519.068 sin pérdida visible. Se
  cuantiza a 1e-5° (~1,1 m) y se codifica como `Int32` de arranque por parte más
  deltas `Int16`. El exportador reconstruye la geometría y la compara contra la
  original antes de escribir.
- **Procedencia** colapsada a una tabla por campo: la terna fuente/fecha/método
  es constante en 56 de los 58 campos, y los dos restantes (`subdividido`,
  `motivo_corte`) viajan por tramo.

## Reglas que cumple, y cómo se comprueba

`tests/test_visor.R`, etapa `visor` de `tests/run.R`:

| Aserción | Qué protege |
|---|---|
| Cada columna reproduce el parquet valor a valor, con identidad exacta | Regla 1 |
| Los NULL del parquet siguen siendo NULL en el payload | Regla 1 |
| Ningún diccionario viaja desempaquetado a texto suelto | Regla 1 |
| `procedencia.parquet` tiene fila si y sólo si el valor no es NULL | Regla 2 |
| La procedencia del payload coincide con `procedencia.parquet` | Regla 2 |
| El método declarado está en `derivado \| declarado \| estimado` | Regla 2 |
| La geometría no se desalinea de las filas | — |
| El primer vértice de cada tramo cae sobre `coord_inicio` | — |
| El HTML no tiene ninguna referencia a la red | autocontención |
| El HTML declara el sha256 del parquet del que salió | Regla 3 |
| El HTML incrusta los módulos reales, no los stubs | Regla 5 |
| El HTML no es más antiguo que los módulos que lo componen | Regla 5 |

La regla «un valor NULL no tiene procedencia» no es una decisión de diseño del
visor: es lo que dice el parquet, y hay una aserción que lo verifica. Si algún
día dejara de cumplirse, la prueba falla y hay que reescribir la regla, no
saltársela.

## Avisos de lectura que el visor muestra

Casos donde el valor de la base es correcto pero se presta a leerse mal. El
visor nunca cambia el valor; muestra la advertencia junto a él.

- **`km_tramo`, `km_inicio` y `km_fin` están en METROS** pese al nombre
  (`docs/esquema.md`).
- **`km_tramo = 0` significa «la fuente no lo informó»**, no cero metros
  (`docs/descripciones_columnas.csv`). Son 2.227 tramos.
- **`km_tramo` en tramos subdivididos es la longitud del tramo *sin partir*.**
  Es un campo `declarado` y no se recalcula al segmentar por comuna, así que
  describe al tramo padre, no a la fila. Son 4.456 de los 18.368 tramos, todos
  con `subdividido = Sí` y `motivo_corte = cambio_comuna`; la mediana de
  `delta_longitud_pct` en ese grupo es −61,7 %. La longitud de la fila está en
  `longitud_calc_m`. **Sumar `km_tramo` sobre varias filas del mismo rol cuenta
  el mismo camino más de una vez.**
- **Los cortes por cuantiles del mapa se calculan sólo sobre los tramos con
  dato.** La leyenda declara ese número, nunca el total de la base: con `tmda`
  son 1.850 y no 18.368. Las clases se rotulan con los valores realmente
  observados en cada una, para que ningún tramo quede fuera del intervalo que su
  etiqueta declara.
- **El CSV exportado es una selección**, y su cabecera lo dice. Un porcentaje
  calculado sobre él no es un porcentaje nacional.

## Limitaciones conocidas

- Bajo 900 px de ancho la ficha cubre todo el cuerpo. Se cierra con `Escape` o
  con la ×.
- El mapa no tiene mapa base. Para ubicarse hace falta la propia red vial.
- El croquis de la ficha no lleva escala.
- 30 tramos tienen `km_tramo` más de 1,5 veces mayor que `longitud_calc_m` **sin
  estar subdivididos**. No es un problema del visor; queda anotado aquí para
  quien revise la etapa de derivación.
