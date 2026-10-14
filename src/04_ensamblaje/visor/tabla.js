/* ===========================================================================
   VISOR DE TRAMOS — tabla virtualizada, filtros y exportacion.
   Este modulo es el DUENO de V.filtrados: ningun otro lo escribe.

   Regla 1 (REGLAS.md): una celda vacia es un NULL de la base. Aqui nunca se
   rellena, nunca se estima y nunca se muestra como 0, "N/D" ni "sin dato".
   En consecuencia:
     - los NULL se ordenan SIEMPRE al final, en ambos sentidos;
     - cada filtro ofrece "incluir sin dato (NULL)", activo por omision, para
       que un rango o una faceta jamas haga desaparecer filas legitimas en
       silencio.

   Corolario para los filtros de rango: el filtro que se aplica tiene que ser
   EXACTAMENTE el que el usuario escribio. Un numero mal leido produce un
   contador, una tabla, un mapa y un CSV coherentes entre si y todos falsos, sin
   ningun aviso. Por eso leerNumero() es estricto y lo que no entiende se marca
   como error visible en vez de aplicarse a medias.

   Este modulo NO lee procedencia (V.procDe): no muestra insignias de fuente ni
   de metodo, asi que no le afecta que una celda NULL no tenga procedencia.
   =========================================================================== */
(function () {
  "use strict";

  const ALTO = 24;   // altura fija de fila, en px (la virtualizacion la asume)
  const BUF  = 6;    // filas de colchon arriba y abajo del viewport

  /* --- organizacion de las 63 columnas por bloque tematico --------------- */
  const BLOQUES = [
    ["Identificación", ["id_tramo", "id_tramo_a1", "objectid_mop", "subdividido",
                        "motivo_corte", "en_lista_colega", "match_metodo"]],
    ["Red vial",       ["rol", "rol_id", "codigo_camino", "nombre_camino", "clasificacion",
                        "carpeta", "calzada", "orientacion_ruta", "enrolado",
                        "concesionado", "tuicion"]],
    ["Geometría",      ["km_inicio", "km_fin", "km_tramo", "longitud_calc_m",
                        "delta_longitud_pct", "sinuosidad", "coord_inicio", "coord_fin",
                        "utm_zona", "buffer_join_m"]],
    ["Altimetría",     ["cota_min", "cota_max", "cota_media", "cota_culminante",
                        "clase_kapos", "pendiente_media", "pendiente_max",
                        "desnivel_subida_m", "desnivel_bajada_m", "cruza_portezuelo",
                        "orientacion_ladera", "cota_max_z_mop", "delta_z_m"]],
    ["Territorio",     ["region", "provincia", "comuna"]],
    ["Geomorfología",  ["unidad_geomorf", "vertiente", "n_unidades_geomorf"]],
    ["Nieve",          ["dias_nieve_mediana", "dias_nieve_media", "dias_nieve_sd", "meses_nieve",
                        "n_anios_validos", "dias_validos_mediana", "serie_inicio", "serie_fin"]],
    ["Fronteras",      ["es_paso", "paso_nombre", "paso_pais", "paso_trafico",
                        "paso_habilitacion", "en_zona_fronteriza", "dist_limite_m"]],
    ["Esquí",          ["es_esqui", "esqui_nombre", "esqui_cota_base"]],
    ["Localidades",    ["es_localidad", "localidad_nombre", "dist_servicios_km"]],
    ["Tránsito",       ["tmda", "tmda_invierno", "tmda_anio", "tmda_composicion",
                        "punto_censal_id", "dist_punto_censal_m"]]
  ];

  const POR_DEFECTO = ["id_tramo", "rol", "nombre_camino", "region", "comuna",
                       "clase_kapos", "cota_max", "cota_min", "pendiente_media",
                       "km_tramo", "longitud_calc_m", "es_paso", "carpeta", "vertiente",
                       "dias_nieve_mediana"];

  const FACETAS = [
    { c: "region" }, { c: "clase_kapos", num: true }, { c: "carpeta" },
    { c: "clasificacion" }, { c: "calzada" }, { c: "enrolado" },
    { c: "concesionado" }, { c: "provincia", busca: true }, { c: "comuna", busca: true },
    { c: "vertiente" }, { c: "unidad_geomorf", busca: true }
  ];
  const RANGOS = ["dias_nieve_mediana", "meses_nieve", "cota_max", "cota_min", "pendiente_media", "km_tramo",
                  "longitud_calc_m", "dist_servicios_km", "tmda"];
  const BOOLS  = ["es_paso", "cruza_portezuelo", "es_esqui", "es_localidad",
                  "en_zona_fronteriza", "subdividido", "en_lista_colega"];
  const BUSCA_EN = ["id_tramo", "rol", "nombre_camino", "comuna", "provincia",
                    "region", "paso_nombre"];

  const ANCHO = {
    id_tramo: 150, id_tramo_a1: 120, nombre_camino: 210, rol: 90, rol_id: 95,
    codigo_camino: 110, clasificacion: 210, carpeta: 130, region: 200,
    provincia: 140, comuna: 140, paso_nombre: 170, paso_trafico: 200,
    paso_pais: 90, esqui_nombre: 180, localidad_nombre: 160, tmda_composicion: 250,
    coord_inicio: 150, coord_fin: 150, punto_censal_id: 120, motivo_corte: 120,
    match_metodo: 110, orientacion_ruta: 120, clase_kapos: 78, tuicion: 110,
    unidad_geomorf: 220, vertiente: 96
  };
  const ANCHO_T = { num: 88, bool: 62, dict: 130, str: 140 };

  const LS_COLS = "visor-tabla-columnas";

  /* --- utilidades -------------------------------------------------------- */
  const nfNum = new Intl.NumberFormat("es-CL", { maximumFractionDigits: 3 });
  const nfEnt = new Intl.NumberFormat("es-CL");
  const colator = new Intl.Collator("es", { numeric: true, sensitivity: "base" });

  function norm(s) {
    return (s == null ? "" : String(s)).normalize("NFD")
      .replace(/[\u0300-\u036f]/g, "").toLowerCase();
  }
  // jsonlite desempaqueta un diccionario de un solo valor a texto suelto:
  // se normaliza aqui para no leerlo caracter a caracter.
  function dictDe(col) {
    const d = V.dicts[col];
    return Array.isArray(d) ? d : (d == null ? [] : [d]);
  }
  function esNulo(col, i) {
    const c = V.colByName[col], a = V.raw[col];
    if (!c) return true;
    if (c.t === "dict" || c.t === "bool") return a[i] < 0;
    if (c.t === "num") return Number.isNaN(a[i]);
    return a[i] === null || a[i] === undefined;
  }
  function texto(col, i) {
    const c = V.colByName[col], a = V.raw[col];
    if (!c || esNulo(col, i)) return "";
    if (c.t === "dict") { const v = dictDe(col)[a[i]]; return v == null ? "" : v; }
    if (c.t === "bool") return a[i] === 1 ? "Sí" : "No";
    if (c.t === "num")  return nfNum.format(a[i]);
    return String(a[i]);
  }
  function el(tag, cls, txt) {
    const e = document.createElement(tag);
    if (cls) e.className = cls;
    if (txt != null) e.textContent = txt;
    return e;
  }
  function leerLS(k) { try { return localStorage.getItem(k); } catch (e) { return null; } }
  function escribirLS(k, v) { try { localStorage.setItem(k, v); } catch (e) {} }

  /* --- numeros: escritura plana y lectura estricta -----------------------
     numPlano(x): representacion decimal SIN exponente del double, con los
     mismos digitos que String(x) — que ya es la cadena mas corta que vuelve a
     leerse como el mismo double. Hace falta porque String() emite notacion
     cientifica bajo 1e-6 (delta_longitud_pct llega a 6,37e-7) y un CSV con
     "6,366642050384794e-7" mezcla coma decimal y exponente: hay lectores que
     no lo aceptan. El CSV tiene que reproducir el parquet, no una version
     degradada de el.                                                       */
  function sinExponente(s) {
    const m = /^(-?)(\d+)(?:\.(\d+))?[eE]([+-]?\d+)$/.exec(s);
    if (!m) return s;                       // ya venia sin exponente
    const sig = m[1], dig = m[2] + (m[3] || "");
    const punto = m[2].length + parseInt(m[4], 10);
    let cuerpo;
    if (punto <= 0)             cuerpo = "0." + "0".repeat(-punto) + dig;
    else if (punto >= dig.length) cuerpo = dig + "0".repeat(punto - dig.length);
    else                        cuerpo = dig.slice(0, punto) + "." + dig.slice(punto);
    return sig + cuerpo;
  }
  function numPlano(x) { return sinExponente(String(x)); }

  function cifrasSig(s) {
    const d = s.replace(/^[+-]/, "").replace(".", "")
               .replace(/^0+/, "").replace(/0+$/, "");
    return d.length;
  }

  /* numCsv(x): el texto del double que va al CSV.
     String(x) da la cadena mas corta que JS vuelve a leer como el mismo double,
     pero "mas corta" no basta para OTROS lectores: dist_punto_censal_m tiene un
     valor cuya forma corta ("9345.55181780158", 15 cifras) cae casi exactamente
     en el punto medio entre dos doubles, y el strtod de R en Windows lo redondea
     al vecino — un ULP de diferencia con el parquet, en un archivo que dice
     reproducirlo. Por eso: forma corta solo cuando es un numero "redondo"
     (<=10 cifras significativas, imposible que roce un punto medio), y 17 cifras
     significativas en cuanto haya mas. 17 cifras determinan el double sin
     ambiguedad para cualquier lector correcto.                               */
  // La forma exacta vive en nucleo.js (V.exacto): cuando cada modulo tenia la
  // suya, la ficha, el title y el CSV imprimian tres cadenas distintas para el
  // mismo valor. Aqui solo se delega.
  function numCsv(x) { return V.exacto(x); }

  /* leerNumero(txt): lee lo que el usuario escribio en una casilla de rango.
     Acepta, sin ambiguedad:
       formato chileno completo   5.201,795   3.000   1.234.567   -10,6
       coma decimal sin miles     5201,795    2,5
       punto decimal simple       5201.795    3000    0.5
     La regla que desambigua "3.000": el punto solo es separador de miles
     cuando TODOS los grupos que abre tienen exactamente tres digitos
     (\d{1,3}(\.\d{3})+); si no, es punto decimal. Asi "3.000" -> 3000 y
     "5201.795" -> 5201,795, que es lo que cada uno significa en su formato.
     parseFloat no vale: acepta prefijos ("3000m" -> 3000, "3 000" -> 3) y
     aplicaria en silencio un filtro que nadie pidio.
     Devuelve {vacio:true} | {ok:true, v:number} | {error:"…"}              */
  const RE_MILES = /^[+-]?\d{1,3}(?:\.\d{3})+(?:,\d+)?$/;
  const RE_COMA  = /^[+-]?\d+(?:,\d+)?$/;
  const RE_PUNTO = /^[+-]?\d+(?:\.\d+)?$/;
  const FORMATOS = "3000 · 3.000 · 3000,5 · 3.000,5 · 3000.5";

  function leerNumero(txt) {
    const s = String(txt == null ? "" : txt).trim();
    if (!s) return { vacio: true };
    let n;
    if (RE_MILES.test(s))      n = Number(s.replace(/\./g, "").replace(",", "."));
    else if (RE_COMA.test(s))  n = Number(s.replace(",", "."));
    else if (RE_PUNTO.test(s)) n = Number(s);
    else return { error: "no se entiende como número" };
    if (!Number.isFinite(n)) return { error: "no es un número finito" };
    return { ok: true, v: n };
  }

  // Texto es-CL de un numero que leerNumero() vuelve a leer como el MISMO
  // double. Si el redondeo de Intl no lo permite, se cae al decimal plano.
  const nfExacto = new Intl.NumberFormat("es-CL", { maximumFractionDigits: 20 });
  function textoNum(v) {
    let s;
    try { s = nfExacto.format(v); } catch (e) { s = null; }
    if (s) { const r = leerNumero(s); if (r.ok && r.v === v) return s; }
    return numPlano(v);
  }

  /* --- estado ------------------------------------------------------------ */
  let raiz, elScroll, elCab, elCuerpo, elCuenta, popCols, popFil, elBusca, btnFil, elVacio;
  let visibles = [], orden = { col: null, dir: 1 };
  const pool = [];
  let posDe = null;          // indice de tramo -> posicion en V.filtrados (-1 si fuera)
  let bufRes = null;         // buffer reutilizable del resultado del filtro
  let rangoDictCache = {}, normCache = {}, distNumCache = {}, extremos = {};
  let ultimoA = -1, ultimoB = -1, ultimoCA = -1, ultimoCB = -1, ultimoSL = -1;
  let metaVis = [], offVis = [];   // metadatos y offsets en x de las columnas visibles

  const estado = {
    busca: "",
    facetas: {},   // col -> {sel:Set, nulos:bool, q:string}
    // rangos: min/max son el filtro REALMENTE aplicado; malMin/malMax guardan
    // el texto que no se pudo leer (para avisar en vez de ignorarlo) e
    // invertido marca min > max, que no es un filtro estrecho sino imposible.
    rangos: {},    // col -> {min, max, nulos, malMin, malMax, invertido}
    bools: {},     // col -> {est:''|'si'|'no', nulos:bool}
    // criterio geomorfologico de inclusion (REGLAS.md): clase_kapos 1-5 O
    // cruza_portezuelo. Es una disyuncion entre dos columnas, que las facetas
    // (siempre en conjuncion) no pueden expresar. No escribe ningun valor.
    montana: { est: "", nulos: true }
  };

  function estadoInicial() {
    estado.busca = "";
    FACETAS.forEach(f => { estado.facetas[f.c] = { sel: new Set(), nulos: true, q: "" }; });
    RANGOS.forEach(c => { estado.rangos[c] = { min: null, max: null, nulos: true,
                                               malMin: null, malMax: null, invertido: false }; });
    BOOLS.forEach(c => { estado.bools[c] = { est: "", nulos: true }; });
    estado.montana = { est: "", nulos: true };
  }

  /* --- criterio geomorfologico: 1 montana, 0 no, -1 sin dato -------------- */
  // Un tramo es de montana si su clase Kapos esta entre 1 y 5 o si cruza un
  // portezuelo. Si no cumple ninguna de las dos y le falta alguno de los dos
  // datos, no se puede decidir: queda como NULL, no como "no".
  let montanaCache = null;
  function montanaDe() {
    if (montanaCache) return montanaCache;
    const out = new Int8Array(V.n);
    const k = V.colByName.clase_kapos ? V.raw.clase_kapos : null;
    const p = V.colByName.cruza_portezuelo ? V.raw.cruza_portezuelo : null;
    for (let i = 0; i < V.n; i++) {
      const kv = k ? k[i] : NaN, pv = p ? p[i] : -1;
      if ((!Number.isNaN(kv) && kv >= 1 && kv <= 5) || pv === 1) out[i] = 1;
      else if (Number.isNaN(kv) || pv < 0) out[i] = -1;
      else out[i] = 0;
    }
    return (montanaCache = out);
  }
  function cuentaMontana() {
    const m = montanaDe(); let si = 0, no = 0, nul = 0;
    for (let i = 0; i < V.n; i++) { if (m[i] === 1) si++; else if (m[i] === 0) no++; else nul++; }
    return { si: si, no: no, nul: nul };
  }

  /* --- totales de la seleccion ------------------------------------------- */
  // Longitud medida sobre la geometria (longitud_calc_m, nunca km_tramo, que en
  // los tramos subdivididos repite la del tramo padre) y roles identificables
  // (sin "S/R", "-" ni "S/R-..."). Son sumas de la seleccion, no valores nuevos.
  // fuera: "-", "S/R", "S/R-A-179", "S/Rol 1970"
  function rolIdentificable(t) { return !!t && t !== "-" && t.indexOf("S/R") !== 0; }
  function totalesSeleccion(f) {
    let m = 0;
    const lon = V.colByName.longitud_calc_m ? V.raw.longitud_calc_m : null;
    const roles = new Set();
    for (let k = 0; k < f.length; k++) {
      const i = f[k];
      if (lon && !Number.isNaN(lon[i])) m += lon[i];
      if (V.colByName.rol) { const t = texto("rol", i); if (rolIdentificable(t)) roles.add(t); }
    }
    return { km: m / 1000, roles: roles.size };
  }

  /* --- caches derivadas de los datos ------------------------------------- */
  function rangoDict(col) {                    // code -> rango alfabetico
    if (rangoDictCache[col]) return rangoDictCache[col];
    const d = dictDe(col), idx = d.map((_, k) => k);
    idx.sort((a, b) => colator.compare(d[a], d[b]));
    const r = new Int32Array(d.length);
    for (let k = 0; k < idx.length; k++) r[idx[k]] = k;
    return (rangoDictCache[col] = r);
  }
  function normDe(col) {                       // texto normalizado para buscar
    if (normCache[col]) return normCache[col];
    const c = V.colByName[col], a = V.raw[col];
    let out;
    if (c.t === "dict") out = dictDe(col).map(norm);
    else { out = new Array(V.n); for (let i = 0; i < V.n; i++) out[i] = norm(a[i]); }
    return (normCache[col] = out);
  }
  function distintosNum(col) {                 // valores distintos de una numerica discreta
    if (distNumCache[col]) return distNumCache[col];
    const a = V.raw[col], s = new Set();
    for (let i = 0; i < V.n; i++) if (!Number.isNaN(a[i])) s.add(a[i]);
    const v = Array.from(s).sort((x, y) => x - y);
    return (distNumCache[col] = v);
  }
  function extremosDe(col) {
    if (extremos[col]) return extremos[col];
    const a = V.raw[col]; let mn = Infinity, mx = -Infinity;
    for (let i = 0; i < V.n; i++) { const x = a[i]; if (Number.isNaN(x)) continue;
      if (x < mn) mn = x; if (x > mx) mx = x; }
    return (extremos[col] = (mn === Infinity ? null : { mn: mn, mx: mx }));
  }

  /* =======================================================================
     FILTRADO
     Recorre los arrays tipados de V.raw. Las facetas se cuentan de forma
     disyuntiva (cada faceta se cuenta ignorando su propia seleccion) en la
     misma pasada, con el truco de contar los fallos por fila.
     ======================================================================= */
  function predicadoBusqueda() {
    const q = norm(estado.busca).trim();
    if (!q) return null;
    // cada palabra debe aparecer en ALGUNA de las columnas buscables; asi
    // "putre copaquilla" encuentra la comuna en una columna y el nombre en otra.
    const partes = q.split(/\s+/);
    const cols = BUSCA_EN.filter(c => V.colByName[c]);
    const term = partes.map(p => {
      const dictSets = [], strCols = [];
      for (const c of cols) {
        if (V.colByName[c].t === "dict") {
          const nd = normDe(c), s = new Set();
          for (let k = 0; k < nd.length; k++) if (nd[k].indexOf(p) >= 0) s.add(k);
          if (s.size) dictSets.push({ a: V.raw[c], s: s });
        } else {
          strCols.push({ a: normDe(c), p: p });
        }
      }
      return { d: dictSets, s: strCols };
    });
    return function (i) {
      for (let t = 0; t < term.length; t++) {
        const T = term[t];
        let hay = false;
        for (let j = 0; j < T.d.length && !hay; j++) {
          const k = T.d[j].a[i]; if (k >= 0 && T.d[j].s.has(k)) hay = true;
        }
        for (let j = 0; j < T.s.length && !hay; j++) {
          const v = T.s[j].a[i]; if (v && v.indexOf(T.s[j].p) >= 0) hay = true;
        }
        if (!hay) return false;
      }
      return true;
    };
  }

  function recalcular(emitir) {
    const n = V.n;
    if (!bufRes) bufRes = new Int32Array(n);
    if (!posDe)  posDe  = new Int32Array(n);

    const fBusca = predicadoBusqueda();

    // rangos y booleanas: se resuelven en una lista plana para el bucle caliente
    const rgs = [];
    for (const c of RANGOS) {
      const r = estado.rangos[c];
      if (!V.colByName[c]) continue;
      if (r.min === null && r.max === null && r.nulos) continue;
      rgs.push({ a: V.raw[c], mn: r.min, mx: r.max, nul: r.nulos });
    }
    const bls = [];
    for (const c of BOOLS) {
      const b = estado.bools[c];
      if (!V.colByName[c]) continue;
      if (b.est === "" && b.nulos) continue;
      bls.push({ a: V.raw[c], est: b.est, nul: b.nulos });
    }

    // facetas: siempre se recorren todas, porque hay que contar aunque no filtren
    const fac = [];
    for (const f of FACETAS) {
      if (!V.colByName[f.c]) continue;
      const st = estado.facetas[f.c];
      const o = { col: f.c, num: !!f.num, a: V.raw[f.c], sel: st.sel, nul: st.nulos };
      if (f.num) {
        const vals = distintosNum(f.c);
        o.vals = vals;
        o.idxDe = new Map(); vals.forEach((v, k) => o.idxDe.set(v, k));
        o.cnt = new Int32Array(vals.length + 1);
      } else {
        o.cnt = new Int32Array(dictDe(f.c).length + 1);
      }
      fac.push(o);
    }

    const mo = estado.montana, mArr = (mo.est !== "" || !mo.nulos) ? montanaDe() : null;
    let m = 0;
    for (let i = 0; i < n; i++) {
      if (fBusca && !fBusca(i)) continue;
      if (mArr) {
        const v = mArr[i];
        if (v < 0) { if (!mo.nulos) continue; }
        else if (mo.est === "si" && v !== 1) continue;
        else if (mo.est === "no" && v !== 0) continue;
      }

      let ok = true;
      for (let j = 0; j < rgs.length && ok; j++) {
        const r = rgs[j], x = r.a[i];
        if (Number.isNaN(x)) { if (!r.nul) ok = false; }
        else if ((r.mn !== null && x < r.mn) || (r.mx !== null && x > r.mx)) ok = false;
      }
      if (!ok) continue;
      for (let j = 0; j < bls.length && ok; j++) {
        const b = bls[j], k = b.a[i];
        if (k < 0) { if (!b.nul) ok = false; }
        else if (b.est === "si") { if (k !== 1) ok = false; }
        else if (b.est === "no") { if (k !== 0) ok = false; }
      }
      if (!ok) continue;

      // facetas: cuantas fallan y cual
      let fallos = 0, cual = -1;
      for (let j = 0; j < fac.length; j++) {
        const f = fac[j], a = f.a;
        let pasa;
        if (f.num) {
          const x = a[i];
          pasa = Number.isNaN(x) ? f.nul : (f.sel.size === 0 || f.sel.has(x));
        } else {
          const k = a[i];
          pasa = k < 0 ? f.nul : (f.sel.size === 0 || f.sel.has(k));
        }
        if (!pasa) { fallos++; cual = j; if (fallos > 1) break; }
      }
      if (fallos === 0) {
        bufRes[m++] = i;
        for (let j = 0; j < fac.length; j++) fac[j].cnt[clave(fac[j], i)]++;
      } else if (fallos === 1) {
        fac[cual].cnt[clave(fac[cual], i)]++;
      }
    }

    V.filtrados = bufRes.slice(0, m);
    if (orden.col) ordenar();
    posDe.fill(-1);
    for (let k = 0; k < V.filtrados.length; k++) posDe[V.filtrados[k]] = k;

    pintarCuentas(fac);
    const tot = totalesSeleccion(V.filtrados);
    elCuenta.textContent = nfEnt.format(m) + " de " + nfEnt.format(n) + " tramos · " +
      nfEnt.format(Math.round(tot.km)) + " km · " + nfEnt.format(tot.roles) + " roles";
    elCuenta.title = "km: suma de longitud_calc_m de los tramos seleccionados (no km_tramo). " +
      "Roles: valores distintos de rol, sin contar «S/R», «-» ni «S/R-…».";
    elCuenta.classList.toggle("t-filtrado", m !== n);
    marcarActivos();
    ultimoA = ultimoB = -1;
    render();
    if (emitir !== false) V.emit("filtro");
  }

  function clave(f, i) {
    if (f.num) { const x = f.a[i]; if (Number.isNaN(x)) return 0; return f.idxDe.get(x) + 1; }
    const k = f.a[i]; return k < 0 ? 0 : k + 1;
  }

  /* --- orden ------------------------------------------------------------- */
  function comparador(col, dir) {
    const c = V.colByName[col], a = V.raw[col];
    if (c.t === "num") return function (i, j) {
      const x = a[i], y = a[j], nx = Number.isNaN(x), ny = Number.isNaN(y);
      if (nx || ny) return (nx && ny) ? i - j : (nx ? 1 : -1);   // NULL al final
      return x === y ? i - j : (x < y ? -dir : dir);
    };
    if (c.t === "bool" || c.t === "dict") {
      const rk = c.t === "dict" ? rangoDict(col) : null;
      return function (i, j) {
        const x = a[i], y = a[j];
        if (x < 0 || y < 0) return (x < 0 && y < 0) ? i - j : (x < 0 ? 1 : -1);
        const rx = rk ? rk[x] : x, ry = rk ? rk[y] : y;
        return rx === ry ? i - j : (rx < ry ? -dir : dir);
      };
    }
    return function (i, j) {                     // texto: solo null va al final
      const x = a[i], y = a[j];
      if (x == null || y == null) return (x == null && y == null) ? i - j : (x == null ? 1 : -1);
      const r = colator.compare(x, y);
      return r === 0 ? i - j : (r < 0 ? -dir : dir);
    };
  }
  function ordenar() {
    if (!orden.col || !V.colByName[orden.col]) return;
    V.filtrados.sort(comparador(orden.col, orden.dir));
  }

  /* =======================================================================
     RENDER DE LA TABLA (virtualizada)
     ======================================================================= */
  function anchoDe(col) {
    return ANCHO[col] || ANCHO_T[(V.colByName[col] || {}).t] || 120;
  }
  function anchoTotal() {
    let w = 0; for (const c of visibles) w += anchoDe(c); return w;
  }
  function esNum(col) { return (V.colByName[col] || {}).t === "num"; }

  function pintarCabecera() {
    elCab.textContent = "";
    const w = anchoTotal();
    elCab.style.width = w + "px";
    elCuerpo.style.width = w + "px";
    visibles.forEach(col => {
      const d = V.desc[col] || {};
      const th = el("div", "t-th" + (esNum(col) ? " t-der" : ""));
      th.style.width = anchoDe(col) + "px";
      th.title = col + (d.que_es ? " — " + d.que_es : "");
      th.appendChild(el("span", "t-th-n", col));
      const fl = el("span", "t-th-o", orden.col === col ? (orden.dir > 0 ? "▲" : "▼") : "");
      th.appendChild(fl);
      if (orden.col === col) th.classList.add("t-ord");
      th.addEventListener("click", () => {
        if (orden.col === col) orden.dir = -orden.dir;
        else { orden.col = col; orden.dir = 1; }
        ordenar();
        posDe.fill(-1);
        for (let k = 0; k < V.filtrados.length; k++) posDe[V.filtrados[k]] = k;
        pintarCabecera();
        ultimoA = ultimoB = -1;
        render();
      });
      elCab.appendChild(th);
    });
    metaVis = visibles.map(col => {
      const c = V.colByName[col], num = c.t === "num";
      return { col: col, t: c.t, a: V.raw[col], d: c.t === "dict" ? dictDe(col) : null,
               num: num,
               cls: "t-cel" + (num ? " mono t-der" : ""),
               clsN: "t-cel" + (num ? " mono t-der" : "") + " vacio" };
    });
    offVis = new Array(visibles.length + 1);
    for (let j = 0, acc = 0; j <= visibles.length; j++) {
      offVis[j] = acc; if (j < visibles.length) acc += anchoDe(visibles[j]);
    }
    ultimoCA = ultimoCB = ultimoSL = -1;
    pool.length = 0;
    elCuerpo.textContent = "";
  }

  function nuevaFila() {
    const f = el("div", "t-fila");
    visibles.forEach(col => {
      const c = el("span", "t-cel");
      c.style.width = anchoDe(col) + "px";
      f.appendChild(c);
    });
    f._idx = -2;
    elCuerpo.appendChild(f);
    return f;
  }

  function render() {
    const tot = V.filtrados.length;
    if (elVacio) {
      elVacio.hidden = tot !== 0;
      // el diagnostico se recalcula solo cuando hace falta: render() corre en
      // cada scroll
      if (tot === 0) {
        const m = describirVacio();
        if (m !== elVacio._m) { elVacio._m = m; elVacio.textContent = m; }
      }
    }
    elCuerpo.style.height = (tot * ALTO) + "px";
    const st = elScroll.scrollTop, h = elScroll.clientHeight || 400;
    let a = Math.max(0, Math.floor(st / ALTO) - BUF);
    let b = Math.min(tot, Math.ceil((st + h) / ALTO) + BUF);
    if (b < a) b = a;
    const nec = b - a;
    while (pool.length < nec) pool.push(nuevaFila());
    for (let k = nec; k < pool.length; k++) pool[k].style.display = "none";

    // ventana horizontal: con 63 columnas no tiene sentido escribir las que
    // quedan fuera del viewport
    const nc = metaVis.length, sl = elScroll.scrollLeft, cw = elScroll.clientWidth || 800;
    let ca = 0, cb = nc;
    while (ca < nc && offVis[ca + 1] < sl - 240) ca++;
    cb = ca; while (cb < nc && offVis[cb] < sl + cw + 240) cb++;
    if (ca !== ultimoCA || cb !== ultimoCB) {
      for (let k = 0; k < pool.length; k++) pool[k]._idx = -2;
      ultimoCA = ca; ultimoCB = cb;
    }
    ultimoSL = sl;

    for (let k = 0; k < nec; k++) {
      const f = pool[k], p = a + k, i = V.filtrados[p];
      f.style.display = "";
      f.style.top = (p * ALTO) + "px";
      if (f._idx !== i) {
        f._idx = i;
        const cs = f.childNodes;
        for (let j = 0; j < nc; j++) {
          const cel = cs[j];
          if (j < ca || j >= cb) {
            if (cel.className !== "t-cel t-off") {
              cel.className = "t-cel t-off"; cel.textContent = ""; cel.title = "";
            }
            continue;
          }
          const m = metaVis[j], a2 = m.a;
          let nulo, txt = "", tit = "";
          if (m.t === "num") {
            const x = a2[i];
            nulo = Number.isNaN(x);
            if (!nulo) {
              txt = nfNum.format(x);
              // el valor exacto de la base queda a un hover de distancia: lo que
              // se ve redondeado y lo que se exporta no pueden parecer distintos
              const ex = V.exactoCL(x);   // misma cadena que la ficha y el CSV
              tit = ex.replace(",", ".").length > txt.replace(/\./g, "").length ? ex : "";
            }
          } else if (m.t === "dict") {
            const k2 = a2[i]; nulo = k2 < 0;
            if (!nulo) { const v = m.d[k2]; txt = v == null ? "" : v; }
          } else if (m.t === "bool") {
            const k2 = a2[i]; nulo = k2 < 0;
            if (!nulo) txt = k2 === 1 ? "Sí" : "No";
          } else {
            const v = a2[i]; nulo = (v === null || v === undefined);
            if (!nulo) txt = v;
          }
          // La base trae la raya COMO VALOR declarado por Vialidad: rol, rol_id
          // y codigo_camino valen "-" en muchos tramos. El NULL se marca con un
          // simbolo dibujado (no un caracter) y ademas se nombra en el hover,
          // para que un "-" que es dato y una celda sin dato no se parezcan.
          if (nulo) tit = "sin dato (NULL) en " + m.col;
          else if (!tit && txt === "-") tit = "«-» es el valor declarado en " + m.col;
          cel.textContent = txt;
          if (cel.title !== tit) cel.title = tit;
          cel.className = nulo ? m.clsN : m.cls;
        }
      }
      f.classList.toggle("t-sel", i === V.sel);
      f.classList.toggle("t-hov", i === V.hover);
    }
    ultimoA = a; ultimoB = b;
  }

  function repintarMarcas() {
    for (const f of pool) {
      if (f.style.display === "none") continue;
      f.classList.toggle("t-sel", f._idx === V.sel);
      f.classList.toggle("t-hov", f._idx === V.hover);
    }
  }

  /* La cabecera .t-cab es sticky DENTRO de .t-scroll: ocupa siempre los
     primeros px del viewport y las filas empiezan debajo de ella. Ignorar ese
     alto hacia abajo dejaba la fila seleccionada cortada (2 px una de cada
     cuatro pulsaciones de ArrowDown, 26 px la siguiente) porque el borde
     inferior real cae mas abajo de lo que suponia el calculo. */
  function verFila(i) {
    const p = posDe ? posDe[i] : -1;
    if (p < 0) return;
    const cab = elCab ? elCab.offsetHeight : 0;
    const h = elScroll.clientHeight, st = elScroll.scrollTop;
    const arriba = cab + p * ALTO, abajo = arriba + ALTO;   // coords de contenido
    const margen = ALTO * 3;
    // visible = arriba >= st + cab (por debajo de la cabecera) y abajo <= st + h
    if (arriba < st + cab) elScroll.scrollTop = Math.max(0, arriba - cab - margen);
    else if (abajo > st + h) elScroll.scrollTop = abajo - h + margen;
  }

  function seleccionar(i) {
    if (V.sel === i) return;
    V.sel = i;
    V.emit("seleccion", i);
  }

  /* =======================================================================
     PANELES: columnas y filtros
     ======================================================================= */
  function guardarCols() { escribirLS(LS_COLS, JSON.stringify(visibles)); }

  // ordenar por una columna que ya no se ve deja la tabla en un orden sin
  // explicacion visible: se vuelve al orden natural.
  function sanearOrden() {
    if (orden.col && visibles.indexOf(orden.col) < 0) { orden.col = null; return true; }
    return false;
  }

  function pintarPanelColumnas() {
    popCols.textContent = "";
    const cab = el("div", "t-pop-cab");
    cab.appendChild(el("strong", null, "Columnas visibles"));
    const acc = el("span", "t-pop-acc");
    const bTodas = el("button", "btn t-mini", "Todas");
    const bDef = el("button", "btn t-mini", "Por defecto");
    const bNada = el("button", "btn t-mini", "Ninguna");
    acc.append(bTodas, bDef, bNada);
    cab.appendChild(acc);
    popCols.appendChild(cab);

    const rejilla = el("div", "t-pop-rej");
    const usadas = new Set();
    BLOQUES.forEach(b => b[1].forEach(c => usadas.add(c)));
    const sueltas = V.cols.map(c => c.n).filter(c => !usadas.has(c));
    const bloques = sueltas.length ? BLOQUES.concat([["Otras", sueltas]]) : BLOQUES;

    bloques.forEach(([nombre, cols]) => {
      const g = el("div", "t-grupo");
      g.appendChild(el("h4", null, nombre));
      cols.forEach(col => {
        if (!V.colByName[col]) return;
        const d = V.desc[col] || {};
        const lab = el("label", "t-chk");
        const inp = el("input"); inp.type = "checkbox";
        inp.checked = visibles.indexOf(col) >= 0;
        inp.addEventListener("change", () => {
          if (inp.checked) {
            if (visibles.indexOf(col) < 0) {
              // se respeta el orden canonico de los bloques
              const ord = [];
              bloques.forEach(([, cs]) => cs.forEach(c => ord.push(c)));
              const nuevas = ord.filter(c => c === col || visibles.indexOf(c) >= 0);
              visibles = nuevas;
            }
          } else {
            visibles = visibles.filter(c => c !== col);
          }
          if (!visibles.length) { visibles = [col]; inp.checked = true; }
          guardarCols();
          const reord = sanearOrden();
          pintarCabecera(); ultimoA = ultimoB = -1;
          if (reord) recalcular(); else render();
        });
        lab.appendChild(inp);
        lab.appendChild(el("span", "t-chk-n", col));
        const nulos = (V.colByName[col] || {}).nulos || 0;
        if (nulos === V.n) lab.appendChild(el("span", "t-chk-c vacio", "sin dato"));
        else if (nulos > 0) lab.appendChild(el("span", "t-chk-c", nfEnt.format(nulos) + " NULL"));
        lab.title = col + (d.que_es ? " — " + d.que_es : "");
        g.appendChild(lab);
      });
      rejilla.appendChild(g);
    });
    popCols.appendChild(rejilla);

    function fijar(lista) {
      visibles = lista.filter(c => V.colByName[c]);
      if (!visibles.length) visibles = ["id_tramo"];
      guardarCols();
      const reord = sanearOrden();
      pintarPanelColumnas();
      pintarCabecera(); ultimoA = ultimoB = -1;
      if (reord) recalcular(); else render();
    }
    bTodas.addEventListener("click", () => {
      const ord = []; bloques.forEach(([, cs]) => cs.forEach(c => ord.push(c))); fijar(ord);
    });
    bDef.addEventListener("click", () => fijar(POR_DEFECTO.slice()));
    bNada.addEventListener("click", () => fijar(["id_tramo"]));
  }

  const refFac = {}, refRan = {}, refBool = {};

  function pintarPanelFiltros() {
    popFil.textContent = "";

    /* --- criterio geomorfologico de inclusion --- */
    const cm = cuentaMontana(), stM = estado.montana;
    const crit = el("div", "t-crit");
    const cabC = el("div", "t-crit-cab");
    cabC.appendChild(el("span", "t-faceta-n", "Criterio geomorfológico de inclusión"));
    cabC.appendChild(el("span", "t-crit-def", "clase_kapos entre 1 y 5, o cruza_portezuelo = Sí"));
    crit.appendChild(cabC);
    const triM = el("div", "t-tri");
    const botsM = {};
    [["", "todos", V.n], ["si", "tramos de montaña", cm.si], ["no", "resto de la red", cm.no]].forEach(([v, t, c]) => {
      const bt = el("button", "t-tri-b" + (stM.est === v ? " act" : ""), t + " · " + nfEnt.format(c));
      bt.addEventListener("click", () => {
        stM.est = v;
        Object.keys(botsM).forEach(k => botsM[k].classList.toggle("act", k === v));
        recalcular();
      });
      botsM[v] = bt; triM.appendChild(bt);
    });
    crit.appendChild(triM);
    if (cm.nul) {
      const ln = el("label", "t-chk t-nulos");
      const inN = el("input"); inN.type = "checkbox"; inN.checked = stM.nulos;
      inN.addEventListener("change", () => { stM.nulos = inN.checked; recalcular(); });
      ln.appendChild(inN);
      ln.appendChild(el("span", "t-chk-n vacio", "incluir sin dato (NULL)"));
      ln.appendChild(el("span", "t-chk-c", nfEnt.format(cm.nul)));
      crit.appendChild(ln);
    }
    popFil.appendChild(crit);

    const rej = el("div", "t-fil-rej");

    /* --- facetas --- */
    const gF = el("div", "t-fil-col");
    gF.appendChild(el("h4", null, "Categorías"));
    FACETAS.forEach(f => {
      if (!V.colByName[f.c]) return;
      const st = estado.facetas[f.c];
      const box = el("div", "t-faceta");
      const cab = el("div", "t-faceta-cab");
      cab.appendChild(el("span", "t-faceta-n", f.c));
      const lim = el("button", "t-x", "limpiar");
      lim.addEventListener("click", () => {
        st.sel.clear(); st.nulos = true; pintarPanelFiltros(); recalcular();
      });
      cab.appendChild(lim);
      cab.title = ((V.desc[f.c] || {}).que_es) || f.c;
      box.appendChild(cab);

      if (f.busca) {
        const bq = el("input", "t-faceta-q");
        bq.type = "search"; bq.placeholder = "buscar en " + f.c + "…";
        bq.value = st.q;
        bq.addEventListener("input", () => { st.q = bq.value; filtrarValores(f.c); });
        box.appendChild(bq);
      }

      // "incluir sin dato" SIEMPRE presente y marcado por omision (Regla 1)
      const ln = el("label", "t-chk t-nulos");
      const inN = el("input"); inN.type = "checkbox"; inN.checked = st.nulos;
      inN.addEventListener("change", () => { st.nulos = inN.checked; recalcular(); });
      ln.appendChild(inN);
      ln.appendChild(el("span", "t-chk-n vacio", "incluir sin dato (NULL)"));
      const cN = el("span", "t-chk-c", "");
      ln.appendChild(cN);
      box.appendChild(ln);

      const vals = el("div", "t-vals");
      const filas = new Map();
      const lista = f.num
        ? distintosNum(f.c).map((v, k) => ({ k: k, txt: nfNum.format(v), val: v }))
        : dictDe(f.c).map((s, k) => ({ k: k, txt: s, val: k }))
                     .sort((a, b) => colator.compare(a.txt, b.txt));
      lista.forEach(it => {
        const lab = el("label", "t-chk");
        const inp = el("input"); inp.type = "checkbox";
        inp.checked = st.sel.has(it.val);
        inp.addEventListener("change", () => {
          if (inp.checked) st.sel.add(it.val); else st.sel.delete(it.val);
          recalcular();
        });
        lab.appendChild(inp);
        lab.appendChild(el("span", "t-chk-n", it.txt));
        const c = el("span", "t-chk-c", "");
        lab.appendChild(c);
        lab.title = it.txt;
        lab._n = norm(it.txt);
        vals.appendChild(lab);
        filas.set(it.k, { lab: lab, cnt: c, inp: inp });
      });
      box.appendChild(vals);
      gF.appendChild(box);
      refFac[f.c] = { filas: filas, nul: cN, nulInp: inN, nulLab: ln, vals: vals };
      if (f.busca) filtrarValores(f.c);
    });
    rej.appendChild(gF);

    /* --- rangos --- */
    const gR = el("div", "t-fil-col");
    gR.appendChild(el("h4", null, "Rangos numéricos"));
    RANGOS.forEach(c => {
      if (!V.colByName[c]) return;
      const st = estado.rangos[c];
      const ex = extremosDe(c), nulos = (V.colByName[c].nulos) || 0;
      const box = el("div", "t-rango");
      const cab = el("div", "t-faceta-cab");
      cab.appendChild(el("span", "t-faceta-n", c));
      cab.title = ((V.desc[c] || {}).que_es) || c;
      box.appendChild(cab);
      const fila = el("div", "t-rango-in");
      const a = el("input", "t-num mono"), b = el("input", "t-num mono");
      a.type = "text"; b.type = "text";
      a.placeholder = "mín"; b.placeholder = "máx";
      a.setAttribute("aria-label", "mínimo de " + c);
      b.setAttribute("aria-label", "máximo de " + c);
      a.setAttribute("aria-describedby", "aviso-" + c);
      b.setAttribute("aria-describedby", "aviso-" + c);
      // si habia texto que no se pudo leer se vuelve a mostrar TAL CUAL: al
      // repintar el panel no puede desaparecer el error dejando el aviso solo
      a.value = st.malMin !== null ? st.malMin : (st.min === null ? "" : textoNum(st.min));
      b.value = st.malMax !== null ? st.malMax : (st.max === null ? "" : textoNum(st.max));
      // el aviso vive dentro del recuadro del rango, pegado a las casillas:
      // un error de lectura no puede quedarse solo en la consola
      const aviso = el("div", "t-rango-aviso");
      // el motivo del rechazo tiene que llegar tambien a un lector de
      // pantalla: aria-invalid solo dice "invalido", no que formatos valen
      aviso.id = "aviso-" + c;
      aviso.setAttribute("role", "alert");
      aviso.setAttribute("aria-live", "polite");
      aviso.hidden = true;

      // Los extremos van redondeados a 3 decimales para poder leerse; el valor
      // exacto de la base tiene mas cifras (cota_max llega a 5.201,795019852272).
      // Copiar el texto visible dejaria fuera la fila del maximo, asi que el
      // chip es un boton que escribe los extremos EXACTOS en las casillas.
      if (ex) {
        const chip = el("button", "t-faceta-ex mono",
          nfNum.format(ex.mn) + " … " + nfNum.format(ex.mx));
        chip.type = "button";
        chip.title = "Extremos exactos en la base: " + textoNum(ex.mn) + " … " +
          textoNum(ex.mx) + "\n(el texto visible va redondeado a 3 decimales)" +
          "\nPulsa para copiarlos a las casillas.";
        chip.addEventListener("click", () => {
          a.value = textoNum(ex.mn); b.value = textoNum(ex.mx); leer();
        });
        cab.appendChild(chip);
      }

      function pintarAviso() {
        a.classList.toggle("t-num-mal", !!st.malMin || st.invertido);
        b.classList.toggle("t-num-mal", !!st.malMax || st.invertido);
        if (st.malMin) a.setAttribute("aria-invalid", "true"); else a.removeAttribute("aria-invalid");
        if (st.malMax) b.setAttribute("aria-invalid", "true"); else b.removeAttribute("aria-invalid");
        let txt = "";
        const malos = [];
        if (st.malMin) malos.push("mín «" + st.malMin + "»");
        if (st.malMax) malos.push("máx «" + st.malMax + "»");
        if (malos.length)
          txt = "No se aplica " + malos.join(" ni ") + ": " +
                (malos.length > 1 ? "no se entienden" : "no se entiende") +
                " como número. Formatos aceptados: " + FORMATOS + ".";
        else if (st.invertido)
          txt = "El mínimo (" + textoNum(st.min) + ") es mayor que el máximo (" +
                textoNum(st.max) + "): ningún tramo puede cumplir las dos " +
                "condiciones a la vez. Corrige uno de los dos extremos.";
        aviso.textContent = txt;
        aviso.hidden = !txt;
      }

      function leer() {
        const ra = leerNumero(a.value), rb = leerNumero(b.value);
        st.malMin = ra.error ? String(a.value).trim() : null;
        st.malMax = rb.error ? String(b.value).trim() : null;
        st.min = ra.ok ? ra.v : null;
        st.max = rb.ok ? rb.v : null;
        st.invertido = (st.min !== null && st.max !== null && st.min > st.max);
        // la casilla se reescribe en el formato que ella misma sabe releer:
        // lo que se ve y lo que se aplica dejan de poder discrepar
        if (ra.ok) a.value = textoNum(ra.v);
        if (rb.ok) b.value = textoNum(rb.v);
        pintarAviso();
        recalcular();
      }
      a.addEventListener("change", leer); b.addEventListener("change", leer);
      fila.append(a, el("span", "t-sep", "—"), b);
      box.appendChild(fila);
      box.appendChild(aviso);
      pintarAviso();
      const ln = el("label", "t-chk t-nulos");
      const inN = el("input"); inN.type = "checkbox"; inN.checked = st.nulos;
      inN.addEventListener("change", () => { st.nulos = inN.checked; recalcular(); });
      ln.appendChild(inN);
      ln.appendChild(el("span", "t-chk-n vacio", "incluir sin dato (NULL)"));
      ln.appendChild(el("span", "t-chk-c", nfEnt.format(nulos)));
      box.appendChild(ln);
      gR.appendChild(box);
      refRan[c] = { a: a, b: b, nulInp: inN, nulLab: ln, aviso: pintarAviso };
    });
    rej.appendChild(gR);

    /* --- booleanas --- */
    const gB = el("div", "t-fil-col");
    gB.appendChild(el("h4", null, "Marcas (sí / no / indiferente)"));
    BOOLS.forEach(c => {
      if (!V.colByName[c]) return;
      const st = estado.bools[c];
      const nulos = (V.colByName[c].nulos) || 0;
      const box = el("div", "t-bool");
      const cab = el("div", "t-faceta-cab");
      cab.appendChild(el("span", "t-faceta-n", c));
      cab.title = ((V.desc[c] || {}).que_es) || c;
      box.appendChild(cab);
      const tri = el("div", "t-tri");
      const bots = {};
      [["", "indif."], ["si", "sí"], ["no", "no"]].forEach(([v, t]) => {
        const bt = el("button", "t-tri-b" + (st.est === v ? " act" : ""), t);
        bt.addEventListener("click", () => {
          st.est = v;
          Object.keys(bots).forEach(k => bots[k].classList.toggle("act", k === v));
          recalcular();
        });
        bots[v] = bt; tri.appendChild(bt);
      });
      box.appendChild(tri);
      const ln = el("label", "t-chk t-nulos");
      const inN = el("input"); inN.type = "checkbox"; inN.checked = st.nulos;
      inN.addEventListener("change", () => { st.nulos = inN.checked; recalcular(); });
      ln.appendChild(inN);
      ln.appendChild(el("span", "t-chk-n vacio", "incluir sin dato (NULL)"));
      ln.appendChild(el("span", "t-chk-c", nfEnt.format(nulos)));
      box.appendChild(ln);
      gB.appendChild(box);
      refBool[c] = { bots: bots, nulInp: inN, nulLab: ln };
    });
    rej.appendChild(gB);

    popFil.appendChild(rej);
  }

  function filtrarValores(col) {
    const r = refFac[col], q = norm(estado.facetas[col].q).trim();
    if (!r) return;
    r.filas.forEach(o => {
      o.lab.style.display = (!q || o.lab._n.indexOf(q) >= 0 || o.inp.checked) ? "" : "none";
    });
  }

  function pintarCuentas(fac) {
    if (!fac) return;
    fac.forEach(f => {
      const r = refFac[f.col];
      if (!r) return;
      r.nul.textContent = nfEnt.format(f.cnt[0]);
      r.nul.classList.toggle("t-cero", f.cnt[0] === 0);
      r.filas.forEach((o, k) => {
        const v = f.cnt[k + 1] || 0;
        o.cnt.textContent = nfEnt.format(v);
        o.lab.classList.toggle("t-cero", v === 0 && !o.inp.checked);
      });
    });
  }

  function hayFiltros() {
    if (estado.busca.trim()) return true;
    if (estado.montana.est !== "" || !estado.montana.nulos) return true;
    for (const f of FACETAS) { const s = estado.facetas[f.c]; if (s && (s.sel.size || !s.nulos)) return true; }
    for (const c of RANGOS) { const s = estado.rangos[c]; if (s && (s.min !== null || s.max !== null || !s.nulos)) return true; }
    for (const c of BOOLS)  { const s = estado.bools[c];  if (s && (s.est !== "" || !s.nulos)) return true; }
    return false;
  }
  // Cuando un filtro restringe pero sigue dejando pasar los NULL, se resalta la
  // casilla: el usuario tiene que ver que las filas sin dato NO desaparecieron.
  function avisar(ref, activo, nulos) {
    if (ref && ref.nulLab) ref.nulLab.classList.toggle("t-nulos-avisa", !!(activo && nulos));
  }
  // Rangos que no se estan aplicando como el usuario cree: texto ilegible o
  // min > max. Se listan para poder avisarlos en el boton y explicar la tabla
  // vacia sin culpar a las casillas de NULL.
  function problemasRangos() {
    const out = [];
    for (const c of RANGOS) {
      const s = estado.rangos[c];
      if (!s || !V.colByName[c]) continue;
      if (s.malMin) out.push({ col: c, tipo: "texto", cual: "mín", txt: s.malMin });
      if (s.malMax) out.push({ col: c, tipo: "texto", cual: "máx", txt: s.malMax });
      if (s.invertido) out.push({ col: c, tipo: "invertido", min: s.min, max: s.max });
    }
    return out;
  }
  // Columnas cuyo "incluir sin dato (NULL)" esta DESmarcado: la unica causa de
  // vacio que justifica mandar al usuario a esas casillas (Regla 1).
  function colsSinNulos() {
    const out = [];
    FACETAS.forEach(f => { const s = estado.facetas[f.c]; if (s && !s.nulos) out.push(f.c); });
    RANGOS.forEach(c => { const s = estado.rangos[c]; if (s && !s.nulos) out.push(c); });
    BOOLS.forEach(c => { const s = estado.bools[c]; if (s && !s.nulos) out.push(c); });
    if (!estado.montana.nulos) out.push("criterio geomorfológico");
    return out;
  }

  // Criterio activo en texto. Se usa en el mensaje de tabla vacia y en la
  // cabecera del CSV: un recorte sin su criterio no se puede volver a defender.
  function resumenFiltros() {
    const p = [];
    if (estado.busca.trim()) p.push('texto "' + estado.busca.trim() + '"');
    if (estado.montana.est === "si") p.push("tramos de montaña (clase_kapos 1–5 o cruza_portezuelo)" + (estado.montana.nulos && cuentaMontana().nul ? " o NULL" : ""));
    else if (estado.montana.est === "no") p.push("resto de la red (ni clase_kapos 1–5 ni cruza_portezuelo)" + (estado.montana.nulos && cuentaMontana().nul ? " o NULL" : ""));
    else if (!estado.montana.nulos) p.push("criterio geomorfológico con dato (sin NULL)");
    FACETAS.forEach(f => {
      const s = estado.facetas[f.c];
      if (!s || !V.colByName[f.c]) return;
      const vals = [];
      if (s.sel.size) {
        if (f.num) s.sel.forEach(v => vals.push(nfNum.format(v)));
        else { const d = dictDe(f.c); s.sel.forEach(k => vals.push(d[k])); }
        vals.sort((x, y) => colator.compare(x, y));
      }
      if (vals.length) p.push(f.c + " ∈ {" + vals.join(", ") + "}" + (s.nulos ? " o NULL" : ""));
      else if (!s.nulos) p.push(f.c + " con dato (sin NULL)");
    });
    RANGOS.forEach(c => {
      const s = estado.rangos[c];
      if (!s || !V.colByName[c]) return;
      const t = [];
      if (s.min !== null) t.push("≥ " + textoNum(s.min));
      if (s.max !== null) t.push("≤ " + textoNum(s.max));
      if (t.length) p.push(c + " " + t.join(" y ") + (s.nulos ? " o NULL" : ""));
      else if (!s.nulos) p.push(c + " con dato (sin NULL)");
      if (s.malMin) p.push(c + " mín «" + s.malMin + "» NO APLICADO (no es número)");
      if (s.malMax) p.push(c + " máx «" + s.malMax + "» NO APLICADO (no es número)");
    });
    BOOLS.forEach(c => {
      const s = estado.bools[c];
      if (!s || !V.colByName[c]) return;
      if (s.est) p.push(c + " = " + (s.est === "si" ? "Sí" : "No") + (s.nulos ? " o NULL" : ""));
      else if (!s.nulos) p.push(c + " con dato (sin NULL)");
    });
    return p.length ? p.join(" · ")
                    : "sin filtros: las " + nfEnt.format(V.n) + " filas de la base";
  }

  function textoOrden() {
    if (!orden.col) return "orden natural del archivo (fila del parquet)";
    return orden.col + " " + (orden.dir > 0 ? "ascendente" : "descendente") +
           " · los NULL siempre al final";
  }

  // Por que no hay ninguna fila. Antes se acusaba SIEMPRE a las casillas de
  // NULL, incluso cuando estaban todas marcadas: eso empujaba a desmarcarlas a
  // ciegas, que es justo lo que la Regla 1 quiere evitar.
  function describirVacio() {
    const inv = problemasRangos().filter(p => p.tipo === "invertido");
    if (inv.length) {
      const p = inv[0];
      return "El rango «" + p.col + "» pide un mínimo (" + textoNum(p.min) +
        ") mayor que su máximo (" + textoNum(p.max) + "). Ningún tramo puede " +
        "cumplir las dos condiciones a la vez: corrige uno de los dos extremos. " +
        "No es un problema de datos que falten.";
    }
    const sn = colsSinNulos();
    if (sn.length)
      return "Ningún tramo cumple el criterio activo. Está desmarcado «incluir " +
        "sin dato (NULL)» en " + sn.join(", ") + ": esas filas quedan fuera " +
        "aunque su valor no se haya podido derivar. Criterio: " + resumenFiltros() + ".";
    if (estado.busca.trim())
      return "Ningún tramo coincide con «" + estado.busca.trim() + "». La " +
        "búsqueda mira id_tramo, rol, nombre_camino, comuna, provincia, región " +
        "y paso_nombre, y exige que cada palabra aparezca en alguna de ellas. " +
        (resumenFiltros().indexOf("·") >= 0 ? "Criterio completo: " + resumenFiltros() + "." : "");
    return "Ningún tramo cumple la combinación de filtros activos. Todas las " +
      "casillas «incluir sin dato (NULL)» siguen marcadas, así que el vacío no " +
      "viene de las filas sin dato. Criterio: " + resumenFiltros() + ".";
  }

  function marcarActivos() {
    btnFil.classList.toggle("act", hayFiltros() || !popFil.hidden);
    const probs = problemasRangos();
    btnFil.classList.toggle("t-mal", probs.length > 0);
    btnFil.title = probs.length
      ? probs.map(p => p.tipo === "invertido"
          ? p.col + ": mín > máx"
          : p.col + " " + p.cual + ": «" + p.txt + "» no se entiende como número").join("\n")
      : "";
    FACETAS.forEach(f => { const s = estado.facetas[f.c];
      if (s) avisar(refFac[f.c], s.sel.size > 0, s.nulos); });
    RANGOS.forEach(c => { const s = estado.rangos[c];
      if (s) avisar(refRan[c], s.min !== null || s.max !== null, s.nulos); });
    BOOLS.forEach(c => { const s = estado.bools[c];
      if (s) avisar(refBool[c], s.est !== "", s.nulos); });
  }

  function limpiar() {
    estadoInicial();
    elBusca.value = "";
    pintarPanelFiltros();
    recalcular();
  }

  /* --- exportacion CSV --------------------------------------------------- */
  function celdaCsv(col, i) {
    if (esNulo(col, i)) return "";                 // NULL sale vacio, nunca 0
    const c = V.colByName[col], a = V.raw[col];
    let s;
    // numCsv: decimal plano y sin ambiguedad. String() emitiria
    // "6.366642050384794e-7" y, con la coma decimal, "6,366642050384794e-7",
    // que no todos los lectores de CSV aceptan; ademas su forma mas corta puede
    // caer sobre un punto medio entre dos doubles. Ver numCsv().
    if (c.t === "num") s = V.exactoCL(a[i]);
    else if (c.t === "bool") s = a[i] === 1 ? "Sí" : "No";
    else if (c.t === "dict") { const v = dictDe(col)[a[i]]; s = v == null ? "" : v; }
    else s = String(a[i]);
    return /[";\r\n]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
  }
  // sha256 del parquet de origen, declarado por visor_html.py en el <head>.
  // Si no esta, se dice que no esta: no se inventa un identificador.
  function shaParquet() {
    const m = document.querySelector('meta[name="fondef-parquet-sha256"]');
    const v = m ? (m.getAttribute("content") || "").trim() : "";
    return v || null;
  }

  /* Cabecera de procedencia del CSV (Reglas 2 y 5).
     Un CSV suelto con 45 de 18.368 filas, sin criterio, sin orden y con las
     columnas que quedaron guardadas en el navegador de otra sesion es el
     insumo tipico de "porcentaje de la muestra presentado como nacional".
     Estas lineas viajan con el archivo para que eso no pueda pasar callando. */
  function cabeceraCsv(cols, nFilas) {
    const sha = shaParquet();
    const omitidas = V.cols.map(c => c.n).filter(c => cols.indexOf(c) < 0);
    const L = [];
    L.push("Catastro de caminos de montaña — FONDEF IDeA · exportación del visor de tramos");
    L.push("exportado: " + new Date().toISOString().replace("T", " ").slice(0, 19) + " UTC");
    L.push("visor generado: " + ((V.meta && V.meta.generado) || "no declarado"));
    L.push("sha256 de data/processed/tramos.parquet: " +
           (sha || "NO DECLARADO en el HTML — no se puede acreditar el origen"));
    L.push("filas exportadas: " + nFilas + " de " + V.n +
           " — ES UNA SELECCIÓN, no la base completa. Cualquier porcentaje " +
           "calculado sobre este archivo es de la selección, nunca nacional.");
    L.push("criterio de filtro: " + resumenFiltros());
    const tot = totalesSeleccion(V.filtrados);
    L.push("totales de la selección: " + nFilas + " tramos · " + Math.round(tot.km) +
           " km (suma de longitud_calc_m) · " + tot.roles + " roles identificables");
    L.push("orden: " + textoOrden());
    L.push("columnas exportadas: " + cols.length + " de " + V.cols.length +
           " — " + cols.join(", "));
    L.push("columnas omitidas: " + omitidas.length +
           (omitidas.length ? " — " + omitidas.join(", ") : ""));
    const vacias = (V.meta && V.meta.columnas_omitidas) || [];
    if (vacias.length)
      L.push("columnas de la base sin ningún valor (100% NULL), fuera del visor: " +
             vacias.join(", "));
    if (leerLS(LS_COLS) !== null)
      L.push("aviso: la selección de columnas viene guardada en este navegador " +
             "(localStorage «" + LS_COLS + "») y puede ser de una sesión anterior.");
    L.push("formato: columnas separadas por punto y coma · decimal con coma · " +
           "UTF-8 con BOM · celda vacía = NULL en la base, nunca 0");
    // sin ";" ni saltos dentro de los comentarios: un lector que no los salte
    // no debe partir la linea en columnas
    return L.map(s => "# " + s.replace(/;/g, ",").replace(/[\r\n]+/g, " "));
  }

  function descargarCsv() {
    const cols = visibles.slice(), f = V.filtrados;
    const lin = cabeceraCsv(cols, f.length);
    lin.push(cols.join(";"));
    for (let k = 0; k < f.length; k++) {
      const i = f[k], fila = new Array(cols.length);
      for (let j = 0; j < cols.length; j++) fila[j] = celdaCsv(cols[j], i);
      lin.push(fila.join(";"));
    }
    const txt = "\uFEFF" + lin.join("\r\n") + "\r\n";
    const blob = new Blob([txt], { type: "text/csv;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    const fecha = ((V.meta && V.meta.generado) || "").slice(0, 10).replace(/-/g, "") || "sinfecha";
    a.href = url;
    a.download = "tramos_" + f.length + "de" + V.n + "_" + fecha + ".csv";
    document.body.appendChild(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(url), 4000);
  }

  /* =======================================================================
     MONTAJE
     ======================================================================= */
  function init(cont) {
    raiz = cont;
    estadoInicial();

    // columnas guardadas
    let guardadas = null;
    try { guardadas = JSON.parse(leerLS(LS_COLS) || "null"); } catch (e) { guardadas = null; }
    if (Array.isArray(guardadas)) guardadas = guardadas.filter(c => V.colByName[c]);
    visibles = (guardadas && guardadas.length) ? guardadas
             : POR_DEFECTO.filter(c => V.colByName[c]);
    if (!visibles.length) visibles = V.cols.slice(0, 8).map(c => c.n);

    raiz.classList.add("tabla");
    raiz.textContent = "";

    /* barra */
    const barra = el("div", "t-barra");
    elBusca = el("input", "t-busca");
    elBusca.type = "search";
    elBusca.placeholder = "Buscar en id, rol, nombre, comuna, provincia, región, paso…";
    elBusca.setAttribute("aria-label", "Buscar");
    barra.appendChild(elBusca);

    const btnCols = el("button", "btn", "Columnas");
    btnFil = el("button", "btn", "Filtros");
    const btnLimp = el("button", "btn", "Limpiar");
    const btnCsv = el("button", "btn", "Descargar CSV");
    barra.append(btnCols, btnFil, btnLimp, btnCsv);

    elCuenta = el("span", "t-cuenta", "—");
    barra.appendChild(elCuenta);

    popCols = el("div", "t-pop"); popCols.hidden = true;
    popFil  = el("div", "t-pop t-pop-fil"); popFil.hidden = true;
    // Los paneles van FUERA de la barra: la barra lleva overflow:hidden para no
    // desbordar sobre el mapa, y dentro de ella los recortaba a nada.
    const zonaBarra = el("div", "t-zona-barra");
    zonaBarra.append(barra, popCols, popFil);
    raiz.appendChild(zonaBarra);

    /* tabla */
    elScroll = el("div", "t-scroll");
    elScroll.tabIndex = 0;
    elCab = el("div", "t-cab");
    elCuerpo = el("div", "t-cuerpo");
    elScroll.append(elCab, elCuerpo);
    // el texto lo escribe describirVacio() segun la causa real del vacio
    elVacio = el("div", "t-vacio", "");
    elVacio.hidden = true;
    raiz.append(elScroll, elVacio);

    pintarCabecera();
    pintarPanelColumnas();
    pintarPanelFiltros();

    /* eventos de barra */
    function alternar(pop, otro) {
      otro.hidden = true;
      pop.hidden = !pop.hidden;
      btnCols.classList.toggle("act", !popCols.hidden);
      btnFil.classList.toggle("act", !popFil.hidden || hayFiltros());
    }
    // cierra el panel abierto; devuelve cual estaba abierto, o null
    function cerrarPops() {
      const cual = !popCols.hidden ? btnCols : (!popFil.hidden ? btnFil : null);
      popCols.hidden = true; popFil.hidden = true;
      btnCols.classList.remove("act"); marcarActivos();
      return cual;
    }
    btnCols.addEventListener("click", () => alternar(popCols, popFil));
    btnFil.addEventListener("click", () => alternar(popFil, popCols));
    btnLimp.addEventListener("click", limpiar);
    btnCsv.addEventListener("click", descargarCsv);
    document.addEventListener("click", (ev) => {
      // Los paneles viven en zonaBarra, fuera de la barra: un clic dentro de
      // ellos no debe cerrarlos. Un clic en un control que se repinto al
      // instante (p. ej. «limpiar» de una faceta) ya no esta en el documento.
      if (zonaBarra.contains(ev.target) || !ev.target.isConnected) return;
      cerrarPops();
    });
    // Escape cierra el panel abierto. «Columnas» y «Filtros» cubren 811x558 px
    // y solo se cerraban pinchando fuera; la ficha sí cerraba con Escape, lo que
    // hacía la diferencia más desconcertante todavía.
    // Si hay un panel abierto es la capa de arriba y consume el Escape, para no
    // cerrar de paso la ficha; si no lo hay, el evento sigue su camino. Este
    // modulo monta antes que ficha.js, asi que su listener corre primero.
    document.addEventListener("keydown", (ev) => {
      if (ev.key !== "Escape" || ev.defaultPrevented) return;
      const cual = cerrarPops();
      if (!cual) return;
      ev.preventDefault();
      ev.stopImmediatePropagation();
      try { cual.focus(); } catch (e) {}
    });

    let tmr = 0;
    elBusca.addEventListener("input", () => {
      clearTimeout(tmr);
      tmr = setTimeout(() => { estado.busca = elBusca.value; recalcular(); }, 160);
    });

    /* eventos de tabla */
    elScroll.addEventListener("scroll", () => {
      const a = Math.max(0, Math.floor(elScroll.scrollTop / ALTO) - BUF);
      if (a !== ultimoA || elScroll.scrollLeft !== ultimoSL) render();
    }, { passive: true });
    window.addEventListener("resize", () => { ultimoA = -1; render(); });

    elCuerpo.addEventListener("click", (ev) => {
      const f = ev.target.closest ? ev.target.closest(".t-fila") : null;
      if (!f || f._idx == null || f._idx < 0) return;
      seleccionar(f._idx);
    });
    elCuerpo.addEventListener("mouseover", (ev) => {
      const f = ev.target.closest ? ev.target.closest(".t-fila") : null;
      const i = f && f._idx >= 0 ? f._idx : -1;
      if (i !== V.hover) { V.hover = i; V.emit("hover", i); }
    });
    elScroll.addEventListener("mouseleave", () => {
      if (V.hover !== -1) { V.hover = -1; V.emit("hover", -1); }
    });
    elScroll.addEventListener("keydown", (ev) => {
      if (ev.key !== "ArrowDown" && ev.key !== "ArrowUp") return;
      const tot = V.filtrados.length;
      if (!tot) return;
      let p = V.sel >= 0 && posDe[V.sel] >= 0 ? posDe[V.sel] : -1;
      p = ev.key === "ArrowDown" ? Math.min(tot - 1, p + 1) : Math.max(0, p <= 0 ? 0 : p - 1);
      ev.preventDefault();
      const i = V.filtrados[p];
      seleccionar(i);
      verFila(i);
    });

    /* eventos del visor */
    V.on("seleccion", (i) => { verFila(i); ultimoA = -1; render(); });
    V.on("hover", () => repintarMarcas());

    recalcular(false);   // primera pasada sin emitir: los otros modulos aun no montan
  }

  window.Tabla = { init: init };
})();
