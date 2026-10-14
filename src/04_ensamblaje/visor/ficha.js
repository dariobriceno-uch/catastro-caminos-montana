/* ===========================================================================
   VISOR DE TRAMOS — ficha.js
   Cajon lateral con las 63 variables de un tramo y su procedencia (Regla 2).

   Este modulo NO calcula, NO estima y NO completa ningun valor: todo lo que
   muestra sale de V.val / V.fmt / V.procDe / V.desc, es decir, de la base.
   Un campo NULL se muestra vacio con la etiqueta tenue "sin dato" (Regla 1);
   nunca como 0, "N/D" ni un valor plausible.
   =========================================================================== */
(function () {
  "use strict";

  /* --- agrupacion de las 63 variables en bloques legibles ----------------
     El orden es solo de presentacion. Ninguna columna se omite: las que no
     figuren en esta tabla se agregan al final en "Otras variables".        */
  const BLOQUES = [
    ["Identificación", [
      "id_tramo", "id_tramo_a1", "objectid_mop", "en_lista_colega"]],
    ["Red vial (MOP)", [
      "rol", "rol_id", "codigo_camino", "nombre_camino", "clasificacion",
      "carpeta", "calzada", "orientacion_ruta", "enrolado", "concesionado",
      "tuicion", "km_inicio", "km_fin", "km_tramo"]],
    ["Segmentación", [
      "subdividido", "motivo_corte", "longitud_calc_m", "delta_longitud_pct",
      "coord_inicio", "coord_fin", "utm_zona"]],
    ["Altimetría (DEM)", [
      "cota_min", "cota_max", "cota_media", "cota_culminante",
      "pendiente_media", "pendiente_max", "orientacion_ladera", "sinuosidad",
      "desnivel_subida_m", "desnivel_bajada_m", "cruza_portezuelo",
      "clase_kapos", "cota_max_z_mop", "delta_z_m"]],
    ["Territorio", [
      "region", "provincia", "comuna"]],
    ["Fronteras", [
      "es_paso", "paso_nombre", "paso_pais", "paso_trafico",
      "paso_habilitacion", "dist_limite_m", "en_zona_fronteriza"]],
    ["Geomorfología (FT-10)", [
      "unidad_geomorf", "vertiente", "n_unidades_geomorf"]],
    ["Cobertura nival (FT-08, MODIS)", [
      "dias_nieve_mediana", "dias_nieve_media", "dias_nieve_sd", "meses_nieve",
      "n_anios_validos", "dias_validos_mediana", "serie_inicio", "serie_fin"]],
    ["Centros invernales", [
      "es_esqui", "esqui_nombre", "esqui_cota_base"]],
    ["Localidades y servicios", [
      "es_localidad", "localidad_nombre", "dist_servicios_km", "buffer_join_m"]],
    ["Tránsito", [
      "tmda", "tmda_invierno", "tmda_composicion", "tmda_anio",
      "punto_censal_id", "dist_punto_censal_m", "match_metodo"]]
  ];

  /* Los tres metodos de la Regla 2. No existe un cuarto valor. */
  const METODOS = {
    derivado:  { sig: "der", cls: "m-der",
      tit: "derivado — calculado por código sobre un ráster o un vector de data/raw/" },
    declarado: { sig: "dec", cls: "m-dec",
      tit: "declarado — copiado tal cual de un atributo de la fuente" },
    estimado:  { sig: "est", cls: "m-est",
      tit: "estimado — método documentado en el commit" }
  };
  const SIN_PROC = { sig: "·", cls: "m-nd",
    tit: "sin procedencia declarada para este campo en procedencia.parquet" };
  /* Una celda vacia no lleva insignia: procedencia.parquet solo registra una
     fila cuando el valor existe, asi que un NULL no tiene metodo, ni fuente,
     ni fecha, ni agente. Mostrar "·" aqui lo confundiria con los campos que
     si tienen valor y no tienen procedencia declarada. */
  const VACIA = { cls: "m-vac" };

  /* --- unidades ---------------------------------------------------------
     Copiadas de docs/esquema.md y docs/descripciones_columnas.csv. No se
     infiere ninguna del nombre de la columna: km_inicio, km_fin y km_tramo
     estan en METROS pese al nombre, y asi lo dicen las dos fuentes.
     `nota` se muestra en el title de la unidad.                             */
  const KM_EN_M = "La fuente entrega METROS pese al nombre «km» " +
    "(docs/esquema.md: «Unidad verificada 2026-08-26: la capa entrega METROS " +
    "pese al nombre»). Un valor 32200 es el kilómetro 32,2 del camino.";
  const UNIDAD = {
    km_inicio:           { u: "m",       nota: KM_EN_M },
    km_fin:              { u: "m",       nota: KM_EN_M },
    km_tramo:            { u: "m",       nota: KM_EN_M },
    longitud_calc_m:     { u: "m" },
    delta_longitud_pct:  { u: "%" },
    cota_min:            { u: "msnm",    nota: "metros sobre el nivel del mar" },
    cota_max:            { u: "msnm",    nota: "metros sobre el nivel del mar" },
    cota_media:          { u: "msnm",    nota: "metros sobre el nivel del mar" },
    cota_culminante:     { u: "msnm",    nota: "metros sobre el nivel del mar" },
    cota_max_z_mop:      { u: "msnm",    nota: "metros sobre el nivel del mar" },
    esqui_cota_base:     { u: "msnm",    nota: "metros sobre el nivel del mar; " +
                                               "no es una cota del camino" },
    delta_z_m:           { u: "m" },
    desnivel_subida_m:   { u: "m" },
    desnivel_bajada_m:   { u: "m" },
    pendiente_media:     { u: "°",       nota: "grados" },
    pendiente_max:       { u: "°",       nota: "grados" },
    dist_limite_m:       { u: "m" },
    dist_punto_censal_m: { u: "m" },
    buffer_join_m:       { u: "m" },
    dist_servicios_km:   { u: "km" },
    dias_nieve_mediana:  { u: "días/año", nota: "mediana 2010–2024, escalada a 365; entorno de 500 m (MODIS), no la calzada" },
    dias_nieve_media:    { u: "días/año", nota: "media 2010–2024, escalada a 365" },
    dias_nieve_sd:       { u: "días",     nota: "desviación estándar interanual" },
    meses_nieve:         { u: "meses",    nota: "meses con mediana interanual > 5 días con nieve" },
    n_anios_validos:     { u: "años",     nota: "años con ≥ 60 días observados sin nube" },
    dias_validos_mediana:{ u: "días/año", nota: "mediana de días con observación válida" },
    tmda:                { u: "veh/día", nota: "vehículos promedio por día" },
    tmda_invierno:       { u: "veh/día", nota: "vehículos promedio por día" }
  };

  /* --- ceros que la propia fuente declara como «no informado» ------------
     docs/descripciones_columnas.csv, fila km_tramo: «Un valor 0 significa que
     la fuente no lo informó». El 0 esta en la base y no se convierte en NULL,
     pero no puede presentarse como si fuera una longitud medida.            */
  const CERO_NO_INFORMADO = {
    km_tramo: {
      corto: "no informado",
      largo: "km_tramo = 0. Según docs/descripciones_columnas.csv, un valor 0 " +
             "significa que la fuente (Vialidad) no informó la longitud del " +
             "tramo; no es una longitud de cero metros. La longitud medida " +
             "sobre la geometría está en longitud_calc_m."
    }
  };

  const CIFRAS = [
    ["cota_max", "Cota máxima"], ["cota_min", "Cota mínima"],
    ["km_tramo", "Longitud declarada"], ["clase_kapos", "Clase Kapos"]
  ];

  const LS_OCULTAR = "visor-ficha-ocultar-nulos";

  /* --- utilidades -------------------------------------------------------- */
  function el(tag, cls, txt) {
    const e = document.createElement(tag);
    if (cls) e.className = cls;
    if (txt != null) e.textContent = txt;
    return e;
  }
  function css(nombre) {
    return getComputedStyle(document.documentElement).getPropertyValue(nombre).trim();
  }
  function guardar(k, v) { try { localStorage.setItem(k, v); } catch (e) {} }
  function leer(k) { try { return localStorage.getItem(k); } catch (e) { return null; } }

  /* Representacion exacta del valor tal como esta en el parquet. V.fmt redondea
     a 3 decimales para que la cifra se lea; el exacto no se pierde: va al title
     y es lo que se exporta. Dos artefactos del mismo visor no pueden entregar
     altitudes distintas para el mismo tramo.

     numPlano: los mismos digitos que String(x) — la cadena mas corta que vuelve
     a leerse como el mismo double — pero sin notacion cientifica, que aparece
     bajo 1e-6 (delta_longitud_pct llega a 6,37e-7). Con la coma decimal, la
     ficha copiada y el CSV de la tabla escriben exactamente la misma cadena
     para el mismo valor. */
  function numPlano(x) {
    const s = String(x);
    const m = /^(-?)(\d+)(?:\.(\d+))?[eE]([+-]?\d+)$/.exec(s);
    if (!m) return s;
    const sig = m[1], dig = m[2] + (m[3] || "");
    const punto = m[2].length + parseInt(m[4], 10);
    let cuerpo;
    if (punto <= 0)                cuerpo = "0." + "0".repeat(-punto) + dig;
    else if (punto >= dig.length)  cuerpo = dig + "0".repeat(punto - dig.length);
    else                           cuerpo = dig.slice(0, punto) + "." + dig.slice(punto);
    return sig + cuerpo;
  }
  function exacto(col, i) {
    const v = V.val(col, i);
    if (v === null) return "";
    if (typeof v === "boolean") return v ? "Sí" : "No";
    if (typeof v === "number") return V.exactoCL(v);  // misma cadena que tabla y CSV
    return String(v);
  }
  function unidadDe(col) { return UNIDAD[col] || null; }
  /* Avisos de lectura: el valor es el de la base y no se toca, pero se muestra
     junto a la advertencia que la propia documentacion de la columna declara. */
  const SUBDIVIDIDO = {
    corto: "del tramo sin partir",
    largo: "Este tramo se partió (subdividido = Sí), y km_tramo es DECLARADO: " +
           "conserva la longitud que Vialidad da al tramo antes de partirlo, no " +
           "la de esta fila. La longitud de esta fila está en longitud_calc_m, y " +
           "delta_longitud_pct mide la diferencia. Afecta a 4.456 de los 18.368 " +
           "tramos. Sumar km_tramo sobre varias filas del mismo rol contaría el " +
           "mismo camino más de una vez."
  };
  function ceroNoInformado(col, i) {
    const a = CERO_NO_INFORMADO[col];
    if (a && V.val(col, i) === 0) return a;
    if (col === "km_tramo" && V.val("subdividido", i) === true) return SUBDIVIDIDO;
    return null;
  }

  /* Copia al portapapeles. file:// no es contexto seguro, asi que
     navigator.clipboard puede no existir: se cae al textarea + execCommand. */
  function copiar(texto) {
    if (navigator.clipboard && window.isSecureContext) {
      return navigator.clipboard.writeText(texto).then(function () { return true; },
                                                       function () { return respaldo(texto); });
    }
    return Promise.resolve(respaldo(texto));
  }
  function respaldo(texto) {
    try {
      const ta = el("textarea");
      ta.value = texto;
      ta.setAttribute("readonly", "");
      ta.style.cssText = "position:fixed;top:-1000px;left:-1000px;opacity:0";
      document.body.appendChild(ta);
      ta.select();
      const ok = document.execCommand("copy");
      document.body.removeChild(ta);
      return ok;
    } catch (e) { return false; }
  }

  /* --- estado del modulo -------------------------------------------------- */
  let raiz = null, cuerpo = null, ui = {}, filas = {}, actual = -1;
  let ocultarNulos = leer(LS_OCULTAR) === "1";
  let origenFoco = null;      // elemento que tenia el foco cuando se abrio
  let abiertoEn = -1;         // tramo que estaba abierto, para devolver el foco
  /* Bajo 900 px la ficha cubre todo el cuerpo (estilo_base.css): ahi si es un
     dialogo modal. Sobre 900 px es un panel mas en el flujo y no tapa nada,
     asi que convertirlo en modal seria mentirle al lector de pantalla. */
  const mqCubre = window.matchMedia("(max-width:900px)");

  /* --- armado del esqueleto ----------------------------------------------- */
  function montar(el0) {
    raiz = el0;
    raiz.classList.add("ficha");
    raiz.setAttribute("tabindex", "-1");

    /* estilo_base.css cuenta con que la ficha sea el tercer panel dentro del
       flex de #cuerpo: al abrirse el mapa se encoge en vez de quedar tapado.
       Si el armazón todavía la deja como hermana de #cuerpo, queda como una
       franja de 420 px bajo el mapa. Se reubica una sola vez y sin efecto si
       ya está en su sitio. */
    const flujo = document.getElementById("cuerpo");
    if (flujo && raiz.parentNode !== flujo) flujo.appendChild(raiz);

    const cab = el("header", "fi-cab");
    const l1 = el("div", "fi-l1");
    ui.id = el("span", "fi-id mono");
    ui.cerrar = el("button", "fi-x");
    ui.cerrar.type = "button";
    ui.cerrar.title = "Cerrar la ficha (Esc)";
    ui.cerrar.setAttribute("aria-label", "Cerrar la ficha");
    ui.cerrar.textContent = "×";
    l1.appendChild(ui.id); l1.appendChild(ui.cerrar);

    ui.rol = el("div", "fi-rol");
    ui.ubic = el("div", "fi-ubic");
    ui.chips = el("div", "fi-chips");
    ui.cifras = el("div", "fi-cifras");
    cab.appendChild(l1); cab.appendChild(ui.rol); cab.appendChild(ui.ubic);
    cab.appendChild(ui.chips); cab.appendChild(ui.cifras);

    /* barra de navegacion y acciones */
    const barra = el("div", "fi-barra");
    ui.ant = el("button", "btn fi-nav", "‹");
    ui.ant.type = "button"; ui.ant.title = "Tramo anterior dentro del filtro";
    ui.pos = el("span", "fi-pos mono");
    ui.sig = el("button", "btn fi-nav", "›");
    ui.sig.type = "button"; ui.sig.title = "Tramo siguiente dentro del filtro";
    ui.copId = el("button", "btn", "Copiar id");
    ui.copId.type = "button"; ui.copId.title = "Copiar el id_tramo al portapapeles";
    ui.copFicha = el("button", "btn", "Copiar ficha");
    ui.copFicha.type = "button";
    ui.copFicha.title = "Copiar las variables del tramo con su procedencia, como texto";
    barra.appendChild(ui.ant); barra.appendChild(ui.pos); barra.appendChild(ui.sig);
    barra.appendChild(el("span", "fi-esp"));
    barra.appendChild(ui.copId); barra.appendChild(ui.copFicha);

    const barra2 = el("div", "fi-barra fi-barra2");
    const lab = el("label", "fi-toggle");
    ui.chk = document.createElement("input");
    ui.chk.type = "checkbox"; ui.chk.checked = ocultarNulos;
    lab.appendChild(ui.chk);
    lab.appendChild(el("span", null, "ocultar campos sin dato"));
    ui.conteoNulos = el("span", "fi-conteo mono");
    barra2.appendChild(lab);
    barra2.appendChild(el("span", "fi-esp"));
    barra2.appendChild(ui.conteoNulos);

    /* croquis + esquema de cotas */
    const croq = el("section", "fi-croquis");
    croq.appendChild(el("h3", "fi-h3", "Croquis del tramo"));
    ui.cvGeo = document.createElement("canvas");
    ui.cvGeo.className = "fi-cv fi-cv-geo";
    croq.appendChild(ui.cvGeo);
    ui.notaGeo = el("p", "fi-nota");
    croq.appendChild(ui.notaGeo);

    /* la unidad va en el titulo: las tres etiquetas de abajo son cotas */
    croq.appendChild(el("h3", "fi-h3", "Esquema de cotas (msnm)"));
    ui.cvPerfil = document.createElement("canvas");
    ui.cvPerfil.className = "fi-cv fi-cv-perfil";
    croq.appendChild(ui.cvPerfil);
    ui.perfilLabs = el("div", "fi-perfil-labs");
    croq.appendChild(ui.perfilLabs);
    croq.appendChild(el("p", "fi-nota fi-aviso",
      "Esquema de tres cotas (mínima, media, máxima), no es el perfil real del " +
      "camino: el perfil vértice a vértice no está en la base y no se inventa aquí. " +
      "La posición horizontal no indica en qué punto del tramo ocurre cada cota."));

    cuerpo = el("div", "fi-campos");

    const pie = el("footer", "fi-pie");
    ui.notaMeta = el("p", "fi-nota");
    pie.appendChild(ui.notaMeta);
    pie.appendChild(el("p", "fi-nota fi-aviso",
      "Una celda vacía significa NULL en la base: el valor no se pudo derivar de " +
      "data/raw/ y la fila quedó registrada en data/pendientes.csv. No es un cero, " +
      "ni un «sin información», ni un dato pendiente de digitar en el visor."));
    ui.pieProc = el("p", "fi-nota");
    pie.appendChild(ui.pieProc);

    raiz.appendChild(cab); raiz.appendChild(barra); raiz.appendChild(barra2);
    raiz.appendChild(croq); raiz.appendChild(cuerpo); raiz.appendChild(pie);

    construirCampos();
    aplicarOcultar();

    /* --- eventos de la interfaz --- */
    ui.cerrar.addEventListener("click", function () { seleccionar(-1); });
    ui.ant.addEventListener("click", function () { mover(-1); });
    ui.sig.addEventListener("click", function () { mover(+1); });
    ui.copId.addEventListener("click", function () {
      const b = this;
      if (actual < 0) return;
      const t = V.val("id_tramo", actual);
      copiar(t === null ? "" : String(t)).then(function (ok) { avisar(b, ok); });
    });
    ui.copFicha.addEventListener("click", function () {
      const b = this;
      if (actual < 0) return;
      copiar(fichaComoTexto(actual)).then(function (ok) { avisar(b, ok); });
    });
    ui.chk.addEventListener("change", function () {
      ocultarNulos = ui.chk.checked;
      guardar(LS_OCULTAR, ocultarNulos ? "1" : "0");
      aplicarOcultar();
    });
    cuerpo.addEventListener("click", function (ev) {
      const f = ev.target.closest(".fi-fila");
      if (f && cuerpo.contains(f)) alternarDetalle(f);
    });
    cuerpo.addEventListener("keydown", function (ev) {
      if (ev.key !== "Enter" && ev.key !== " ") return;
      const f = ev.target.closest(".fi-fila");
      if (f && cuerpo.contains(f)) { ev.preventDefault(); alternarDetalle(f); }
    });
    document.addEventListener("keydown", function (ev) {
      /* Sin stopPropagation: otros modulos pueden tener su propio Escape. */
      if (ev.key === "Escape" && raiz.classList.contains("abierto")) seleccionar(-1);
    });
    document.addEventListener("keydown", atraparTab, true);
    mqCubre.addEventListener
      ? mqCubre.addEventListener("change", aplicarModal)
      : mqCubre.addListener(aplicarModal);
    window.addEventListener("resize", function () { if (actual >= 0) dibujar(actual); });
  }

  /* --- foco: dialogo solo cuando la ficha cubre el cuerpo (F7) ------------- */
  function aplicarModal() {
    if (!raiz) return;
    if (raiz.classList.contains("abierto") && mqCubre.matches) {
      raiz.setAttribute("role", "dialog");
      raiz.setAttribute("aria-modal", "true");
    } else {
      raiz.removeAttribute("role");
      raiz.removeAttribute("aria-modal");
    }
  }

  function tabulables() {
    const sel = "button:not([disabled]),input:not([disabled]),select,textarea," +
                "a[href],[tabindex]:not([tabindex=\"-1\"])";
    return Array.prototype.filter.call(raiz.querySelectorAll(sel), function (e) {
      return e.offsetWidth > 0 || e.offsetHeight > 0 || e === document.activeElement;
    });
  }

  function atraparTab(ev) {
    if (ev.key !== "Tab" || !raiz) return;
    if (!raiz.classList.contains("abierto") || !mqCubre.matches) return;
    const f = tabulables();
    if (!f.length) { ev.preventDefault(); raiz.focus(); return; }
    const pri = f[0], ult = f[f.length - 1], act = document.activeElement;
    if (!raiz.contains(act)) { ev.preventDefault(); (ev.shiftKey ? ult : pri).focus(); }
    else if (ev.shiftKey && act === pri) { ev.preventDefault(); ult.focus(); }
    else if (!ev.shiftKey && act === ult) { ev.preventDefault(); pri.focus(); }
  }

  /* Al cerrar, el foco vuelve a la fila de la tabla que abrio la ficha; si esa
     fila ya no esta en el DOM (la tabla es virtual y recicla filas), vuelve a
     donde estaba antes de abrir. Nunca queda en BODY. */
  function devolverFoco(i) {
    let destino = null;
    if (i >= 0) {
      const fs = document.querySelectorAll("#panel-tabla .t-fila");
      for (const f of fs) if (f._idx === i) { destino = f; break; }
    }
    if (!destino && origenFoco && origenFoco.isConnected &&
        !raiz.contains(origenFoco) && origenFoco !== document.body)
      destino = origenFoco;
    if (!destino)
      destino = document.querySelector("#panel-tabla .t-scroll") ||
                document.getElementById("panel-tabla");
    if (!destino || typeof destino.focus !== "function") return;
    if (destino.tabIndex < 0 && !destino.hasAttribute("tabindex"))
      destino.setAttribute("tabindex", "-1");
    try { destino.focus({ preventScroll: true }); } catch (e) { destino.focus(); }
  }

  function avisar(boton, ok) {
    if (!boton.dataset.txt) boton.dataset.txt = boton.textContent;
    boton.textContent = ok ? "copiado" : "no se pudo copiar";
    boton.classList.toggle("fi-falla", !ok);
    clearTimeout(boton._t);
    boton._t = setTimeout(function () {
      boton.textContent = boton.dataset.txt;
      boton.classList.remove("fi-falla");
    }, 1400);
  }

  /* --- lista de campos: se construye una vez y solo se repuebla ----------- */
  function columnasPorBloque() {
    const vistos = {}, salida = [];
    for (const par of BLOQUES) {
      const ok = par[1].filter(function (c) {
        if (!V.colByName[c]) return false;
        vistos[c] = 1; return true;
      });
      if (ok.length) salida.push([par[0], ok]);
    }
    const resto = V.cols.map(function (c) { return c.n; })
                        .filter(function (n) { return !vistos[n]; });
    if (resto.length) salida.push(["Otras variables", resto]);
    return salida;
  }

  function construirCampos() {
    cuerpo.textContent = "";
    filas = {};
    const grupos = columnasPorBloque();
    for (const par of grupos) {
      const titulo = par[0], cols = par[1];
      const sec = el("section", "fi-bloque");
      const h = el("h3", "fi-h3");
      h.appendChild(el("span", null, titulo));
      const cnt = el("span", "fi-h3-n mono");
      h.appendChild(cnt);
      sec.appendChild(h);
      sec._cnt = cnt; sec._cols = cols;

      for (const col of cols) {
        const fila = el("div", "fi-fila");
        fila.dataset.col = col;
        fila.setAttribute("tabindex", "0");
        fila.setAttribute("role", "button");
        fila.title = "Ver procedencia y descripción de " + col;

        const nom = el("span", "fi-nom mono", col);
        const val = el("span", "fi-val");
        const met = el("span", "fi-met");
        fila.appendChild(nom); fila.appendChild(val); fila.appendChild(met);

        const det = el("div", "fi-det");
        det.hidden = true;

        const caja = el("div", "fi-caja");
        caja.appendChild(fila); caja.appendChild(det);
        sec.appendChild(caja);
        filas[col] = { caja: caja, fila: fila, val: val, met: met, det: det, hecho: false };
      }
      cuerpo.appendChild(sec);
    }
  }

  /* --- pintado de un tramo ------------------------------------------------ */
  /* opc.unidad === false  -> no imprime el sufijo de unidad (el rotulo ya la lleva)
     opc.aviso  === false  -> no imprime la marca de «0 = no informado»          */
  function texto(nodo, col, i, opc) {
    opc = opc || {};
    nodo.textContent = "";
    nodo.removeAttribute("title");
    if (V.esNulo(col, i)) {
      nodo.appendChild(el("span", "vacio fi-sindato", "sin dato"));
      nodo.classList.add("es-nulo");
      return;
    }
    nodo.classList.remove("es-nulo");
    nodo.appendChild(document.createTextNode(V.fmt(col, i)));

    const u = unidadDe(col);
    if (u && opc.unidad !== false) {
      nodo.appendChild(document.createTextNode(" "));
      const su = el("span", "fi-uni", u.u);
      if (u.nota) { su.title = u.nota; su.classList.add("fi-uni-nota"); }
      nodo.appendChild(su);
    }

    /* El valor exacto de la base queda a un hover de distancia: lo que se ve
       redondeado y lo que se exporta no pueden parecer cifras distintas. */
    const v = V.val(col, i);
    if (typeof v === "number") {
      let t = "valor exacto en la base: " + exacto(col, i) + (u ? " " + u.u : "");
      if (u && u.nota) t += "\n" + u.nota;
      nodo.title = t;
    } else if (u && u.nota) {
      nodo.title = u.nota;
    }

    const cero = ceroNoInformado(col, i);
    if (cero && opc.aviso !== false) {
      nodo.appendChild(document.createTextNode(" "));
      const sc = el("span", "fi-cero", cero.corto);
      sc.title = cero.largo;
      nodo.appendChild(sc);
    }
  }

  /* Regla 2 a la vista. Una celda vacia NO lleva insignia: un valor que no
     existe no tiene metodo, ni fuente, ni fecha, ni agente. */
  function insigniaMetodo(nodo, col, i) {
    if (V.esNulo(col, i)) {
      nodo.textContent = "";
      nodo.className = "fi-met " + VACIA.cls;
      nodo.removeAttribute("title");
      nodo.setAttribute("aria-hidden", "true");
      return;
    }
    nodo.removeAttribute("aria-hidden");
    const p = V.procDe(col, i);
    const m = (p && METODOS[p.metodo]) ? METODOS[p.metodo] : SIN_PROC;
    nodo.textContent = m.sig;
    nodo.className = "fi-met " + m.cls;
    nodo.title = p
      ? (m.tit + "\nfuente " + p.fuente + " · descargada " + p.fecha + " · agente " + p.agente)
      : SIN_PROC.tit;
  }

  function chip(rotulo, colNombre, i) {
    const c = el("span", "chip fi-chip");
    c.appendChild(el("b", null, rotulo));
    if (colNombre && V.colByName[colNombre]) {
      c.appendChild(document.createTextNode(" "));
      const t = V.fmt(colNombre, i);
      if (t) c.appendChild(document.createTextNode(t));
      else c.appendChild(el("span", "vacio fi-sindato", "sin nombre en la fuente"));
      c.title = colNombre;
    }
    return c;
  }

  function pintar(i) {
    actual = i;
    if (i < 0) return;

    /* encabezado */
    ui.id.textContent = V.fmt("id_tramo", i) || "(id vacío)";

    ui.rol.textContent = "";
    const rol = V.fmt("rol", i), nom = V.fmt("nombre_camino", i);
    if (rol) ui.rol.appendChild(el("span", "fi-rol-cod mono", rol));
    if (rol && nom) ui.rol.appendChild(el("span", "fi-sep", " · "));
    if (nom) ui.rol.appendChild(el("span", null, nom));
    if (!rol && !nom)
      ui.rol.appendChild(el("span", "vacio fi-sindato", "sin rol ni nombre en la fuente"));

    ui.ubic.textContent = "";
    ["comuna", "provincia", "region"].forEach(function (c, k) {
      if (k) ui.ubic.appendChild(el("span", "fi-sep", " · "));
      const t = V.colByName[c] ? V.fmt(c, i) : "";
      ui.ubic.appendChild(t ? el("span", null, t)
                            : el("span", "vacio fi-sindato", c + " sin dato"));
    });

    /* distintivos: solo si la base lo dice */
    ui.chips.textContent = "";
    if (V.val("es_paso", i) === true) ui.chips.appendChild(chip("Paso fronterizo", "paso_nombre", i));
    if (V.val("es_esqui", i) === true) ui.chips.appendChild(chip("Centro invernal", "esqui_nombre", i));
    if (V.val("cruza_portezuelo", i) === true) ui.chips.appendChild(chip("Cruza portezuelo", null, i));
    if (V.val("en_zona_fronteriza", i) === true) ui.chips.appendChild(chip("Zona fronteriza", null, i));
    if (V.val("es_localidad", i) === true) ui.chips.appendChild(chip("Localidad", "localidad_nombre", i));
    ui.chips.hidden = !ui.chips.childNodes.length;

    /* cifras destacadas: la unidad va en el rotulo para que la cifra grande no
       se lea sin ella (km_tramo son METROS pese al nombre, docs/esquema.md) */
    ui.cifras.textContent = "";
    for (const par of CIFRAS) {
      const col = par[0];
      if (!V.colByName[col]) continue;
      const u = unidadDe(col);
      const t = el("div", "fi-cifra");
      const v = el("div", "fi-cifra-v mono");
      texto(v, col, i, { unidad: false, aviso: false });
      const r = el("div", "fi-cifra-r");
      r.appendChild(el("span", "fi-cifra-rot",
        par[1] + (u ? " (" + u.u + ")" : "")));
      const m = el("span", "fi-met");
      insigniaMetodo(m, col, i);
      r.appendChild(m);
      t.appendChild(v); t.appendChild(r);

      /* Un 0 que la fuente declara como «no informado» no puede presentarse
         como longitud (Regla 1: la base manda, pero el lector debe verlo). */
      const cero = ceroNoInformado(col, i);
      if (cero) {
        t.classList.add("fi-cifra-cero");
        const av = el("div", "fi-cifra-aviso",
          cero === SUBDIVIDIDO ? "longitud del tramo sin partir" : "0 = la fuente no lo informó");
        av.title = cero.largo;
        t.appendChild(av);
      }
      t.title = col + (u && u.nota ? " — " + u.nota : "");
      ui.cifras.appendChild(t);
    }

    /* las filas de variables */
    for (const col in filas) {
      const f = filas[col];
      texto(f.val, col, i);
      insigniaMetodo(f.met, col, i);
      f.caja.classList.toggle("nulo", V.esNulo(col, i));
      f.det.hidden = true;
      f.det.textContent = "";
      f.caja.classList.remove("abierta");
      f.hecho = false;
    }

    dibujar(i);
    aplicarOcultar();
    actualizarNav();

    ui.notaMeta.textContent = (V.meta && V.meta.nota) ? V.meta.nota : "";
    ui.pieProc.textContent =
      "Procedencia por campo según docs/fuentes.md y data/processed/procedencia.parquet. " +
      "Atributos: " + (V.meta ? V.meta.parquet : "") +
      " · geometría: " + (V.meta ? V.meta.gpkg : "") + ".";
  }

  /* --- detalle desplegable (Regla 2 a la vista) --------------------------- */
  function alternarDetalle(fila) {
    const col = fila.dataset.col, f = filas[col];
    if (!f) return;
    if (!f.hecho) { armarDetalle(col, f); f.hecho = true; }
    const abrir = f.det.hidden;
    f.det.hidden = !abrir;
    f.caja.classList.toggle("abierta", abrir);
  }

  function armarDetalle(col, f) {
    const i = actual;
    f.det.textContent = "";
    const p = i >= 0 ? V.procDe(col, i) : null;

    const g = el("div", "fi-proc");
    /* Tres casos distintos, y no se pueden confundir:
       1. celda vacia            -> no hay valor, luego no hay procedencia
       2. valor sin procedencia  -> el valor existe y falta la declaracion
       3. valor con procedencia  -> Regla 2 completa                          */
    if (i >= 0 && V.esNulo(col, i)) {
      g.classList.add("fi-proc-nd");
      g.appendChild(el("span", "vacio",
        "Celda vacía: NULL en la base. Un valor que no existe no tiene " +
        "procedencia — procedencia.parquet registra una fila sólo por cada " +
        "valor presente —, así que este campo no lleva método, ni fuente, ni " +
        "fecha de descarga, ni agente. El motivo por el que no se pudo derivar " +
        "queda en data/pendientes.csv."));
    } else if (p) {
      const pares = [["fuente", p.fuente], ["fecha de descarga", p.fecha],
                     ["método", p.metodo], ["agente", p.agente]];
      for (const par of pares) {
        g.appendChild(el("span", "fi-pk", par[0]));
        const b = el("span", "fi-pv mono");
        if (par[1] == null || par[1] === "")
          b.appendChild(el("span", "vacio fi-sindato", "sin dato"));
        else b.textContent = String(par[1]);
        if (par[0] === "método" && METODOS[par[1]]) b.classList.add(METODOS[par[1]].cls + "-txt");
        g.appendChild(b);
      }
    } else {
      g.classList.add("fi-proc-nd");
      g.appendChild(el("span", "vacio",
        "Sin procedencia declarada para este campo en procedencia.parquet. " +
        "El valor mostrado sigue siendo el de la base; lo que falta es la " +
        "declaración de origen."));
    }
    f.det.appendChild(g);

    const d = V.desc ? V.desc[col] : null;
    if (d) {
      const dl = el("dl", "fi-desc");
      const pares = [["Qué es", d.que_es], ["De dónde sale", d.de_donde],
                     ["Cómo leerlo", d.como_leerlo]];
      for (const par of pares) {
        if (!par[1]) continue;
        dl.appendChild(el("dt", null, par[0]));
        dl.appendChild(el("dd", null, par[1]));
      }
      if (dl.childNodes.length) f.det.appendChild(dl);
    } else {
      f.det.appendChild(el("p", "fi-nota vacio",
        "Sin descripción en docs/descripciones_columnas.csv."));
    }
  }

  /* --- mostrar / ocultar campos sin dato ---------------------------------- */
  function aplicarOcultar() {
    if (!cuerpo) return;
    let nulos = 0, total = 0;
    const secs = cuerpo.querySelectorAll(".fi-bloque");
    for (const sec of secs) {
      let conDato = 0;
      for (const col of sec._cols) {
        const f = filas[col];
        const esN = actual >= 0 && V.esNulo(col, actual);
        if (esN) nulos++; else conDato++;
        total++;
        f.caja.hidden = ocultarNulos && esN;
      }
      sec._cnt.textContent = actual < 0 ? "" : conDato + "/" + sec._cols.length;
      sec._cnt.title = actual < 0 ? "" :
        conDato + " variables con dato de " + sec._cols.length + " en el bloque";
      sec.hidden = ocultarNulos && conDato === 0;
    }
    ui.conteoNulos.textContent = actual < 0 ? "" : (total - nulos) + "/" + total + " con dato";
    ui.conteoNulos.title = actual < 0 ? "" :
      nulos + " de " + total + " variables están en NULL para este tramo";
  }

  /* --- croquis de la geometria del tramo ---------------------------------- */
  function preparar(cv, alto) {
    const ancho = Math.max(120, Math.round(cv.clientWidth || 380));
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    cv.width = Math.round(ancho * dpr);
    cv.height = Math.round(alto * dpr);
    const ctx = cv.getContext("2d");
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, ancho, alto);
    return { ctx: ctx, w: ancho, h: alto };
  }

  function dibujarGeom(i) {
    const g = V.geom, cv = ui.cvGeo, alto = 120;
    cv.style.height = alto + "px";
    const c = preparar(cv, alto), ctx = c.ctx, w = c.w, h = c.h;
    const bg = css("--f-mapa-bg") || "#eee";
    ctx.fillStyle = bg; ctx.fillRect(0, 0, w, h);
    ctx.strokeStyle = css("--f-borde") || "#ddd"; ctx.lineWidth = 1;
    ctx.strokeRect(0.5, 0.5, w - 1, h - 1);
    if (!g || i < 0 || i >= g.nTramo) { ui.notaGeo.textContent = ""; return; }

    const x0 = g.bboxT[i * 4], y0 = g.bboxT[i * 4 + 1],
          x1 = g.bboxT[i * 4 + 2], y1 = g.bboxT[i * 4 + 3];
    /* correccion de aspecto: un grado de longitud mide menos que uno de latitud */
    const latMed = ((y0 + y1) / 2) / g.escala;
    const kx = Math.max(0.05, Math.cos(latMed * Math.PI / 180));
    const pad = 10;
    const bw = (x1 - x0) * kx, bh = (y1 - y0);
    let s;
    if (bw <= 0 && bh <= 0) s = 1;
    else s = Math.min(bw > 0 ? (w - 2 * pad) / bw : Infinity,
                      bh > 0 ? (h - 2 * pad) / bh : Infinity);
    if (!isFinite(s) || s <= 0) s = 1;
    const offx = (w - bw * s) / 2, offy = (h - bh * s) / 2;
    const px = function (x) { return (x - x0) * kx * s + offx; };
    const py = function (y) { return h - ((y - y0) * s + offy); };

    ctx.lineJoin = "round"; ctx.lineCap = "round";
    ctx.strokeStyle = css("--f-sel") || "#1f6feb";
    ctx.lineWidth = 2;
    let vertices = 0, ini = null, fin = null;
    for (let p = g.tramoP0[i]; p < g.tramoP0[i + 1]; p++) {
      const a = g.parteOff[p], b = g.parteOff[p + 1];
      if (b - a < 1) continue;
      ctx.beginPath();
      for (let k = a; k < b; k++) {
        const X = px(g.xy[k * 2]), Y = py(g.xy[k * 2 + 1]);
        if (k === a) ctx.moveTo(X, Y); else ctx.lineTo(X, Y);
        if (ini === null) ini = [X, Y];
        fin = [X, Y];
        vertices++;
      }
      if (b - a === 1) ctx.lineTo(px(g.xy[a * 2]) + 0.01, py(g.xy[a * 2 + 1]));
      ctx.stroke();
    }
    if (ini) {
      ctx.lineWidth = 1.5;
      ctx.strokeStyle = css("--f-txt-2") || "#555";
      ctx.fillStyle = bg;
      ctx.beginPath(); ctx.arc(ini[0], ini[1], 3.5, 0, 6.2832); ctx.fill(); ctx.stroke();
    }
    if (fin) {
      ctx.fillStyle = css("--f-acento") || "#8a5a2b";
      ctx.beginPath(); ctx.arc(fin[0], fin[1], 3.5, 0, 6.2832); ctx.fill();
    }
    const partes = g.tramoP0[i + 1] - g.tramoP0[i];
    ui.notaGeo.textContent =
      "Sólo la geometría de este tramo, sin mapa base ni escala. " +
      vertices.toLocaleString("es-CL") + " vértices en " + partes +
      (partes === 1 ? " parte" : " partes") + ", simplificada a " + g.tol_m +
      " m. Círculo hueco: primer vértice; círculo lleno: último.";
  }

  /* --- esquema de tres cotas (no es un perfil) ---------------------------- */
  function dibujarPerfil(i) {
    const cv = ui.cvPerfil, alto = 58;
    cv.style.height = alto + "px";
    const c = preparar(cv, alto), ctx = c.ctx, w = c.w, h = c.h;
    ui.perfilLabs.textContent = "";

    const defs = [["cota_min", "mín"], ["cota_media", "media"], ["cota_max", "máx"]];
    const vals = defs.map(function (d) {
      return V.colByName[d[0]] ? V.val(d[0], i) : null;
    });
    const hay = vals.filter(function (v) { return typeof v === "number"; });

    ctx.strokeStyle = css("--f-borde") || "#ddd";
    ctx.lineWidth = 1;
    ctx.beginPath(); ctx.moveTo(0, h - 0.5); ctx.lineTo(w, h - 0.5); ctx.stroke();

    if (hay.length) {
      let lo = Math.min.apply(null, hay), hi = Math.max.apply(null, hay);
      if (hi === lo) { hi = lo + 1; lo = lo - 1; }
      const pad = 12;
      const xs = [w * 0.16, w * 0.5, w * 0.84];
      const ys = vals.map(function (v) {
        return typeof v === "number"
          ? h - pad - (v - lo) / (hi - lo) * (h - 2 * pad) : null;
      });

      ctx.strokeStyle = css("--f-txt-3") || "#999";
      ctx.setLineDash([3, 3]); ctx.lineWidth = 1.5;
      ctx.beginPath();
      let mov = false;
      for (let k = 0; k < 3; k++) {
        if (ys[k] === null) { mov = false; continue; }
        if (!mov) { ctx.moveTo(xs[k], ys[k]); mov = true; } else ctx.lineTo(xs[k], ys[k]);
      }
      ctx.stroke(); ctx.setLineDash([]);

      ctx.fillStyle = css("--f-acento") || "#8a5a2b";
      for (let k = 0; k < 3; k++) {
        if (ys[k] === null) continue;
        ctx.beginPath(); ctx.arc(xs[k], ys[k], 3.5, 0, 6.2832); ctx.fill();
      }
    }

    for (const d of defs) {
      const caja = el("div", "fi-plab");
      caja.appendChild(el("span", "fi-plab-r", d[1]));
      const v = el("span", "fi-plab-v mono");
      if (V.colByName[d[0]]) texto(v, d[0], i, { unidad: false });
      else v.appendChild(el("span", "vacio fi-sindato", "sin dato"));
      caja.appendChild(v);
      caja.title = d[0] + " — metros sobre el nivel del mar";
      ui.perfilLabs.appendChild(caja);
    }
  }

  function dibujar(i) { dibujarGeom(i); dibujarPerfil(i); }

  /* --- navegacion dentro de V.filtrados ----------------------------------- */
  function posEnFiltro() {
    const f = V.filtrados;
    if (!f || actual < 0) return -1;
    for (let k = 0; k < f.length; k++) if (f[k] === actual) return k;
    return -1;
  }

  function actualizarNav() {
    const f = V.filtrados, n = f ? f.length : 0;
    const k = posEnFiltro();
    if (actual < 0) { ui.pos.textContent = ""; ui.pos.title = ""; }
    else if (k < 0) {
      ui.pos.textContent = "fuera del filtro";
      ui.pos.title = "Este tramo no está entre los " + n.toLocaleString("es-CL") +
                     " que pasan el filtro actual.";
    } else {
      ui.pos.textContent = (k + 1).toLocaleString("es-CL") + " / " +
                           n.toLocaleString("es-CL");
      ui.pos.title = "Posición dentro de los tramos filtrados";
    }
    const vacio = n === 0 || actual < 0;
    ui.ant.disabled = vacio || k === 0;
    ui.sig.disabled = vacio || (k >= 0 && k === n - 1);
  }

  function mover(d) {
    const f = V.filtrados;
    if (!f || !f.length) return;
    let k = posEnFiltro();
    if (k < 0) k = d > 0 ? -1 : f.length;      /* fuera del filtro: entra por el borde */
    const j = k + d;
    if (j < 0 || j >= f.length) return;
    seleccionar(f[j]);
  }

  /* Emite 'seleccion' DESPUES de fijar V.sel. Nunca se llama desde el
     manejador de 'seleccion' (regla anti-bucle). */
  function seleccionar(i) {
    V.sel = i;
    V.emit("seleccion", i);
  }

  /* --- ficha completa como texto ------------------------------------------ */
  /* Lo que se copia tiene que ser lo mismo que dice el parquet: el valor va
     completo, sin el redondeo de presentacion, para que la ficha copiada y el
     CSV de la tabla no entreguen altitudes distintas del mismo tramo. */
  function fichaComoTexto(i) {
    const L = [];
    L.push("Catastro de caminos de montaña — ficha de tramo");
    L.push("id_tramo: " + (V.fmt("id_tramo", i) || "(vacío)"));
    L.push("generado: " + (V.meta ? V.meta.generado : "") +
           " · atributos: " + (V.meta ? V.meta.parquet : ""));
    L.push("NULL = el valor no se pudo derivar de data/raw/. No es un cero.");
    L.push("Una celda NULL no lleva procedencia: procedencia.parquet registra " +
           "una fila sólo por cada valor presente, de modo que un campo vacío " +
           "no tiene método, ni fuente, ni fecha, ni agente.");
    L.push("Los valores van con la precisión del parquet, sin el redondeo de " +
           "la pantalla. Unidades según docs/esquema.md y " +
           "docs/descripciones_columnas.csv.");
    L.push("columna\tvalor\tunidad\t[método | fuente | fecha de descarga | agente]");
    L.push("");
    for (const par of columnasPorBloque()) {
      L.push("## " + par[0]);
      for (const col of par[1]) {
        const u = unidadDe(col);
        const uni = u ? u.u : "";
        if (V.esNulo(col, i)) { L.push("  " + col + "\tNULL\t" + uni); continue; }
        const p = V.procDe(col, i);
        const proc = p ? (p.metodo + " | " + p.fuente + " | " + p.fecha + " | " + p.agente)
                       : "sin procedencia declarada";
        const cero = ceroNoInformado(col, i);
        L.push("  " + col + "\t" + exacto(col, i) + "\t" + uni + "\t[" + proc + "]" +
               (cero ? "\t← 0 = la fuente no lo informó" : ""));
      }
      L.push("");
    }
    const vistos = new Set();
    for (const col of Object.keys(CERO_NO_INFORMADO).concat(["km_tramo"]))
      if (V.colByName[col]) {
        const a = ceroNoInformado(col, i);
        if (a && !vistos.has(a.largo)) { vistos.add(a.largo); L.push(a.largo); }
      }
    if (V.meta && V.meta.nota) L.push(V.meta.nota);
    return L.join("\n");
  }

  /* --- ciclo de vida ------------------------------------------------------ */
  window.Ficha = {
    init: function (el0) {
      montar(el0);

      V.on("seleccion", function (i) {
        const j = (typeof i === "number") ? i : V.sel;
        const estaba = raiz.classList.contains("abierto");

        if (j == null || j < 0 || j >= V.n) {
          const cerrado = abiertoEn;
          raiz.classList.remove("abierto");
          raiz.setAttribute("aria-hidden", "true");
          aplicarModal();
          actual = -1;
          abiertoEn = -1;
          aplicarOcultar();
          actualizarNav();
          /* Escape o clic en × no pueden dejar el foco en BODY. */
          if (estaba) { devolverFoco(cerrado); origenFoco = null; }
          return;
        }

        if (!estaba) {
          const a = document.activeElement;
          origenFoco = (a && a !== document.body && !raiz.contains(a)) ? a : null;
        }
        /* La clase va ANTES de pintar: con display:none el panel mide 0x0 y el
           croquis y el esquema de cotas saldrian dibujados sobre un lienzo del
           ancho de reserva, no del ancho real. */
        raiz.classList.add("abierto");
        raiz.removeAttribute("aria-hidden");
        aplicarModal();
        pintar(j);
        abiertoEn = j;
        raiz.scrollTop = 0;
        /* Cuando cubre todo el cuerpo se comporta como dialogo: el foco entra. */
        if (!estaba && mqCubre.matches) raiz.focus({ preventScroll: true });
      });

      V.on("filtro", function () { actualizarNav(); });
      V.on("tema", function () { if (actual >= 0) dibujar(actual); });

      raiz.setAttribute("aria-hidden", "true");
      actualizarNav();
    }
  };
})();
