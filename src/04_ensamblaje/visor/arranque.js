/* VISOR DE TRAMOS — arranque: carga el payload y monta los tres modulos. */
(function () {
  "use strict";
  const $ = s => document.querySelector(s);

  function tema() {
    const b = $("#btn-tema");
    const guardado = (() => { try { return localStorage.getItem("visor-tema"); } catch (e) { return null; } })();
    if (guardado) document.documentElement.setAttribute("data-tema", guardado);
    b.addEventListener("click", () => {
      const act = document.documentElement.getAttribute("data-tema");
      const oscuro = act ? act === "oscuro"
        : matchMedia("(prefers-color-scheme: dark)").matches;
      const nuevo = oscuro ? "claro" : "oscuro";
      document.documentElement.setAttribute("data-tema", nuevo);
      try { localStorage.setItem("visor-tema", nuevo); } catch (e) {}
      V.emit("tema", nuevo);
    });
  }

  window.addEventListener("DOMContentLoaded", async () => {
    try {
      await V.cargar(document.getElementById("payload").textContent.trim());

      $("#cab-sub").textContent =
        V.n.toLocaleString("es-CL") + " tramos · " + V.cols.length + " variables · " +
        V.geom.nVert.toLocaleString("es-CL") + " vértices (simplificado a " +
        V.geom.tol_m + " m) · generado " + V.meta.generado.replace("T", " ");

      tema();
      window.Tabla.init($("#panel-tabla"));
      window.Mapa.init($("#panel-mapa"));
      window.Ficha.init($("#panel-ficha"));

      $("#carga").classList.add("oculto");
      $("#app").hidden = false;
      V.emit("listo");
    } catch (e) {
      console.error(e);
      $("#carga-err").textContent = "No se pudo abrir el catastro: " + e.message;
    }
  });
})();
