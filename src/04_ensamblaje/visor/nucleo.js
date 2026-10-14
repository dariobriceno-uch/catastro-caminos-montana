/* ===========================================================================
   VISOR DE TRAMOS — nucleo
   Decodifica el payload y expone la API que usan mapa.js, tabla.js y ficha.js.
   No calcula ni completa ningun valor: solo lee lo que viene de la base.
   =========================================================================== */
(function () {
  "use strict";

  const V = window.V = {
    n: 0, cols: [], colByName: {}, dicts: {}, desc: {}, proc: {}, procVar: {},
    raw: {}, bbox: null, meta: null, geom: null,
    filtrados: null,     // Int32Array con los indices que pasan los filtros
    sel: -1,             // tramo seleccionado, -1 si ninguno
    hover: -1
  };

  /* --- eventos ---------------------------------------------------------- */
  const subs = {};
  V.on = (ev, cb) => { (subs[ev] = subs[ev] || []).push(cb); };
  V.emit = (ev, d) => { (subs[ev] || []).forEach(cb => cb(d)); };

  /* --- decodificacion --------------------------------------------------- */
  function b64aBytes(b64) {
    const bin = atob(b64);
    const out = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out;
  }

  async function descomprimir(bytes) {
    if (typeof DecompressionStream !== "function")
      throw new Error("Este navegador no soporta DecompressionStream. " +
                      "Se necesita Chrome 80+, Edge 80+, Firefox 113+ o Safari 16.4+.");
    const ds = new DecompressionStream("gzip");
    const stream = new Blob([bytes]).stream().pipeThrough(ds);
    return new Uint8Array(await new Response(stream).arrayBuffer());
  }

  /* --- acceso a valores -------------------------------------------------- */
  // Devuelve el valor tal como esta en la base: numero, texto, booleano o null.
  V.val = function (col, i) {
    const c = V.colByName[col];
    if (!c) return null;
    const a = V.raw[col];
    if (c.t === "dict") {
      const k = a[i];
      if (k < 0) return null;
      const d = V.dicts[col];
      if (k >= d.length) throw new Error("diccionario de " + col + ": código " + k + " fuera de rango");
      return d[k];
    }
    if (c.t === "bool") { const k = a[i]; return k < 0 ? null : k === 1; }
    if (c.t === "num")  { const x = a[i]; return Number.isNaN(x) ? null : x; }
    const s = a[i];     return s === null ? null : s;
  };

  /* --- representacion exacta de un double --------------------------------
     Vive aqui, y no en cada modulo, porque cuando la ficha, el title de la
     tabla y el CSV la implementaban por separado imprimian tres cadenas
     distintas para la misma altitud: la falla conocida "registrar altitudes
     distintas para el mismo objeto en tablas distintas".

     sinExponente: String() emite notacion cientifica bajo 1e-6
     (delta_longitud_pct llega a 6,37e-7) y "6,37e-7" con coma decimal no lo
     acepta cualquier lector de CSV.
     17 cifras cuando la forma corta pasa de 10: la forma corta es la mas breve
     que JS vuelve a leer igual, pero no basta para OTROS lectores — hay un
     valor de dist_punto_censal_m cuya forma corta de 15 cifras cae casi en el
     punto medio entre dos doubles y el strtod de R en Windows lo desvia un ULP.
     17 cifras determinan el double sin ambiguedad para cualquier lector. */
  function sinExponente(s) {
    const m = /^(-?)(\d+)(?:\.(\d+))?[eE]([+-]?\d+)$/.exec(s);
    if (!m) return s;
    const sig = m[1], dig = m[2] + (m[3] || "");
    const punto = m[2].length + parseInt(m[4], 10);
    let cuerpo;
    if (punto <= 0) cuerpo = "0." + "0".repeat(-punto) + dig;
    else if (punto >= dig.length) cuerpo = dig + "0".repeat(punto - dig.length);
    else cuerpo = dig.slice(0, punto) + "." + dig.slice(punto);
    return sig + cuerpo;
  }
  function cifrasSig(s) {
    return s.replace(/^[+-]/, "").replace(".", "")
            .replace(/^0+/, "").replace(/0+$/, "").length;
  }
  // Decimal plano con punto. Reproduce el parquet bit a bit.
  V.exacto = function (x) {
    if (typeof x !== "number" || Number.isNaN(x)) return "";
    const corto = sinExponente(String(x));
    return cifrasSig(corto) <= 10 ? corto : sinExponente(x.toPrecision(17));
  };
  // Lo mismo con coma decimal y sin separador de miles: legible en es-CL y
  // todavia legible por una maquina.
  V.exactoCL = function (x) { return V.exacto(x).replace(".", ","); };

  // Años e identificadores no llevan separador de miles: "2.025" se lee como
  // dos mil veinticinco y es el año 2025.
  const SIN_MILES = new Set(["tmda_anio", "objectid_mop", "utm_zona",
                             "clase_kapos", "km_inicio", "km_fin"]);

  // Texto para mostrar. Celda vacia = NULL en la base, nunca un valor inventado.
  V.fmt = function (col, i) {
    const v = V.val(col, i);
    if (v === null) return "";
    if (typeof v === "boolean") return v ? "Sí" : "No";
    if (typeof v === "number")
      return v.toLocaleString("es-CL", { maximumFractionDigits: 3,
                                         useGrouping: !SIN_MILES.has(col) });
    return v;
  };

  V.esNulo = (col, i) => V.val(col, i) === null;

  // Procedencia declarada del campo para ese tramo (Regla 2).
  // Un valor NULL no tiene procedencia: procedencia.parquet sólo registra una
  // fila cuando el valor se pudo derivar o declarar. Devolver la procedencia
  // del campo para una celda vacía sería atribuirle un origen que no tiene.
  V.procDe = function (col, i) {
    if (V.val(col, i) === null) return null;
    if (V.procVar[col]) {
      const k = V.procVar[col].por_tramo[i];
      return (k === null || k < 0) ? null : V.procVar[col].opciones[k];
    }
    return V.proc[col] || null;
  };

  /* --- geometria --------------------------------------------------------- */
  // xy: Int32Array de coordenadas cuantizadas, intercaladas lon,lat.
  // Para grados reales: xy[k] / geom.escala
  function armarGeometria(g) {
    const starts = new Int32Array(b64aBytes(g.starts_b64).buffer);
    const deltas = new Int16Array(b64aBytes(g.deltas_b64).buffer);
    const vpp    = g.verts_por_parte;      // vertices de cada parte
    const ppt    = g.partes_por_tramo;     // partes de cada tramo
    const nVert  = g.n_vertices, nParte = vpp.length, nTramo = ppt.length;

    const xy       = new Int32Array(nVert * 2);
    const parteOff = new Int32Array(nParte + 1);   // offset en vertices
    const tramoP0  = new Int32Array(nTramo + 1);   // primera parte de cada tramo
    const bboxT    = new Int32Array(nTramo * 4);

    for (let p = 0, acc = 0; p < nParte; p++) { parteOff[p] = acc; acc += vpp[p]; }
    parteOff[nParte] = nVert;
    for (let t = 0, acc = 0; t < nTramo; t++) { tramoP0[t] = acc; acc += ppt[t]; }
    tramoP0[nTramo] = nParte;

    let iv = 0, id = 0;
    for (let p = 0; p < nParte; p++) {
      let cx = starts[p * 2], cy = starts[p * 2 + 1];
      xy[iv * 2] = cx; xy[iv * 2 + 1] = cy; iv++;
      for (let j = 1; j < vpp[p]; j++) {
        cx += deltas[id * 2]; cy += deltas[id * 2 + 1]; id++;
        xy[iv * 2] = cx; xy[iv * 2 + 1] = cy; iv++;
      }
    }
    if (iv !== nVert) throw new Error("geometria: vertices reconstruidos " + iv + " != " + nVert);

    for (let t = 0; t < nTramo; t++) {
      let x0 = Infinity, y0 = Infinity, x1 = -Infinity, y1 = -Infinity;
      for (let p = tramoP0[t]; p < tramoP0[t + 1]; p++)
        for (let k = parteOff[p]; k < parteOff[p + 1]; k++) {
          const x = xy[k * 2], y = xy[k * 2 + 1];
          if (x < x0) x0 = x; if (x > x1) x1 = x;
          if (y < y0) y0 = y; if (y > y1) y1 = y;
        }
      bboxT[t * 4] = x0; bboxT[t * 4 + 1] = y0; bboxT[t * 4 + 2] = x1; bboxT[t * 4 + 3] = y1;
    }

    return { xy, parteOff, tramoP0, bboxT, escala: g.escala, tol_m: g.tol_m,
             nVert, nParte, nTramo };
  }

  /* --- arranque ---------------------------------------------------------- */
  V.cargar = async function (b64) {
    const json = new TextDecoder("utf-8").decode(await descomprimir(b64aBytes(b64)));
    const P = JSON.parse(json);

    V.meta = P.meta; V.n = P.meta.n_tramos; V.bbox = P.bbox;
    V.cols = P.cols; P.cols.forEach(c => { V.colByName[c.n] = c; });
    V.desc = P.desc; V.proc = P.proc; V.procVar = P.proc_var || {};

    // Un diccionario de un solo valor puede llegar como texto suelto si el
    // serializador lo desempaquetó. Sin esto, V.dicts[col][0] indexaría el
    // primer carácter y el visor mostraría un valor que la base no contiene.
    V.dicts = {};
    for (const k in P.dicts) {
      const d = P.dicts[k];
      V.dicts[k] = Array.isArray(d) ? d : [d];
    }

    // columnas a arrays tipados; NA -> -1 en dict/bool, NaN en num
    for (const c of P.cols) {
      const a = P.data[c.n];
      if (c.t === "dict" || c.t === "bool") {
        const t = new Int32Array(V.n);
        for (let i = 0; i < V.n; i++) t[i] = (a[i] === null) ? -1 : a[i];
        V.raw[c.n] = t;
      } else if (c.t === "num") {
        const t = new Float64Array(V.n);
        for (let i = 0; i < V.n; i++) t[i] = (a[i] === null) ? NaN : a[i];
        V.raw[c.n] = t;
      } else {
        V.raw[c.n] = a;
      }
    }

    V.geom = armarGeometria(P.geom);
    if (V.geom.nTramo !== V.n)
      throw new Error("geometria: " + V.geom.nTramo + " tramos != " + V.n + " filas");

    V.filtrados = new Int32Array(V.n);
    for (let i = 0; i < V.n; i++) V.filtrados[i] = i;
    return V;
  };
})();
