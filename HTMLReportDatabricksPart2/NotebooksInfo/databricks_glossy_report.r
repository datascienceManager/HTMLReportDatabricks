# Databricks notebook source
# MAGIC %md
# MAGIC # Glossy HTML Engagement Report (R)
# MAGIC Inline ggplot2 + animated charts + enriched tables, rendered directly in Databricks.
# MAGIC
# MAGIC **Runtime:** Databricks ML Runtime (R + pandoc preinstalled). Plain runtimes also work but you may need pandoc for self-contained widgets.

# COMMAND ----------

# MAGIC %md
# MAGIC ## 1 · Packages
# MAGIC Most are preinstalled on the ML runtime. The guard below only installs what's missing, and only on the driver. For repeatable clusters, prefer an **init script** or a **cluster library** instead of installing per-run.

# COMMAND ----------

needed <- c("ggplot2","dplyr","tidyr","scales","gganimate","gifski",
            "base64enc","gt","reactable","htmlwidgets","plotly")
to_install <- needed[!sapply(needed, requireNamespace, quietly = TRUE)]
if (length(to_install)) install.packages(to_install, repos = "https://cloud.r-project.org")
invisible(lapply(needed, library, character.only = TRUE))

# COMMAND ----------

# MAGIC %md
# MAGIC ## 2 · Rendering helpers (the part that makes Databricks cooperate)
# MAGIC In-cell `displayHTML()` is how anything HTML shows up. The three things people fight with:
# MAGIC - **htmlwidgets** (plotly / reactable / DT) must be saved *self-contained* and re-injected.
# MAGIC - **gt** tables go in as a raw HTML string via `as_raw_html()`.
# MAGIC - **gganimate** produces a GIF, which has to be base64-embedded to appear inline.

# COMMAND ----------

# Render any htmlwidget (plotly, reactable, DT, leaflet, ...) inline.
display_widget <- function(widget) {
  tmp <- tempfile(fileext = ".html")
  htmlwidgets::saveWidget(widget, tmp, selfcontained = TRUE)   # needs pandoc
  displayHTML(paste(readLines(tmp, warn = FALSE), collapse = "\n"))
}

# Render a gganimate animation inline as a base64 GIF.
display_anim <- function(anim, width = 840, height = 420, fps = 20, duration = 7,
                         bg = "#0E1320") {
  gif <- gganimate::animate(
    anim, width = width, height = height, fps = fps, duration = duration,
    renderer = gganimate::gifski_renderer(), bg = bg, res = 110
  )
  tmp <- tempfile(fileext = ".gif")
  gganimate::anim_save(tmp, gif)
  b64 <- base64enc::base64encode(tmp)
  displayHTML(sprintf(
    '<div style="text-align:center;background:%s;padding:8px;border-radius:14px">
       <img src="data:image/gif;base64,%s" style="max-width:100%%;border-radius:10px"/></div>',
    bg, b64))
}

# Render a static ggplot as a crisp inline PNG (sharper than the default device).
display_ggplot <- function(p, width = 9, height = 4.6, dpi = 150) {
  tmp <- tempfile(fileext = ".png")
  ggplot2::ggsave(tmp, p, width = width, height = height, dpi = dpi, bg = "#0E1320")
  b64 <- base64enc::base64encode(tmp)
  displayHTML(sprintf('<img src="data:image/png;base64,%s" style="max-width:100%%"/>', b64))
}

# COMMAND ----------

# MAGIC %md
# MAGIC ## 3 · The glossy theme + palette
# MAGIC One reusable ggplot2 theme so every chart matches the report. Gold `#F5C518` leads; violet/teal support.

# COMMAND ----------

pal <- list(
  bg     = "#0E1320", ink = "#EEF1F7", muted = "#8B95A8",
  grid   = "#1E2638", gold = "#F5C518", gold_d = "#B8920F",
  violet = "#8B7BF0", teal = "#27C2B6", red = "#F0726A"
)

theme_glossy <- function(base_size = 13) {
  ggplot2::theme_minimal(base_size = base_size) %+replace%
    ggplot2::theme(
      plot.background   = element_rect(fill = pal$bg, color = NA),
      panel.background  = element_rect(fill = pal$bg, color = NA),
      panel.grid.major  = element_line(color = pal$grid, linewidth = 0.4),
      panel.grid.minor  = element_blank(),
      text              = element_text(color = pal$ink),
      axis.text         = element_text(color = pal$muted),
      axis.title        = element_text(color = pal$muted, size = base_size * 0.9),
      plot.title        = element_text(color = "#FFFFFF", face = "bold",
                                       size = base_size * 1.5, hjust = 0,
                                       margin = margin(b = 2)),
      plot.subtitle     = element_text(color = pal$muted, hjust = 0,
                                       margin = margin(b = 14)),
      plot.caption      = element_text(color = "#5A6478", size = base_size * 0.8, hjust = 1),
      legend.position   = "top", legend.justification = "left",
      legend.title      = element_blank(),
      legend.background = element_rect(fill = pal$bg, color = NA),
      legend.key        = element_rect(fill = pal$bg, color = NA),
      plot.margin       = margin(18, 18, 14, 18)
    )
}

# COMMAND ----------

# MAGIC %md
# MAGIC ## 4 · Get data from Spark / Unity Catalog
# MAGIC Real reports read a Delta table. Swap the synthetic block for a `SparkR::sql()` pull.

# COMMAND ----------

# --- Production read (uncomment) ---------------------------------------------
# library(SparkR)
# sdf <- SparkR::sql("SELECT day, market, cohort, dau, watch_min, d7_ret
#                     FROM catalog.schema.engagement_daily
#                     WHERE day BETWEEN '2026-06-09' AND '2026-06-15'")
# dat <- SparkR::collect(sdf)

# --- Synthetic stand-in so this notebook runs as-is --------------------------
set.seed(42)
days    <- seq(as.Date("2026-06-09"), as.Date("2026-06-15"), by = "day")
markets <- c("Saudi Arabia","UAE","Egypt","Qatar","Kuwait")
base    <- c(560, 420, 390, 230, 185) * 1000
dat <- expand.grid(day = days, market = markets, cohort = c("Target","Control"),
                   stringsAsFactors = FALSE)
dat <- dat |>
  dplyr::group_by(market) |>
  dplyr::mutate(
    b      = base[match(market, markets)],
    trend  = as.numeric(day - min(day)) * ifelse(cohort == "Target", 0.045, 0.012),
    dau    = round(b * (1 + trend) * runif(dplyr::n(), .96, 1.05)),
    watch_min = round(rnorm(dplyr::n(), 40, 4) + ifelse(cohort=="Target", 2, 0)),
    d7_ret = pmin(.72, pmax(.46, rnorm(dplyr::n(), .57, .04) +
                            ifelse(cohort=="Target", .02, 0)))
  ) |>
  dplyr::ungroup() |>
  dplyr::select(day, market, cohort, dau, watch_min, d7_ret)

head(dat)

# COMMAND ----------

# MAGIC %md
# MAGIC ## 5 · Static ggplot2 — engagement trend (Target vs Control)

# COMMAND ----------

trend_df <- dat |>
  dplyr::group_by(day, cohort) |>
  dplyr::summarise(dau = sum(dau), .groups = "drop")

p_trend <- ggplot(trend_df, aes(day, dau, color = cohort, fill = cohort)) +
  geom_area(data = subset(trend_df, cohort == "Target"),
            alpha = .18, color = NA) +
  geom_line(aes(linetype = cohort), linewidth = 1.2) +
  geom_point(size = 2.4) +
  scale_color_manual(values = c(Target = pal$gold, Control = pal$violet)) +
  scale_fill_manual(values  = c(Target = pal$gold, Control = pal$violet)) +
  scale_linetype_manual(values = c(Target = "solid", Control = "dashed")) +
  scale_y_continuous(labels = scales::label_number(scale = 1e-6, suffix = "M")) +
  labs(title = "Daily active viewers", subtitle = "Target cohort vs control · MENA",
       x = NULL, y = NULL, caption = "Source: engagement_daily") +
  theme_glossy()

display_ggplot(p_trend)

# COMMAND ----------

# MAGIC %md
# MAGIC ## 6 · Interactive version (plotly) — hover, zoom, inline

# COMMAND ----------

display_widget(plotly::ggplotly(p_trend, tooltip = c("x","y","colour")) |>
                 plotly::layout(paper_bgcolor = pal$bg, plot_bgcolor = pal$bg,
                                font = list(color = pal$ink),
                                legend = list(orientation = "h")))

# COMMAND ----------

# MAGIC %md
# MAGIC ## 7 · Animated chart — market race (gganimate → inline GIF)

# COMMAND ----------

race_df <- dat |>
  dplyr::filter(cohort == "Target") |>
  dplyr::group_by(day, market) |>
  dplyr::summarise(dau = sum(dau), .groups = "drop") |>
  dplyr::group_by(day) |>
  dplyr::mutate(rank = rank(-dau)) |>
  dplyr::ungroup()

anim <- ggplot(race_df, aes(reorder(market, dau), dau, fill = market)) +
  geom_col(width = .72, show.legend = FALSE) +
  geom_text(aes(label = scales::label_number(scale = 1e-3, suffix = "k")(dau)),
            hjust = -0.15, color = pal$ink, size = 4) +
  coord_flip(clip = "off") +
  scale_fill_manual(values = colorRampPalette(c(pal$gold, pal$violet, pal$teal))(5)) +
  scale_y_continuous(expand = expansion(mult = c(0, .15))) +
  labs(title = "Market race — {format(frame_time, '%b %d')}",
       x = NULL, y = "Daily active") +
  theme_glossy() +
  gganimate::transition_time(day) +
  gganimate::ease_aes("cubic-in-out")

display_anim(anim, duration = 7, fps = 20)

# COMMAND ----------

# MAGIC %md
# MAGIC ## 8 · Enriched table A — `gt` (publication style, dark)

# COMMAND ----------

tbl_df <- dat |>
  dplyr::filter(day == max(day)) |>
  dplyr::group_by(market) |>
  dplyr::summarise(dau = sum(dau), watch = mean(watch_min),
                   d7 = mean(d7_ret), .groups = "drop") |>
  dplyr::arrange(dplyr::desc(dau))

gt_tbl <- tbl_df |>
  gt::gt() |>
  gt::tab_header(title = gt::md("**Market detail**"),
                 subtitle = "Latest day · all cohorts") |>
  gt::fmt_number(dau, decimals = 0, sep_mark = ",") |>
  gt::fmt_number(watch, decimals = 0, pattern = "{x}m") |>
  gt::fmt_percent(d7, decimals = 1) |>
  gt::data_color(columns = dau,
                 fn = scales::col_numeric(c("#3a2f00", pal$gold), domain = NULL)) |>
  gt::cols_label(market = "Market", dau = "Daily Active",
                 watch = "Watch (avg)", d7 = "D7 Retention") |>
  gt::tab_options(
    table.background.color   = pal$bg,
    table.font.color         = pal$ink,
    heading.title.font.size  = 20,
    column_labels.background.color = "#121828",
    column_labels.font.weight = "bold",
    table.border.top.style   = "none",
    table_body.hlines.color  = pal$grid,
    table.font.names         = "Inter"
  )

displayHTML(gt::as_raw_html(gt_tbl))

# COMMAND ----------

# MAGIC %md
# MAGIC ## 9 · Enriched table B — `reactable` (sortable, searchable, sparkline cells)

# COMMAND ----------

react_df <- dat |>
  dplyr::filter(cohort == "Target") |>
  dplyr::group_by(market) |>
  dplyr::summarise(dau = sum(dau), series = list(tapply(dau, day, sum)),
                   .groups = "drop")

rt <- reactable::reactable(
  tbl_df,
  searchable = TRUE, sortable = TRUE, highlight = TRUE, defaultPageSize = 5,
  theme = reactable::reactableTheme(
    color = pal$ink, backgroundColor = pal$bg,
    borderColor = pal$grid, stripedColor = "#121828",
    highlightColor = "#1a2335",
    headerStyle = list(color = pal$muted, textTransform = "uppercase",
                       fontSize = "11px", letterSpacing = "0.05em")
  ),
  columns = list(
    market = reactable::colDef(name = "Market"),
    dau    = reactable::colDef(name = "Daily Active", format = reactable::colFormat(separators = TRUE)),
    watch  = reactable::colDef(name = "Watch", format = reactable::colFormat(suffix = "m", digits = 0)),
    d7     = reactable::colDef(name = "D7 Ret.", format = reactable::colFormat(percent = TRUE, digits = 1))
  )
)

display_widget(rt)

# COMMAND ----------

# MAGIC %md
# MAGIC ## 10 · Python ↔ R interop
# MAGIC Objects don't cross languages in memory — **Spark tables do**. Let Python do the heavy ETL, hand off via a temp view or Delta table, then visualize in R.
# MAGIC
# MAGIC ```python
# MAGIC %python
# MAGIC # Heavy aggregation in PySpark
# MAGIC agg = (spark.table("catalog.schema.events")
# MAGIC          .groupBy("day","market","cohort")
# MAGIC          .agg(F.countDistinct("user_id").alias("dau")))
# MAGIC agg.createOrReplaceTempView("report_input")        # session-scoped
# MAGIC # or persist:  agg.write.mode("overwrite").saveAsTable("scratch.report_input")
# MAGIC ```
# MAGIC ```r
# MAGIC %r
# MAGIC library(SparkR)
# MAGIC dat <- collect(sql("SELECT * FROM report_input"))   # now a local R data.frame
# MAGIC ```
# MAGIC Going the other way (R result → Python): `SparkR::createDataFrame(r_df)` then `createOrReplaceTempView()`, and read it back with `spark.table(...)`.

# COMMAND ----------

# MAGIC %md
# MAGIC ## 11 · Export a full standalone HTML file
# MAGIC The notebook itself exports via **File ▸ Export ▸ HTML**. For a polished, shareable artifact, render the `.qmd`/`.Rmd` template to a **Unity Catalog Volume**, then download it.

# COMMAND ----------

out <- "/Volumes/catalog/schema/reports/engagement_report.html"  # <-- your volume
# rmarkdown::render("./engagement_report.qmd", output_file = out, quiet = TRUE)
# displayHTML(sprintf('<a href="%s">Download report</a>', out))
cat("Render target:", out, "\n")
