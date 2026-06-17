# Databricks notebook source
# MAGIC %md
# MAGIC # Self-contained HTML report, built in R (Databricks)
# MAGIC Same architecture as the TOD report: **R computes everything → JSON islands → vanilla JS/SVG renders**.
# MAGIC No charting library ships to the browser, so the output is one portable `.html` with zero runtime deps.
# MAGIC
# MAGIC Pipeline: wrangle (dplyr) → serialize (`jsonlite`) → inject into template (placeholder swap) → `displayHTML` + write to a Volume.

# COMMAND ----------

# Only jsonlite + dplyr are needed for this demo (both preinstalled on the ML runtime).
# For a real network graph add: install.packages(c("igraph"))   # layout + community detection
# For Gini via a package add:   install.packages(c("ineq"))     # (we compute it by hand below)
library(dplyr); library(jsonlite)

# COMMAND ----------

# MAGIC %md
# MAGIC ## 1 · Data — Spark/Unity Catalog or synthetic
# MAGIC Swap the synthetic block for your real `SparkR::collect()` pull.

# COMMAND ----------

# --- Production read (uncomment) ---
# library(SparkR)
# titles <- collect(sql("SELECT title AS n, is_series AS s, viewers AS v, completion AS c
#                        FROM catalog.schema.title_engagement"))

# --- Synthetic stand-in (heavy-tailed viewers, like real streaming demand) ---
set.seed(7)
N <- 120
titles <- data.frame(
  n = sprintf("Title %03d", 1:N),
  s = rbinom(N, 1, 0.35),                          # 1 = series, 0 = movie
  v = round(rlnorm(N, meanlog = 5.2, sdlog = 1.1)) # viewers, long tail
) |>
  mutate(c = round(pmin(95, pmax(30,
            rnorm(N, mean = ifelse(s == 1, 74, 53), sd = 7))), 1))  # completion %
head(titles)

# COMMAND ----------

# MAGIC %md
# MAGIC ## 2 · Compute the "blocks" (one per visual)

# COMMAND ----------

# (a) hero facts -- scalars
facts <- list(
  viewers = sum(titles$v),
  titles  = nrow(titles),
  serGrip = round(mean(titles$c[titles$s == 1]), 1),
  movGrip = round(mean(titles$c[titles$s == 0]), 1)
)

# (b) board -- top 15 titles by viewers
board <- titles |>
  arrange(desc(v)) |>
  slice_head(n = 15) |>
  transmute(n, v, c, s)

# (c) Lorenz curve + Gini -- demand concentration (pure base R, no package)
vs   <- sort(titles$v); n <- length(vs)
gini <- round((2 * sum(seq_len(n) * vs)) / (n * sum(vs)) - (n + 1) / n, 3)
lorenz <- data.frame(
  p = round(100 * c(0, seq_len(n) / n), 2),
  L = round(100 * c(0, cumsum(vs) / sum(vs)), 2)
)

# COMMAND ----------

# MAGIC %md
# MAGIC ## 3 · Serialize each block to JSON
# MAGIC `dataframe="rows"` → array of objects; `auto_unbox=TRUE` → scalars stay scalars.

# COMMAND ----------

j_facts  <- toJSON(facts,  auto_unbox = TRUE)
j_board  <- toJSON(board,  dataframe = "rows", auto_unbox = TRUE)
j_lorenz <- toJSON(lorenz, dataframe = "rows", auto_unbox = TRUE)
j_meta   <- toJSON(list(gini = gini), auto_unbox = TRUE)

# COMMAND ----------

# MAGIC %md
# MAGIC ## 4 · The HTML template
# MAGIC `r"---( ... )---"` is an R raw string, so the inner quotes/braces need no escaping.
# MAGIC The `__D1__`…`__D4__` tokens are where the JSON gets injected. The trailing `<script>`
# MAGIC reads those islands and hand-draws the visuals as SVG + styled divs.

# COMMAND ----------

template <- r"---(<!DOCTYPE html>
<html lang="en"><head><meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Completion Intelligence</title>
<style>
:root{--bg:#070A12;--panel:#0E1320;--panel2:#121828;--line:#1E2638;--ink:#EEF1F7;
  --muted:#8B95A8;--faint:#5A6478;--gold:#F5C518;--gold_d:#B8920F;--violet:#8B7BF0;--teal:#27C2B6;--grid:#19202F}
*{box-sizing:border-box;margin:0;padding:0}
body{background:radial-gradient(1100px 560px at 82% -10%,rgba(245,197,24,.10),transparent 60%),var(--bg);
  color:var(--ink);font-family:Inter,system-ui,-apple-system,"Segoe UI",Roboto,sans-serif}
.wrap{max-width:1040px;margin:0 auto;padding:46px 26px 80px}
.eyebrow{font-size:12px;letter-spacing:.22em;text-transform:uppercase;color:var(--gold);font-weight:600;margin-bottom:12px}
h1{font-size:clamp(28px,5vw,46px);font-weight:800;letter-spacing:-.02em;line-height:1.05;
  background:linear-gradient(180deg,#fff,#C8CEDC);-webkit-background-clip:text;background-clip:text;color:transparent}
.lede{color:var(--muted);max-width:60ch;margin-top:10px}
.kpis{display:grid;grid-template-columns:repeat(4,1fr);gap:14px;margin:34px 0}
.kpi{background:linear-gradient(160deg,var(--panel2),var(--panel));border:1px solid var(--line);border-radius:14px;padding:18px}
.kpi .lab{font-size:11px;text-transform:uppercase;letter-spacing:.05em;color:var(--muted)}
.kpi .val{font-size:26px;font-weight:800;margin-top:6px;font-variant-numeric:tabular-nums}
section{margin:40px 0}
.sec-head{display:flex;align-items:baseline;gap:12px;margin-bottom:16px}
.sec-num{font-size:13px;color:var(--gold_d);font-weight:700}
h2{font-size:20px;font-weight:700;letter-spacing:-.01em}
.sub{margin-left:auto;color:var(--faint);font-size:13px}
.card{background:linear-gradient(180deg,var(--panel2),var(--panel));border:1px solid var(--line);border-radius:16px;padding:22px}
.row{display:grid;grid-template-columns:90px 1fr 70px;align-items:center;gap:12px;margin-bottom:9px}
.row .name{font-size:13px;color:var(--ink);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.track{height:24px;background:var(--grid);border-radius:7px;overflow:hidden}
.fill{height:100%;border-radius:7px}
.fill.ser{background:linear-gradient(90deg,#5b50b8,var(--violet))}
.fill.mov{background:linear-gradient(90deg,var(--gold_d),var(--gold))}
.row .num{font-size:13px;color:var(--muted);text-align:right;font-variant-numeric:tabular-nums}
.legend{display:flex;gap:18px;font-size:12px;color:var(--muted);margin-top:14px}
.dot{display:inline-block;width:9px;height:9px;border-radius:50%;margin-right:6px;vertical-align:middle}
.ax{fill:var(--faint);font-size:11px}
.foot{margin-top:54px;padding-top:20px;border-top:1px solid var(--line);color:var(--faint);font-size:12px}
@media(max-width:720px){.kpis{grid-template-columns:repeat(2,1fr)}}
</style></head>
<body><div class="wrap">

  <p class="eyebrow">Content Intelligence</p>
  <h1>Completion &amp; Demand Report</h1>
  <p class="lede">Built entirely in R on Databricks — data computed server-side, results inlined as JSON, drawn in the browser with plain SVG.</p>

  <div class="kpis" id="kpis"></div>

  <section>
    <div class="sec-head"><span class="sec-num">01</span><h2>Top titles by reach</h2><span class="sub">computed in R · dplyr</span></div>
    <div class="card"><div id="board"></div>
      <div class="legend"><span><span class="dot" style="background:var(--gold)"></span>Movie</span>
      <span><span class="dot" style="background:var(--violet)"></span>Series</span></div></div>
  </section>

  <section>
    <div class="sec-head"><span class="sec-num">02</span><h2>Demand concentration</h2><span class="sub">Lorenz curve · Gini</span></div>
    <div class="card"><div id="lz"></div></div>
  </section>

  <div class="foot">Generated in Azure Databricks · R · jsonlite · self-contained HTML</div>

  <!-- ===== JSON islands: filled by R ===== -->
  <script id="d1" type="application/json">__D1__</script>
  <script id="d2" type="application/json">__D2__</script>
  <script id="d3" type="application/json">__D3__</script>
  <script id="d4" type="application/json">__D4__</script>

  <!-- ===== renderers: vanilla JS draws from the islands ===== -->
  <script>
  const J = id => JSON.parse(document.getElementById(id).textContent);
  const FACTS = J('d1'), BOARD = J('d2'), LZ = J('d3'), META = J('d4');
  const nf = n => n.toLocaleString();

  // KPI cards
  document.getElementById('kpis').innerHTML = [
    ['Viewers', nf(FACTS.viewers)], ['Titles', FACTS.titles],
    ['Series completion', FACTS.serGrip + '%'], ['Movie completion', FACTS.movGrip + '%']
  ].map(([l,v]) => `<div class="kpi"><div class="lab">${l}</div><div class="val">${v}</div></div>`).join('');

  // Ranked bars
  const maxV = Math.max(...BOARD.map(d => d.v));
  document.getElementById('board').innerHTML = BOARD.map(d => {
    const w = Math.max(6, d.v / maxV * 100), cls = d.s ? 'ser' : 'mov';
    return `<div class="row"><span class="name">${d.n}</span>
      <div class="track"><div class="fill ${cls}" style="width:${w}%"></div></div>
      <span class="num">${nf(d.v)}</span></div>`;
  }).join('');

  // Lorenz curve (SVG, hand-drawn from the points R computed)
  (function(){
    const W=720,H=320,P=46;
    const x = p => P + p/100*(W-2*P);
    const y = L => (H-P) - L/100*(H-2*P);
    const pts  = LZ.map(d => `${x(d.p).toFixed(1)},${y(d.L).toFixed(1)}`).join(' ');
    const area = `${x(0).toFixed(1)},${y(0).toFixed(1)} ${pts} ${x(100).toFixed(1)},${y(0).toFixed(1)}`;
    document.getElementById('lz').innerHTML = `
      <svg viewBox="0 0 ${W} ${H}" width="100%">
        <defs><linearGradient id="lzf" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0" stop-color="#F5C518" stop-opacity=".30"/>
          <stop offset="1" stop-color="#F5C518" stop-opacity="0"/></linearGradient></defs>
        <polygon points="${area}" fill="url(#lzf)"/>
        <line x1="${x(0)}" y1="${y(0)}" x2="${x(100)}" y2="${y(100)}" stroke="#5A6478" stroke-dasharray="5 5"/>
        <polyline points="${pts}" fill="none" stroke="#F5C518" stroke-width="2.5"/>
        <text class="ax" x="${x(50)}" y="${H-12}" text-anchor="middle">share of titles →</text>
        <text class="ax" x="${x(2)}" y="${y(96)}">Gini ${META.gini}</text>
      </svg>`;
  })();
  </script>
</div></body></html>)---"

# COMMAND ----------

# MAGIC %md
# MAGIC ## 5 · Inject the JSON (placeholder swap — robust against CSS/JS braces)

# COMMAND ----------

html <- template
html <- sub("__D1__", j_facts,  html, fixed = TRUE)
html <- sub("__D2__", j_board,  html, fixed = TRUE)
html <- sub("__D3__", j_lorenz, html, fixed = TRUE)
html <- sub("__D4__", j_meta,   html, fixed = TRUE)

# COMMAND ----------

# MAGIC %md
# MAGIC ## 6 · Preview inline, then write the single file to a Volume

# COMMAND ----------

displayHTML(html)          # renders right here in the notebook

# COMMAND ----------

out <- "/Volumes/catalog/schema/reports/completion_report.html"   # <-- your Volume
writeLines(html, out)
cat("Wrote", nchar(html), "chars to", out, "\n")
# Then download from the Volume, email it, or serve it — no dependencies travel with it.
