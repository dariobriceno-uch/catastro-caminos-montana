"""Convierte docs/libro_codigos.md (generado por libro_codigos.R) en docs/libro_codigos.html.
Solo transforma formato; no agrega ni altera contenido."""
import re, html, os

root = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
src = os.path.join(root, "docs", "libro_codigos.md")
dst = os.path.join(root, "docs", "libro_codigos.html")
lines = open(src, encoding="utf-8").read().splitlines()

def inline(s):
    s = html.escape(s, quote=False)
    s = re.sub(r"`([^`]+)`", r"<code>\1</code>", s)
    s = re.sub(r"\*\*([^*]+)\*\*", r"<b>\1</b>", s)
    s = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", r'<a href="\2">\1</a>', s)
    return s

BLOQUES = {"A1": "Red Vial", "A2": "Segmentación", "A3": "Altimetría", "A4": "Destinos", "A5": "Tránsito", "ORQ/llave": "Llave / ORQ"}
intro, cards, i = [], [], 0
# encabezado hasta "## Índice"
while i < len(lines) and not lines[i].startswith("## Índice"):
    if lines[i].startswith("# "):
        pass
    elif lines[i].startswith("## "):
        intro.append(f"<h2 class='sec'>{inline(lines[i][3:])}</h2>")
    elif lines[i].startswith("- "):
        intro.append(f"<p class='gl'>{inline(lines[i][2:])}</p>")
    elif lines[i].strip():
        intro.append(f"<p>{inline(lines[i])}</p>")
    i += 1
# saltar índice
while i < len(lines) and not lines[i].startswith("## `"):
    i += 1

cur = None
def flush():
    if cur: cards.append(cur)
while i < len(lines):
    l = lines[i]
    if l.startswith("## `"):
        flush()
        col = l[4:-1]
        cur = {"col": col, "bloque": "", "items": [], "table": []}
    elif l.startswith("- **Bloque:**"):
        m = re.search(r"\*\*Bloque:\*\* ([^·]+)", l)
        cur["bloque"] = m.group(1).strip() if m else ""
        cur["items"].append(inline(l[2:]))
    elif l.startswith("- "):
        cur["items"].append(inline(l[2:]))
    elif l.startswith("| ") and not l.startswith("|---"):
        cells = [c.strip() for c in l.strip("|").split("|")]
        cur["table"].append(cells)
    i += 1
flush()

def card(c):
    slug = re.sub(r"[^a-z0-9]+", "-", c["col"].lower())
    b = c["bloque"]; bl = BLOQUES.get(b, b)
    items = "".join(f"<li>{it}</li>" for it in c["items"])
    tbl = ""
    if c["table"]:
        hdr, rows = c["table"][0], c["table"][1:]
        tbl = ('<div class="tablewrap"><table><tr>' + "".join(f"<th{' class=n' if j else ''}>{html.escape(h)}</th>" for j, h in enumerate(hdr)) + "</tr>"
               + "".join("<tr>" + "".join(f"<td{' class=n' if j else ''}>{inline(v)}</td>" for j, v in enumerate(r)) + "</tr>" for r in rows) + "</table></div>")
    return (f'<section class="card" id="{slug}" data-col="{html.escape(c["col"])}" data-bloque="{html.escape(b)}">'
            f'<h2><code>{html.escape(c["col"])}</code><span class="pill">{html.escape(bl)}</span></h2><ul>{items}</ul>{tbl}</section>')

nav = "".join(f'<a href="#{re.sub(r"[^a-z0-9]+", "-", c["col"].lower())}" data-col="{html.escape(c["col"])}"><code>{html.escape(c["col"])}</code><span>{html.escape(c["bloque"])}</span></a>' for c in cards)

page = f"""<title>Libro de Códigos del Catastro</title>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Source+Serif+4:opsz,wght@8..60,500;8..60,600&family=IBM+Plex+Sans:wght@400;500;600&family=IBM+Plex+Mono:wght@400;500&display=swap">
<style>
:root{{--bg:#F3F4F1;--surface:#FFFFFF;--ink:#1C232B;--ink-2:#4A545E;--ink-3:#7A848D;--rule:#D3D8D4;--accent:#3B5B7E;--accent-soft:#E3EAF2;
--mono:"IBM Plex Mono",ui-monospace,Consolas,monospace;--sans:"IBM Plex Sans",system-ui,Segoe UI,Arial,sans-serif;--serif:"Source Serif 4",Georgia,serif}}
@media (prefers-color-scheme:dark){{:root:not([data-theme="light"]){{--bg:#151A20;--surface:#1D242C;--ink:#E6E9EB;--ink-2:#B4BCC4;--ink-3:#7F8993;--rule:#323B45;--accent:#8FB0D6;--accent-soft:#25344A}}}}
:root[data-theme="dark"]{{--bg:#151A20;--surface:#1D242C;--ink:#E6E9EB;--ink-2:#B4BCC4;--ink-3:#7F8993;--rule:#323B45;--accent:#8FB0D6;--accent-soft:#25344A}}
*{{box-sizing:border-box}} body{{margin:0;background:var(--bg);color:var(--ink);font-family:var(--sans);font-size:15px;line-height:1.5}}
.wrap{{display:grid;grid-template-columns:260px minmax(0,1fr);gap:2rem;max-width:1180px;margin:0 auto;padding:2.5rem 1.5rem 5rem}}
@media (max-width:820px){{.wrap{{grid-template-columns:1fr}} nav{{position:static;max-height:none}}}}
nav{{position:sticky;top:1rem;align-self:start;max-height:calc(100vh - 2rem);overflow:auto;border-right:1px solid var(--rule);padding-right:1rem}}
nav input{{width:100%;font:inherit;font-family:var(--mono);font-size:.8rem;padding:.45rem .6rem;border:1px solid var(--rule);border-radius:4px;background:var(--surface);color:var(--ink);margin-bottom:.6rem}}
nav input:focus{{outline:2px solid var(--accent);outline-offset:1px}}
nav a{{display:flex;justify-content:space-between;gap:.5rem;text-decoration:none;color:var(--ink-2);padding:.22rem .3rem;border-radius:3px;font-size:.82rem}}
nav a:hover,nav a:focus{{background:var(--accent-soft);color:var(--ink);outline:none}} nav a span{{font-family:var(--mono);font-size:.68rem;color:var(--ink-3)}}
nav a.hide,.card.hide{{display:none}}
.eyebrow{{font-family:var(--mono);font-size:.72rem;letter-spacing:.08em;text-transform:uppercase;color:var(--accent);margin:0 0 .5rem}}
h1{{font-family:var(--serif);font-weight:600;font-size:2.1rem;line-height:1.1;margin:0 0 .8rem;text-wrap:balance}}
.intro p{{color:var(--ink-2);margin:0 0 .6rem;max-width:70ch}}
.intro h2.sec{{font-family:var(--serif);font-weight:600;font-size:1.35rem;margin:1.6rem 0 .6rem;color:var(--ink)}}
.intro p.gl{{color:var(--ink);padding-left:1rem;border-left:2px solid var(--rule);margin:0 0 .5rem}}
.card li b{{color:var(--ink)}} .card li:nth-child(-n+3){{color:var(--ink)}} .card li:nth-child(n+4){{color:var(--ink-2);font-size:.92em}}
.card{{background:var(--surface);border:1px solid var(--rule);border-radius:4px;padding:1rem 1.2rem;margin:1rem 0}}
.card h2{{font-family:var(--mono);font-weight:500;font-size:1.05rem;margin:0 0 .5rem;display:flex;align-items:center;gap:.7rem;flex-wrap:wrap}}
.card h2 code{{background:none;padding:0;font-size:1em}}
.pill{{font-family:var(--sans);font-size:.7rem;letter-spacing:.05em;text-transform:uppercase;background:var(--accent-soft);color:var(--accent);padding:.1rem .5rem;border-radius:3px}}
.card ul{{margin:0;padding-left:1.1rem}} .card li{{margin:.15rem 0}}
code{{font-family:var(--mono);font-size:.86em;background:var(--accent-soft);padding:.05em .3em;border-radius:3px}}
.tablewrap{{overflow-x:auto;margin:.6rem 0 0}} table{{border-collapse:collapse;font-size:.86rem;min-width:280px}}
th,td{{text-align:left;padding:.3rem .6rem;border-bottom:1px solid var(--rule)}} th{{font-size:.7rem;letter-spacing:.06em;text-transform:uppercase;color:var(--ink-3);font-weight:500}}
td.n,th.n{{text-align:right;font-family:var(--mono);font-variant-numeric:tabular-nums}}
.count{{font-family:var(--mono);font-size:.75rem;color:var(--ink-3);margin:.2rem 0 .6rem}}
a{{color:var(--accent)}}
</style>
<div class="wrap">
<nav><input id="q" type="search" placeholder="filtrar columna o bloque…" aria-label="Filtrar columnas"><div class="count" id="count"></div>{nav}</nav>
<main>
<p class="eyebrow">FONDEF IDeA · Catastro de caminos de montaña · Fase 1</p>
<h1>Libro de códigos</h1>
<div class="intro">{"".join(intro)}</div>
{"".join(card(c) for c in cards)}
</main></div>
<script>
(function(){{
  var q=document.getElementById('q'),links=document.querySelectorAll('nav a'),cards=document.querySelectorAll('.card'),cnt=document.getElementById('count');
  function apply(){{var v=q.value.trim().toLowerCase(),n=0;
    cards.forEach(function(c){{var ok=!v||c.dataset.col.toLowerCase().indexOf(v)>=0||c.dataset.bloque.toLowerCase().indexOf(v)>=0;c.classList.toggle('hide',!ok);if(ok)n++;}});
    links.forEach(function(a){{var ok=!v||a.dataset.col.toLowerCase().indexOf(v)>=0||a.querySelector('span').textContent.toLowerCase().indexOf(v)>=0;a.classList.toggle('hide',!ok);}});
    cnt.textContent=n+' de '+cards.length+' columnas';}}
  q.addEventListener('input',apply);apply();
}})();
</script>
"""
open(dst, "w", encoding="utf-8").write(page)
print("escrito", dst, len(cards), "fichas")
