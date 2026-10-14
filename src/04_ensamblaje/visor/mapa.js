/* ===========================================================================
   VISOR DE TRAMOS — mapa
   Dibuja los tramos sobre un <canvas>. No hay basemap ni tiles: la propia red
   vial dibuja el contorno del pais. Sin red, sin librerias.

   No calcula ni completa ningun valor: el color sale de V.raw / V.val, y un
   tramo con NULL en la variable activa se pinta con --f-nulo-graf (el gris de
   grafico; --f-nulo es el tono de TEXTO) y aparece en la leyenda como
   "sin dato (NULL)". Nunca se le asigna una clase plausible.

   Los cortes de las clases numericas se calculan solo sobre los tramos que
   tienen dato. La nota de la leyenda declara ese numero, nunca el total de la
   base: presentar 18.368 donde el calculo uso 1.850 es exactamente la falla
   "etiquetar un porcentaje calculado sobre la muestra como porcentaje nacional"
   de REGLAS.md.
   =========================================================================== */
(function () {
  "use strict";

  /* --- constantes ------------------------------------------------------- */
  var D2R = Math.PI / 180;
  var CIRC = 40075016.686;      // m del ecuador = 1 unidad de mundo en x
  var PAD_BASE = 200;           // margen (px css) del lienzo cacheado
  var TOL_PX = 7;               // radio de busqueda del hover
  var MAX_CAT = 12;             // clases de una paleta categorica
  var N_SEQ = 7;                // pasos de la rampa secuencial

  var COLOREABLES = [
    { c: "", t: "(sin color)" },
    { c: "clase_kapos", t: "clase_kapos" },
    { c: "cota_max", t: "cota_max" },
    { c: "dias_nieve_mediana", t: "dias_nieve_mediana" },
    { c: "meses_nieve", t: "meses_nieve" },
    { c: "pendiente_media", t: "pendiente_media" },
    { c: "vertiente", t: "vertiente" },
    { c: "unidad_geomorf", t: "unidad_geomorf" },
    { c: "region", t: "region" },
    { c: "carpeta", t: "carpeta" },
    { c: "clasificacion", t: "clasificacion" },
    { c: "es_paso", t: "es_paso" },
    { c: "cruza_portezuelo", t: "cruza_portezuelo" },
    { c: "tmda", t: "tmda" }
  ];

  /* --- proyeccion Web Mercator normalizada a [0,1] ---------------------- */
  function wX(lon) { return lon / 360 + 0.5; }
  function wY(lat) {
    if (lat > 85.05) lat = 85.05; else if (lat < -85.05) lat = -85.05;
    var s = Math.sin(lat * D2R);
    return 0.5 - Math.log((1 + s) / (1 - s)) / (4 * Math.PI);
  }
  function latDe(wy) {
    return (2 * Math.atan(Math.exp(Math.PI - 2 * Math.PI * wy)) - Math.PI / 2) / D2R;
  }

  /* --- utilidades numericas --------------------------------------------- */
  function nf(x, d) {
    return x.toLocaleString("es-CL", { minimumFractionDigits: d, maximumFractionDigits: d });
  }
  function decPara(rango) {
    if (!isFinite(rango) || rango >= 100) return 0;
    if (rango >= 10) return 1;
    if (rango >= 1) return 2;
    return 3;
  }
  function esc(s) {
    return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  }

  /* ====================================================================== */
  function init(raiz) {
    var G = V.geom, E = G.escala;
    var P0 = G.tramoP0, PO = G.parteOff, XY = G.xy, BT = G.bboxT;
    var N = V.n;

    /* --- geometria proyectada, una sola vez ----------------------------- */
    var t0 = performance.now();
    var wxy = new Float64Array(G.nVert * 2);
    for (var k = 0; k < G.nVert; k++) {
      wxy[k * 2] = XY[k * 2] / E / 360 + 0.5;
      wxy[k * 2 + 1] = wY(XY[k * 2 + 1] / E);
    }
    // bbox de cada tramo ya en coordenadas de mundo (culling y LOD exactos)
    var wb = new Float64Array(N * 4);
    for (var t = 0; t < N; t++) {
      wb[t * 4] = BT[t * 4] / E / 360 + 0.5;
      wb[t * 4 + 2] = BT[t * 4 + 2] / E / 360 + 0.5;
      wb[t * 4 + 1] = wY(BT[t * 4 + 3] / E);   // lat maxima -> y minima
      wb[t * 4 + 3] = wY(BT[t * 4 + 1] / E);
    }
    var msProyeccion = performance.now() - t0;

    /* --- DOM ------------------------------------------------------------ */
    raiz.innerHTML =
      '<div class="mapa-raiz">' +
      '<canvas class="mapa-lienzo"></canvas>' +
      '<canvas class="mapa-encima"></canvas>' +
      '<div class="mapa-tt"></div>' +
      '<div class="mapa-caja mapa-color">' +
      '<div class="mapa-color-cab"><label for="mapa-var">Color</label>' +
      '<select id="mapa-var"></select></div>' +
      '<div class="mapa-leyenda"></div></div>' +
      '<div class="mapa-caja mapa-zoom">' +
      '<button data-a="mas" title="Acercar">+</button>' +
      '<button data-a="menos" title="Alejar">−</button>' +
      '<div class="sep"></div>' +
      '<button data-a="ajustar" class="chico" title="Volver al encuadre completo">▢</button>' +
      '<div class="sep"></div>' +
      '<button data-a="n" class="chico" title="Encuadrar el tercio norte del área de datos">N</button>' +
      '<button data-a="c" class="chico" title="Encuadrar el tercio central del área de datos">C</button>' +
      '<button data-a="s" class="chico" title="Encuadrar el tercio sur del área de datos">S</button>' +
      '</div>' +
      '<div class="mapa-caja mapa-pie">' +
      '<div class="mapa-escala"><div class="mapa-escala-t"></div><div class="mapa-escala-b"></div></div>' +
      '<div class="mapa-nota">geometría simplificada a ' + G.tol_m + ' m</div>' +
      '</div></div>';

    var cont = raiz.querySelector(".mapa-raiz");
    var cv = raiz.querySelector(".mapa-lienzo");
    var cvOv = raiz.querySelector(".mapa-encima");
    var ctx = cv.getContext("2d");
    var ctxOv = cvOv.getContext("2d");
    var elTT = raiz.querySelector(".mapa-tt");
    var elLey = raiz.querySelector(".mapa-leyenda");
    var selVar = raiz.querySelector("#mapa-var");
    var elEscT = raiz.querySelector(".mapa-escala-t");
    var elEscB = raiz.querySelector(".mapa-escala-b");
    var elNota = raiz.querySelector(".mapa-nota");

    COLOREABLES.forEach(function (o) {
      if (o.c && !V.colByName[o.c]) return;
      var op = document.createElement("option");
      op.value = o.c; op.textContent = o.t;
      var d = o.c && V.desc[o.c];
      if (d && d.que_es) op.title = d.que_es;
      selVar.appendChild(op);
    });

    /* --- lienzo cacheado ------------------------------------------------ */
    var off = document.createElement("canvas");
    var ctxOff = off.getContext("2d");
    var offVista = null, offW = 0, offH = 0;

    /* --- estado --------------------------------------------------------- */
    var W = 0, H = 0, dpr = 1, PAD = PAD_BASE;
    var vista = { x: 0, y: 0, s: 1 };
    var sAjuste = 1, sMin = 1, sMax = 5e7;
    var ajustado = false;
    var COL = {};
    var esca = null;            // escala de color activa
    var bk = null;              // Int32Array: clase de cada tramo (-1 = NULL)
    var clases = [];            // [{etiqueta,color,idx:Int32Array}] idx[0] = NULL
    var fuera = new Int32Array(0);
    var dentro = null;          // Uint8Array: 1 si el tramo pasa el filtro
    var selFueraLey = false;    // ultimo estado dibujado de la fila de leyenda
    var verFuera = true;
    var msUltimo = 0;
    var pendPintar = false, pendRender = false, tmrRender = 0;
    var anim = null;
    var sinLOD = false;          // solo para medir: apaga el submuestreo

    /* --- colores desde CSS (nunca escritos en el codigo) ---------------- */
    function leerColores() {
      var cs = getComputedStyle(document.documentElement);
      var g = function (n) { return cs.getPropertyValue(n).trim() || "#888"; };
      // --f-nulo es el gris de TEXTO (contraste 4.5:1). Para pintar en el lienzo
      // y para las muestras de color de la leyenda va --f-nulo-graf, que conserva
      // el gris claro que distingue "sin dato" del resto de la rampa.
      COL.nuloGraf = g("--f-nulo-graf");
      COL.sel = g("--f-sel");
      COL.acento = g("--f-acento");
      COL.linea = g("--m-linea");
      COL.fuera = g("--m-fuera");
      COL.seq = []; for (var i = 0; i < N_SEQ; i++) COL.seq.push(g("--m-seq-" + i));
      COL.cat = []; for (var j = 0; j < MAX_CAT; j++) COL.cat.push(g("--m-cat-" + j));
    }

    /* --- escalas de color ----------------------------------------------- */
    function escalaDe(col) {
      if (!col) return null;
      var c = V.colByName[col], a = V.raw[col], i;

      if (c.t === "bool") {
        return { tipo: "cat", etq: ["No", "Sí"], cols: [COL.cat[0], COL.cat[1]],
          clase: function (i) { var x = a[i]; return x < 0 ? -1 : (x === 1 ? 1 : 0); } };
      }

      if (c.t === "dict") {
        var dic = V.dicts[col], nd = dic.length;
        var cnt = new Int32Array(nd);
        for (i = 0; i < N; i++) { var kk = a[i]; if (kk >= 0) cnt[kk]++; }
        var ord = [];
        for (i = 0; i < nd; i++) if (cnt[i] > 0) ord.push(i);
        ord.sort(function (p, q) { return cnt[q] - cnt[p]; });
        var cabe = ord.length <= MAX_CAT ? ord.length : MAX_CAT - 1;
        var mapa = new Int32Array(nd); for (i = 0; i < nd; i++) mapa[i] = cabe; // resto
        var etq = [], cols = [];
        for (i = 0; i < cabe; i++) { mapa[ord[i]] = i; etq.push(dic[ord[i]]); cols.push(COL.cat[i]); }
        if (ord.length > cabe) {
          etq.push("otras (" + (ord.length - cabe) + " categorías)");
          cols.push(COL.cat[MAX_CAT - 1]);
        }
        return { tipo: "cat", etq: etq, cols: cols,
          clase: function (i) { var x = a[i]; return x < 0 ? -1 : mapa[x]; } };
      }

      // numerica
      var vals = [];
      for (i = 0; i < N; i++) { var v = a[i]; if (!Number.isNaN(v)) vals.push(v); }
      if (!vals.length) return { tipo: "num", etq: [], cols: [], clase: function () { return -1; } };
      vals.sort(function (p, q) { return p - q; });
      var uni = [];
      for (i = 0; i < vals.length; i++) if (!i || vals[i] !== vals[i - 1]) uni.push(vals[i]);

      if (uni.length <= N_SEQ + 2) {          // ordinal: una clase por valor
        var pos = {}, e2 = [], c2 = [];
        var paso = uni.length > 1 ? (N_SEQ - 1) / (uni.length - 1) : 0;
        var enteros = uni.every(function (v) { return Number.isInteger(v); });
        var d0 = enteros ? 0 : decPara(uni[uni.length - 1] - uni[0]);
        for (i = 0; i < uni.length; i++) {
          pos[uni[i]] = i; e2.push(nf(uni[i], d0));
          c2.push(COL.seq[Math.min(N_SEQ - 1, Math.round(i * paso))]);
        }
        return { tipo: "num", etq: e2, cols: c2,
          clase: function (i) { var v = a[i]; return Number.isNaN(v) ? -1 : pos[v]; },
          nota: uni.length + " valores distintos entre los " +
                vals.length.toLocaleString("es-CL") + " tramos con dato" +
                (N > vals.length ? " (los " + (N - vals.length).toLocaleString("es-CL") +
                 " sin dato quedan fuera)" : "") + ", uno por clase" };
      }

      // cuantiles sobre TODOS los tramos CON DATO (no sobre el filtro): asi el
      // color de un tramo no cambia al mover un filtro. Los NULL no participan:
      // no hay valor que ordenar, y contarlos inflaria la base del calculo.
      var cortes = [], notaCero = "";
      // Variable con mas de la mitad de ceros (dias_nieve_mediana: 90 % de los
      // tramos sin nieve): los cuantiles colapsan todos en 0 y queda una sola
      // clase util. Se separa la clase "0" y los cortes se calculan sobre los
      // valores positivos. La leyenda lo declara.
      var nCero = 0; while (nCero < vals.length && vals[nCero] === 0) nCero++;
      var pos = nCero > vals.length / 2 ? vals.slice(nCero) : null;
      if (pos && pos.length >= N_SEQ) {
        cortes.push(pos[0]);                     // todo lo > 0 sale de la clase 0
        for (i = 1; i < N_SEQ - 1; i++) {
          var qp = pos[Math.min(pos.length - 1, Math.floor(i / (N_SEQ - 1) * pos.length))];
          if (qp > cortes[cortes.length - 1]) cortes.push(qp);
        }
        notaCero = "clase 0 aparte (" + nCero.toLocaleString("es-CL") + " tramos); ";
      } else {
        for (i = 1; i < N_SEQ; i++) {
          var q = vals[Math.min(vals.length - 1, Math.floor(i / N_SEQ * vals.length))];
          if (!cortes.length || q > cortes[cortes.length - 1]) cortes.push(q);
        }
      }
      var lo = vals[0], hi = vals[vals.length - 1];
      var nk = cortes.length + 1;

      // Cada clase se rotula con el minimo y el maximo REALMENTE observados en
      // ella, no con el corte del cuantil. Rotular el corte redondeado dejaba
      // tramos fuera del intervalo que su propia etiqueta declara: los cortes de
      // cota_max son 95,625943 · 152,057887 · … y se imprimian 96 · 152, de modo
      // que 49 tramos quedaban del lado que la etiqueta les negaba, y 1.020 en
      // pendiente_media. Con los extremos observados, redondeados hacia afuera,
      // ningun miembro puede caer fuera de su rotulo.
      var vmin = new Array(nk), vmax = new Array(nk);
      for (i = 0; i < nk; i++) { vmin[i] = Infinity; vmax[i] = -Infinity; }
      for (i = 0; i < vals.length; i++) {
        var vv = vals[i], b0 = 0, e0 = cortes.length;
        while (b0 < e0) { var m0 = (b0 + e0) >> 1; if (vv < cortes[m0]) e0 = m0; else b0 = m0 + 1; }
        if (vv < vmin[b0]) vmin[b0] = vv;
        if (vv > vmax[b0]) vmax[b0] = vv;
      }
      function piso(x, d) { var p = Math.pow(10, d); return Math.floor(x * p) / p; }
      function techo(x, d) { var p = Math.pow(10, d); return Math.ceil(x * p) / p; }

      // Decimales minimos con los que dos etiquetas contiguas no se pisan.
      var enteroTodo = Number.isInteger(lo) && Number.isInteger(hi);
      for (i = 0; i < cortes.length; i++) if (!Number.isInteger(cortes[i])) { enteroTodo = false; break; }
      var dd = enteroTodo ? 0 : decPara(hi - lo);
      for (var d2 = dd; d2 <= 6; d2++) {
        var ok = true;
        for (i = 0; i + 1 < nk && ok; i++)
          if (vmax[i] > -Infinity && vmin[i + 1] < Infinity &&
              techo(vmax[i], d2) > piso(vmin[i + 1], d2)) ok = false;
        if (ok) { dd = d2; break; }
        dd = d2;
      }

      var etq3 = [], tit3 = [], cols3 = [];
      for (i = 0; i < nk; i++) {
        if (vmax[i] === -Infinity) {
          etq3.push("(sin tramos)");
          tit3.push("ninguna fila de la base cae en esta clase");
        } else {
          var b1 = nf(piso(vmin[i], dd), dd), b2 = nf(techo(vmax[i], dd), dd);
          etq3.push(b1 === b2 ? b1 : b1 + " – " + b2);
          tit3.push("valores observados en esta clase, de " + b1 + " a " + b2 +
                    (i === 0 ? "" : "; el corte del cuantil está en " + V.exactoCL(cortes[i - 1]) +
                                    " y esta clase lo incluye"));
        }
        cols3.push(COL.seq[nk > 1
          ? Math.min(N_SEQ - 1, Math.round(i * (N_SEQ - 1) / (nk - 1))) : 0]);
      }
      return { tipo: "num", etq: etq3, tit: tit3, cols: cols3,
        clase: function (i) {
          var v = a[i]; if (Number.isNaN(v)) return -1;
          var b = 0, e = cortes.length;
          while (b < e) { var m = (b + e) >> 1; if (v < cortes[m]) e = m; else b = m + 1; }
          return b;
        },
        // El total de la base NO es la base del calculo: los cortes salen solo de
        // los tramos con dato. Declararlo sobre V.n contradecia la propia linea
        // "sin dato (NULL)" de la leyenda.
        nota: notaCero + "cortes por cuantiles sobre los " + (pos && pos.length >= N_SEQ ? pos.length : vals.length).toLocaleString("es-CL") +
              (pos && pos.length >= N_SEQ ? " tramos con valor > 0" : " tramos con dato en esta variable") +
              (N > vals.length
                ? "; los " + (N - vals.length).toLocaleString("es-CL") +
                  " sin dato (NULL) quedan fuera del cálculo"
                : " (ninguno queda sin dato)") +
              ". Cada clase incluye su límite inferior y excluye el superior; " +
              "las etiquetas muestran los valores observados en cada clase" };
    }

    function construirEscala() {
      var col = selVar.value;
      esca = escalaDe(col);
      bk = new Int32Array(N);
      if (!esca) { for (var i = 0; i < N; i++) bk[i] = 0; }
      else {
        var nk = esca.cols.length;
        for (var j = 0; j < N; j++) {
          var b = esca.clase(j);
          bk[j] = (b == null || b < 0) ? -1 : Math.min(b, nk - 1);
        }
      }
      repartir();
    }

    /* reparte V.filtrados en listas por clase (clases[0] = NULL) */
    function repartir() {
      var col = selVar.value;
      var nk = esca ? esca.cols.length : 1;
      var cnt = new Int32Array(nk + 1);      // [0] = NULL
      var f = V.filtrados, i, t;
      for (i = 0; i < f.length; i++) { var b = bk[f[i]]; cnt[b < 0 ? 0 : b + 1]++; }
      var listas = []; for (i = 0; i <= nk; i++) listas.push(new Int32Array(cnt[i]));
      var pos = new Int32Array(nk + 1);
      for (i = 0; i < f.length; i++) {
        t = f[i]; var b2 = bk[t]; var s = b2 < 0 ? 0 : b2 + 1;
        listas[s][pos[s]++] = t;
      }
      clases = [];
      clases.push({ etiqueta: "sin dato (NULL)", color: COL.nuloGraf, idx: listas[0], nulo: true });
      for (i = 0; i < nk; i++)
        clases.push({ etiqueta: esca ? esca.etq[i] : "todos los tramos",
                      titulo: esca && esca.tit ? esca.tit[i] : null,
                      color: esca ? esca.cols[i] : COL.linea, idx: listas[i + 1] });

      // pertenencia al filtro: la usan buscar() y el trazo del seleccionado
      dentro = new Uint8Array(N);
      for (i = 0; i < f.length; i++) dentro[f[i]] = 1;
      // tramos excluidos por el filtro
      if (f.length >= N) { fuera = new Int32Array(0); }
      else {
        fuera = new Int32Array(N - f.length);
        var p = 0; for (i = 0; i < N; i++) if (!dentro[i]) fuera[p++] = i;
      }
      selFueraLey = selExcluido();
      pintarLeyenda(col);
    }

    /* El tramo seleccionado no pasa el filtro actual. No es un caso raro: basta
       seleccionar y despues buscar otra cosa. */
    function selExcluido() { return V.sel >= 0 && !!dentro && !dentro[V.sel]; }

    /* Procedencia de la CAPA. Solo se declara si todos los tramos dibujados que
       tienen dato comparten la misma terna (fuente, fecha, metodo); si difieren,
       no se declara ninguna. Antes se mostraba la del primer tramo de
       V.filtrados como si fuera la de la capa entera, y cambiaba al filtrar.
       Las celdas NULL no tienen procedencia (V.procDe devuelve null) y por eso
       no cuentan ni la contradicen. */
    function procComun(col) {
      if (!col) return null;
      var f = V.filtrados, ref = null, n = 0;
      for (var i = 0; i < f.length; i++) {
        var p = V.procDe(col, f[i]);
        if (!p) continue;
        if (!ref) ref = p;
        else if (p.fuente !== ref.fuente || p.fecha !== ref.fecha || p.metodo !== ref.metodo)
          return null;
        n++;
      }
      return n ? { pr: ref, n: n, total: f.length } : null;
    }

    function pintarLeyenda(col) {
      var h = "", i;
      for (i = 1; i < clases.length; i++) {
        var c = clases[i];
        h += '<div class="mapa-ley-fila"><span class="mapa-ley-sw" style="background:' +
             c.color + '"></span><span class="mapa-ley-tx" title="' +
             esc(c.titulo || c.etiqueta) + '">' +
             esc(c.etiqueta) + '</span><span class="mapa-ley-n">' +
             c.idx.length.toLocaleString("es-CL") + "</span></div>";
      }
      if (col) {
        h += '<div class="mapa-ley-sep"></div>';
        h += '<div class="mapa-ley-fila nulo"><span class="mapa-ley-sw" style="background:' +
             COL.nuloGraf + '"></span><span class="mapa-ley-tx">sin dato (NULL)</span>' +
             '<span class="mapa-ley-n">' + clases[0].idx.length.toLocaleString("es-CL") +
             "</span></div>";
      }
      if (fuera.length) {
        if (!col) h += '<div class="mapa-ley-sep"></div>';
        h += '<div class="mapa-ley-fila fuera' + (verFuera ? "" : " apagada") +
             '" title="Tramos que no pasan el filtro. Clic para mostrarlos u ocultarlos.">' +
             '<span class="mapa-ley-sw" style="background:' + COL.fuera + '"></span>' +
             '<span class="mapa-ley-tx">fuera del filtro</span><span class="mapa-ley-n">' +
             fuera.length.toLocaleString("es-CL") + "</span></div>";
      }
      if (selExcluido()) {
        h += '<div class="mapa-ley-sep"></div>';
        h += '<div class="mapa-ley-fila sel-fuera" title="El tramo seleccionado no ' +
             'pasa el filtro actual. Se dibuja con trazo discontinuo y sigue siendo ' +
             'clicable, pero no forma parte del conjunto filtrado ni de los conteos ' +
             'de la leyenda.">' +
             '<span class="mapa-ley-sw disc" style="--sw:' + COL.sel + '"></span>' +
             '<span class="mapa-ley-tx">seleccionado, fuera del filtro</span>' +
             '<span class="mapa-ley-n">1</span></div>';
      }
      var notas = [];
      if (esca && esca.nota) notas.push(esca.nota);
      if (col && V.desc[col] && V.desc[col].que_es) notas.push(V.desc[col].que_es);
      var pc = procComun(col);
      if (pc) notas.push("fuente " + pc.pr.fuente + " · " + pc.pr.fecha + " · " +
        pc.pr.metodo + ", igual en los " + pc.n.toLocaleString("es-CL") +
        (pc.n === pc.total ? " tramos dibujados" : " tramos dibujados con dato"));
      notas = notas.map(function (s) { return String(s).replace(/\s*\.\s*$/, ""); });
      if (notas.length) h += '<div class="mapa-ley-nota">' + esc(notas.join(". ")) + ".</div>";
      elLey.innerHTML = h;
      var ff = elLey.querySelector(".mapa-ley-fila.fuera");
      if (ff) ff.addEventListener("click", function () {
        verFuera = !verFuera; ff.classList.toggle("apagada", !verFuera); render();
      });
    }

    /* La fila "seleccionado, fuera del filtro" depende de V.sel, que cambia sin
       que cambie el filtro: hay que repintar la leyenda cuando ese estado gira. */
    function refrescarLeySel() {
      var e = selExcluido();
      if (e !== selFueraLey) { selFueraLey = e; pintarLeyenda(selVar.value); }
    }

    /* --- dibujo ---------------------------------------------------------- */
    function anchoLinea(s) {
      var r = s / sAjuste;
      return Math.min(2.4, 0.85 + Math.log(Math.max(1, r)) / Math.LN2 * 0.16);
    }

    // agrega los vertices de un tramo al path actual, submuestreando segun el
    // tamano que ocupa en pantalla.
    // El paso se calcula POR PARTE. Con el total de vertices del tramo,
    // una parte mas corta que el paso no entraba nunca al bucle interior y se
    // dibujaba como una cuerda recta entre su primer y su ultimo vertice: 87
    // tramos del payload son multiparte y 181 de esas partes tienen menos de 8
    // vertices. Usar el conteo de la parte, con el span del tramo (que la
    // acota), submuestrea de menos, nunca de mas.
    function trazar(c, t, vx, vy, vs) {
      var b = t * 4;
      var span = Math.max((wb[b + 2] - wb[b]) * vs, (wb[b + 3] - wb[b + 1]) * vs);
      var coste = 0;
      for (var p = P0[t]; p < P0[t + 1]; p++) {
        var a = PO[p], z = PO[p + 1], nvp = z - a;
        if (nvp < 1) continue;
        var ax = (wxy[a * 2] - vx) * vs, ay = (wxy[a * 2 + 1] - vy) * vs;
        c.moveTo(ax, ay);
        if (nvp === 1) { c.lineTo(ax, ay); coste += 2; continue; }  // vertice suelto
        var paso = 1;
        if (!sinLOD && span < nvp * 0.5)
          paso = Math.max(1, Math.floor(nvp / Math.max(2, span * 2)));
        for (var q = a + paso; q < z - 1; q += paso)
          c.lineTo((wxy[q * 2] - vx) * vs, (wxy[q * 2 + 1] - vy) * vs);
        var e = z - 1;
        c.lineTo((wxy[e * 2] - vx) * vs, (wxy[e * 2 + 1] - vy) * vs);
        coste += Math.ceil(nvp / paso) + 2;
      }
      return coste;
    }

    function trazarLista(c, lista, vx, vy, vs, bx1, by1) {
      var acc = 0, dib = 0;
      c.beginPath();
      for (var i = 0; i < lista.length; i++) {
        var t = lista[i], b = t * 4;
        if (wb[b + 2] < vx || wb[b] > bx1 || wb[b + 3] < vy || wb[b + 1] > by1) continue;
        acc += trazar(c, t, vx, vy, vs); dib++;
        if (acc > 30000) { c.stroke(); c.beginPath(); acc = 0; }
      }
      c.stroke();
      return dib;
    }

    // render completo al lienzo cacheado, con margen PAD alrededor del visible
    function render() {
      if (!W || !H) return;
      var t1 = performance.now();
      var aw = W + PAD * 2, ah = H + PAD * 2;
      if (offW !== aw || offH !== ah || off.width !== Math.round(aw * dpr)) {
        offW = aw; offH = ah;
        off.width = Math.round(aw * dpr); off.height = Math.round(ah * dpr);
      }
      var vx = vista.x - PAD / vista.s, vy = vista.y - PAD / vista.s, vs = vista.s;
      var bx1 = vx + aw / vs, by1 = vy + ah / vs;

      ctxOff.setTransform(dpr, 0, 0, dpr, 0, 0);
      ctxOff.clearRect(0, 0, aw, ah);
      ctxOff.lineCap = "round"; ctxOff.lineJoin = "round";
      var lw = anchoLinea(vs), dib = 0;

      if (verFuera && fuera.length) {
        ctxOff.globalAlpha = 0.34;
        ctxOff.strokeStyle = COL.fuera;
        ctxOff.lineWidth = Math.max(0.5, lw * 0.65);
        dib += trazarLista(ctxOff, fuera, vx, vy, vs, bx1, by1);
        ctxOff.globalAlpha = 1;
      }
      // con un filtro muy selectivo, unos pocos tramos finos se pierden sobre la
      // capa de contexto: se engrosan para que sigan siendo legibles
      ctxOff.lineWidth = lw + (V.filtrados.length < 2500 ? 0.9 : 0);
      for (var i = 0; i < clases.length; i++) {           // NULL primero, abajo
        if (!clases[i].idx.length) continue;
        ctxOff.strokeStyle = clases[i].color;
        dib += trazarLista(ctxOff, clases[i].idx, vx, vy, vs, bx1, by1);
      }
      offVista = { x: vx, y: vy, s: vs };
      msUltimo = performance.now() - t1;
      pintar();
      return { ms: msUltimo, tramos: dib };
    }

    // blit del lienzo cacheado a la vista actual (barato: 1 drawImage)
    function pintar() {
      if (!W || !H) return;
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      ctx.clearRect(0, 0, W, H);
      if (offVista) {
        var f = vista.s / offVista.s;
        var dx = (offVista.x - vista.x) * vista.s;
        var dy = (offVista.y - vista.y) * vista.s;
        ctx.imageSmoothingEnabled = true;
        ctx.drawImage(off, 0, 0, off.width, off.height, dx, dy, offW * f, offH * f);
      }
      pintarEncima();
      escalaGrafica();
    }

    function pintarUno(c, t, color, ancho) {
      c.strokeStyle = color; c.lineWidth = ancho;
      c.beginPath(); trazar(c, t, vista.x, vista.y, vista.s); c.stroke();
    }

    function pintarEncima() {
      if (!W || !H) return;
      ctxOv.setTransform(dpr, 0, 0, dpr, 0, 0);
      ctxOv.clearRect(0, 0, W, H);
      ctxOv.lineCap = "round"; ctxOv.lineJoin = "round";
      var lw = anchoLinea(vista.s);
      if (V.hover >= 0 && V.hover !== V.sel) pintarUno(ctxOv, V.hover, COL.acento, lw + 1.8);
      if (V.sel >= 0) {
        // El seleccionado se dibuja siempre: el usuario lo eligio y la ficha esta
        // mostrando sus datos. Pero si el filtro lo excluye no puede pasar por un
        // tramo mas del conjunto filtrado (antes se trazaba identico, incluso con
        // la capa "fuera del filtro" apagada): va discontinuo, la leyenda lo
        // anuncia y buscar() lo incluye para que siga siendo clicable.
        var ex = selExcluido(), an = lw + 2.6;
        // el lineCap redondo alarga cada guion media anchura por lado y tapaba el
        // hueco: con la linea a ~3 px el trazo discontinuo se veia continuo
        if (ex) { ctxOv.lineCap = "butt"; ctxOv.setLineDash([an * 2.4, an * 2]); }
        pintarUno(ctxOv, V.sel, COL.sel, an);
        if (ex) { ctxOv.setLineDash([]); ctxOv.lineCap = "round"; }
      }
    }

    function escalaGrafica() {
      var lat = latDe(vista.y + H / 2 / vista.s);
      var mpp = CIRC * Math.cos(lat * D2R) / vista.s;      // metros por px css
      var objetivo = mpp * 110;
      var pot = Math.pow(10, Math.floor(Math.log(objetivo) / Math.LN10));
      var r = objetivo / pot, mult = r >= 5 ? 5 : (r >= 2 ? 2 : 1);
      var m = mult * pot;
      elEscB.style.width = Math.round(m / mpp) + "px";
      elEscT.textContent = m >= 1000 ? nf(m / 1000, m >= 10000 ? 0 : 1) + " km"
                                     : nf(m, 0) + " m";
      elNota.title = "Último redibujado completo: " + msUltimo.toFixed(1) + " ms";
    }

    /* --- programacion de repintados -------------------------------------- */
    function pintarRAF() {
      if (pendPintar) return;
      pendPintar = true;
      requestAnimationFrame(function () { pendPintar = false; pintar(); });
    }
    function renderRAF() {
      if (pendRender) return;
      pendRender = true;
      requestAnimationFrame(function () { pendRender = false; render(); });
    }
    function renderPronto(ms) {
      clearTimeout(tmrRender);
      tmrRender = setTimeout(render, ms);
    }
    // durante el arrastre: si la vista salio del margen cacheado, hay que
    // rehacer el cache o apareceria un borde vacio
    function fueraDelCache() {
      if (!offVista) return true;
      if (Math.abs(vista.s / offVista.s - 1) > 0.02) return true;
      var dx = (offVista.x - vista.x) * vista.s, dy = (offVista.y - vista.y) * vista.s;
      return dx > -2 || dy > -2 || dx + offW * (vista.s / offVista.s) < W + 2 ||
             dy + offH * (vista.s / offVista.s) < H + 2;
    }

    /* --- encuadres -------------------------------------------------------- */
    function encuadrar(lon0, lat0, lon1, lat1, margen) {
      if (!W || !H) return;
      margen = margen == null ? 0.08 : margen;
      var x0 = wX(lon0), x1 = wX(lon1), y0 = wY(lat1), y1 = wY(lat0);
      var dw = Math.max(x1 - x0, 1e-9), dh = Math.max(y1 - y0, 1e-9);
      var s = Math.min(W * (1 - margen * 2) / dw, H * (1 - margen * 2) / dh);
      s = Math.max(1e-6, Math.min(sMax, s));
      vista = { x: (x0 + x1) / 2 - W / 2 / s, y: (y0 + y1) / 2 - H / 2 / s, s: s };
    }
    // escala (px css por unidad de mundo) a la que el bbox completo entra en el
    // panel; se recalcula en cada resize para que "ajustar" siempre quepa
    function escalaAjuste() {
      var bb = V.bbox, m = 0.05;
      var dw = Math.max(wX(bb[2]) - wX(bb[0]), 1e-9);
      var dh = Math.max(wY(bb[1]) - wY(bb[3]), 1e-9);
      return Math.min(W * (1 - m * 2) / dw, H * (1 - m * 2) / dh);
    }
    function ajustar() {
      var b = V.bbox;
      encuadrar(b[0], b[1], b[2], b[3], 0.05);
    }
    function tercio(i) {
      var b = V.bbox, y0 = wY(b[3]), y1 = wY(b[1]);
      var a = y0 + (y1 - y0) * i / 3, z = y0 + (y1 - y0) * (i + 1) / 3;
      encuadrar(b[0], latDe(z), b[2], latDe(a), 0.04);
      limitar(); render();
    }
    function limitar() {
      if (vista.s < sMin) vista.s = sMin;
      if (vista.s > sMax) vista.s = sMax;
      var b = V.bbox, x0 = wX(b[0]), x1 = wX(b[2]), y0 = wY(b[3]), y1 = wY(b[1]);
      var mx = W * 0.45 / vista.s, my = H * 0.45 / vista.s;
      if (vista.x > x1 + mx - W / vista.s) vista.x = x1 + mx - W / vista.s;
      if (vista.x < x0 - mx) vista.x = x0 - mx;
      if (vista.y > y1 + my - H / vista.s) vista.y = y1 + my - H / vista.s;
      if (vista.y < y0 - my) vista.y = y0 - my;
    }
    function zoomEn(px, py, factor) {
      var wx = vista.x + px / vista.s, wy = vista.y + py / vista.s;
      var s = Math.max(sMin, Math.min(sMax, vista.s * factor));
      vista.x = wx - px / s; vista.y = wy - py / s; vista.s = s;
      limitar();
    }

    // "esta en el viewport" = su bbox toca el 90% central de la pantalla. No se
    // exige que quepa entero: un tramo largo puede salirse y no por eso hay que
    // reencuadrar cada vez que se hace clic sobre el.
    function visibleEnPantalla(t) {
      var b = t * 4;
      var mx = W * 0.05 / vista.s, my = H * 0.05 / vista.s;
      var x0 = vista.x + mx, x1 = vista.x + W / vista.s - mx;
      var y0 = vista.y + my, y1 = vista.y + H / vista.s - my;
      return !(wb[b + 2] < x0 || wb[b] > x1 || wb[b + 3] < y0 || wb[b + 1] > y1);
    }
    // fraccion del panel que ocupa el bbox del tramo (1 = lo llena)
    function fracEnPantalla(t) {
      var b = t * 4;
      return Math.max((wb[b + 2] - wb[b]) * vista.s / W,
                      (wb[b + 3] - wb[b + 1]) * vista.s / H);
    }
    // A escala pais casi cualquier bbox "toca el 90% central", asi que estar
    // visible no bastaba: un tramo de 13 km quedaba en 2 px y no se encuadraba
    // nunca. Tambien se encuadra cuando el tramo se ve menos de la mitad de
    // grande de lo que escalaPara() puede darle. Al reves no: si ya se ve grande
    // —aunque se salga por los bordes— no se toca el encuadre, que es el que el
    // usuario esta usando para inspeccionarlo. Comparar contra escalaPara evita
    // ademas reencuadrar en bucle un tramo tan corto que ni al maximo llega al
    // tamano pedido.
    function necesitaEncuadre(t) {
      if (!visibleEnPantalla(t)) return true;
      return vista.s < escalaPara(t) * 0.5;
    }

    // vuelo suave hacia un tramo. Se rehace el cache en el destino antes de
    // animar: asi el blit intermedio es una reduccion (nitida), no una ampliacion.
    // Escala a la que el tramo ocupa ~60% del panel. Antes solo se alejaba
    // (if (necesita < s)): a escala pais un tramo de 13 km quedaba en 2 px, es
    // decir se "volaba" a un punto invisible. Encuadrar es acercar tambien.
    // Tope del encuadre automatico: no acercarse mas alla de la resolucion que la
    // propia geometria declara (simplificada a G.tol_m m, como dice el pie del
    // mapa). Mas cerca, el encuadre aparentaria una precision que el payload no
    // tiene. El zoom manual con la rueda no se toca.
    function escalaTope(t) {
      var b = t * 4;
      var lat = latDe((wb[b + 1] + wb[b + 3]) / 2);
      return CIRC * Math.cos(lat * D2R) / (G.tol_m / 4);   // 1 px css = tol_m/4 m
    }
    function escalaPara(t) {
      var b = t * 4;
      var techo = Math.min(sMax, escalaTope(t));
      var ex = wb[b + 2] - wb[b], ey = wb[b + 3] - wb[b + 1];
      var mayor = Math.max(ex, ey);
      // bbox degenerado (un solo vertice): no hay tamano al que encuadrar
      if (!(mayor > 0)) return Math.max(sMin, techo);
      // piso proporcional: un tramo casi recto N-S tiene ex ~ 0 y dividir por el
      // daria una escala absurda
      var piso = mayor * 1e-3;
      var s = Math.min(W * 0.6 / Math.max(ex, piso), H * 0.6 / Math.max(ey, piso));
      return Math.max(sMin, Math.min(techo, s));
    }

    function volarA(t) {
      var b = t * 4;
      var cx = (wb[b] + wb[b + 2]) / 2, cy = (wb[b + 1] + wb[b + 3]) / 2;
      var s = escalaPara(t);
      var destino = { x: cx - W / 2 / s, y: cy - H / 2 / s, s: s };
      var origen = { x: vista.x, y: vista.y, s: vista.s };
      var guarda = vista;
      vista = destino; limitar(); destino = vista; vista = guarda;
      if (anim) cancelAnimationFrame(anim.id);
      var d = { x: destino.x, y: destino.y, s: destino.s };
      vista = d; render(); vista = origen;              // cache en el destino
      var t0a = performance.now(), dur = 380;
      anim = { id: 0 };
      (function paso() {
        var u = Math.min(1, (performance.now() - t0a) / dur);
        var e = u < 0.5 ? 2 * u * u : 1 - Math.pow(-2 * u + 2, 2) / 2;
        var ls = Math.exp(Math.log(origen.s) + (Math.log(d.s) - Math.log(origen.s)) * e);
        vista = { x: origen.x + (d.x - origen.x) * e, y: origen.y + (d.y - origen.y) * e, s: ls };
        pintar();
        if (u < 1) anim.id = requestAnimationFrame(paso);
        else { anim = null; vista = { x: d.x, y: d.y, s: d.s }; render(); }
      })();
    }

    /* --- hover / seleccion ------------------------------------------------ */
    function d2Seg(px, py, ax, ay, bx, by) {
      var dx = bx - ax, dy = by - ay, L = dx * dx + dy * dy;
      var u = L > 0 ? ((px - ax) * dx + (py - ay) * dy) / L : 0;
      if (u < 0) u = 0; else if (u > 1) u = 1;
      var qx = ax + u * dx - px, qy = ay + u * dy - py;
      return qx * qx + qy * qy;
    }
    function d2Tramo(t, px, py) {
      var vx = vista.x, vy = vista.y, vs = vista.s, mejor = Infinity;
      for (var p = P0[t]; p < P0[t + 1]; p++) {
        var a = PO[p], z = PO[p + 1];
        var ax = (wxy[a * 2] - vx) * vs, ay = (wxy[a * 2 + 1] - vy) * vs;
        if (z - a === 1) {
          var q0 = ax - px, q1 = ay - py; var d0 = q0 * q0 + q1 * q1;
          if (d0 < mejor) mejor = d0; continue;
        }
        for (var k = a + 1; k < z; k++) {
          var bx = (wxy[k * 2] - vx) * vs, by = (wxy[k * 2 + 1] - vy) * vs;
          var d = d2Seg(px, py, ax, ay, bx, by);
          if (d < mejor) mejor = d;
          ax = bx; ay = by;
        }
      }
      return mejor;
    }
    function buscar(px, py) {
      var wtol = TOL_PX / vista.s;
      var wx = vista.x + px / vista.s, wy = vista.y + py / vista.s;
      var f = V.filtrados, mejor = -1, md = TOL_PX * TOL_PX;
      // el seleccionado que el filtro excluye se dibuja, asi que tiene que poder
      // volver a clicarse; si no, queda un trazo inerte que no se puede quitar
      var extra = selExcluido() ? V.sel : -1;
      var nn = f.length + (extra >= 0 ? 1 : 0);
      for (var i = 0; i < nn; i++) {
        var t = i < f.length ? f[i] : extra, b = t * 4;
        if (wb[b + 2] < wx - wtol || wb[b] > wx + wtol ||
            wb[b + 3] < wy - wtol || wb[b + 1] > wy + wtol) continue;
        var d = d2Tramo(t, px, py);
        if (d < md) { md = d; mejor = t; }
      }
      return mejor;
    }

    function celda(col, i) {
      var s = V.fmt(col, i);
      return s === "" ? '<span class="vacio">—</span>' : esc(s);
    }
    function mostrarTT(t, px, py) {
      if (t < 0) { elTT.classList.remove("visible"); return; }
      elTT.innerHTML =
        '<span class="id">' + celda("id_tramo", t) + "</span>" +
        '<span class="nom">' + celda("nombre_camino", t) + "</span>" +
        '<span class="l2">rol ' + celda("rol", t) + " · " + celda("comuna", t) + "</span>";
      elTT.classList.add("visible");
      var w = elTT.offsetWidth, h = elTT.offsetHeight;
      var x = px + 14, y = py + 14;
      if (x + w > W - 4) x = px - w - 14;
      if (y + h > H - 4) y = py - h - 14;
      elTT.style.left = Math.max(4, x) + "px";
      elTT.style.top = Math.max(4, y) + "px";
    }

    /* --- eventos de puntero ----------------------------------------------- */
    var arr = null, movX = 0, movY = 0, pendHover = false, hx = 0, hy = 0;

    cv.addEventListener("pointerdown", function (e) {
      try { cv.setPointerCapture(e.pointerId); } catch (err) {}
      arr = { x: e.clientX, y: e.clientY, vx: vista.x, vy: vista.y, t: performance.now() };
      movX = 0; movY = 0;
      if (anim) { cancelAnimationFrame(anim.id); anim = null; }
    });
    cv.addEventListener("pointermove", function (e) {
      var r = cv.getBoundingClientRect();
      hx = e.clientX - r.left; hy = e.clientY - r.top;
      if (arr) {
        var dx = e.clientX - arr.x, dy = e.clientY - arr.y;
        movX = Math.abs(dx); movY = Math.abs(dy);
        vista.x = arr.vx - dx / vista.s; vista.y = arr.vy - dy / vista.s;
        limitar();
        if (fueraDelCache()) renderRAF(); else pintarRAF();
        renderPronto(140);
        elTT.classList.remove("visible");
        return;
      }
      if (pendHover) return;
      pendHover = true;
      requestAnimationFrame(function () {
        pendHover = false;
        var t = buscar(hx, hy);
        if (t !== V.hover) { V.hover = t; V.emit("hover", t); pintarEncima(); }
        mostrarTT(t, hx, hy);
        cv.style.cursor = t >= 0 ? "pointer" : "crosshair";
      });
    });
    function soltar(e) {
      if (!arr) return;
      var clic = movX < 4 && movY < 4 && performance.now() - arr.t < 500;
      arr = null;
      render();
      if (clic) {
        var r = cv.getBoundingClientRect();
        var t = buscar(e.clientX - r.left, e.clientY - r.top);
        if (t !== V.sel) { V.sel = t; V.emit("seleccion", t); pintarEncima(); }
      }
    }
    cv.addEventListener("pointerup", soltar);
    window.addEventListener("pointerup", soltar);   // por si el puntero se solto fuera
    cv.addEventListener("pointercancel", function () { arr = null; render(); });
    cv.addEventListener("pointerleave", function () {
      if (V.hover !== -1) { V.hover = -1; V.emit("hover", -1); pintarEncima(); }
      elTT.classList.remove("visible");
    });
    cv.addEventListener("wheel", function (e) {
      e.preventDefault();
      var r = cv.getBoundingClientRect();
      var d = e.deltaMode === 1 ? e.deltaY * 16 : (e.deltaMode === 2 ? e.deltaY * H : e.deltaY);
      zoomEn(e.clientX - r.left, e.clientY - r.top, Math.exp(-d * 0.0022));
      pintarRAF(); renderPronto(70);
      elTT.classList.remove("visible");
    }, { passive: false });
    cv.addEventListener("dblclick", function (e) {
      var r = cv.getBoundingClientRect();
      zoomEn(e.clientX - r.left, e.clientY - r.top, 2);
      render();
    });

    raiz.querySelector(".mapa-zoom").addEventListener("click", function (e) {
      var b = e.target.closest("button"); if (!b) return;
      var a = b.getAttribute("data-a");
      if (a === "mas") { zoomEn(W / 2, H / 2, 1.7); render(); }
      else if (a === "menos") { zoomEn(W / 2, H / 2, 1 / 1.7); render(); }
      else if (a === "ajustar") { ajustar(); render(); }
      else if (a === "n") tercio(0);
      else if (a === "c") tercio(1);
      else if (a === "s") tercio(2);
    });

    selVar.addEventListener("change", function () { construirEscala(); render(); });

    /* --- tamano ----------------------------------------------------------- */
    function redimensionar() {
      var r = cont.getBoundingClientRect();
      var nw = Math.round(r.width), nh = Math.round(r.height);
      var nd = window.devicePixelRatio || 1;
      if (nw === W && nh === H && nd === dpr) return;
      // Punto del mundo que estaba en el centro de la vista. Al abrirse la ficha
      // el mapa se encoge por la derecha; sin conservar el centro, el tramo
      // recien encuadrado se corria hacia el borde (o se salia).
      var ccx = W && H ? vista.x + W / 2 / vista.s : null;
      var ccy = W && H ? vista.y + H / 2 / vista.s : null;
      W = nw; H = nh; dpr = nd;
      if (!W || !H) return;
      PAD = Math.round(PAD_BASE / Math.min(2, Math.max(1, dpr)));
      cv.width = Math.round(W * dpr); cv.height = Math.round(H * dpr);
      cvOv.width = cv.width; cvOv.height = cv.height;
      sAjuste = escalaAjuste(); sMin = sAjuste * 0.4;
      if (!ajustado) { ajustar(); ajustado = true; }
      else {
        if (ccx !== null) { vista.x = ccx - W / 2 / vista.s; vista.y = ccy - H / 2 / vista.s; }
        limitar();
      }
      render();
    }
    new ResizeObserver(redimensionar).observe(cont);
    window.addEventListener("resize", redimensionar);

    /* --- eventos del visor ------------------------------------------------ */
    V.on("filtro", function () { repartir(); render(); });
    // La ficha se abre dentro de este mismo evento y encoge el mapa. Decidir el
    // encuadre con el ancho viejo dejaba el tramo fuera de la vista nueva: se
    // pinta ya para responder al instante, y el encuadre se decide en el cuadro
    // siguiente, cuando redimensionar() ya midio el panel definitivo.
    var pendSel = -2;
    V.on("seleccion", function (t) {
      pintarEncima();
      pendSel = t;
      requestAnimationFrame(function () {
        var s = pendSel; pendSel = -2;
        if (s === -2) return;
        redimensionar();
        refrescarLeySel();
        if (s >= 0 && necesitaEncuadre(s)) volarA(s);
        else pintarEncima();
      });
    });
    V.on("hover", function () { pintarEncima(); });
    V.on("tema", function () {
      leerColores(); construirEscala(); render();
    });
    V.on("listo", redimensionar);

    /* --- arranque --------------------------------------------------------- */
    leerColores();
    construirEscala();
    redimensionar();

    /* --- diagnostico (lo usa visor_check.py) ------------------------------ */
    window.Mapa.medir = function (k, apagarLOD) {
      k = k || 5;
      var ms = [], r = null;
      sinLOD = !!apagarLOD;
      for (var i = 0; i < k; i++) { r = render(); ms.push(+r.ms.toFixed(1)); }
      sinLOD = false;
      ms.sort(function (a, b) { return a - b; });
      return { ms_mediana: ms[ms.length >> 1], ms: ms, tramos_dibujados: r.tramos,
               sin_submuestreo: !!apagarLOD,
               vertices: G.nVert, ms_proyeccion_inicial: +msProyeccion.toFixed(1),
               dpr: dpr, ancho: W, alto: H };
    };
    window.Mapa.estado = function () {
      return { vista: { x: vista.x, y: vista.y, s: vista.s, W: W, H: H },
        clases: clases.map(function (c) {
        return { etiqueta: c.etiqueta, titulo: c.titulo || null, n: c.idx.length }; }),
        fuera: fuera.length, ver_fuera: verFuera, ms_ultimo_render: +msUltimo.toFixed(1),
        variable: selVar.value || null,
        sel: V.sel, sel_fuera_del_filtro: selExcluido(),
        nota: (function () { var e = elLey.querySelector(".mapa-ley-nota");
                             return e ? e.textContent : null; })(),
        s_ajuste: sAjuste, s_min: sMin,
        // fraccion del panel que ocupa el bbox del seleccionado: 0 = un punto
        frac_sel: V.sel >= 0 ? fracEnPantalla(V.sel) : null,
        s_encuadre_sel: V.sel >= 0 ? escalaPara(V.sel) : null };
    };
    // solo para pruebas: clase que el mapa asigna a un tramo (-1 = sin dato)
    window.Mapa.claseDe = function (t) { return bk ? bk[t] : null; };
  }

  window.Mapa = { init: init };
})();
