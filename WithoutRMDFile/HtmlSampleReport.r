# Databricks notebook source
# MAGIC %md
# MAGIC # 📊 HTML Report Generator — Databricks R Notebook
# MAGIC This notebook installs packages, builds a full HTML report with tables,
# MAGIC charts, interactive widgets, and saves it to DBFS as a self-contained HTML file.
# MAGIC
# MAGIC Every function is written as `package::function()` so you always know
# MAGIC which library each call comes from.

# COMMAND ----------
# MAGIC %md
# MAGIC ## ⚙️ STEP 1 — Configuration
# MAGIC Set your output path and report title here before running anything else.

# COMMAND ----------

# ============================================================
# CONFIGURATION — Edit these values only
# ============================================================
REPORT_TITLE   <- "Monthly Sales Performance Report"
REPORT_AUTHOR  <- "Data Analytics Team"
OUTPUT_DIR     <- "/dbfs/FileStore/reports/"   # Must start with /dbfs/
OUTPUT_FILE    <- "sales_report.html"          # Output filename
SELF_CONTAINED <- TRUE                         # TRUE = single portable file

# Derived full path  [base R]
OUTPUT_PATH <- base::paste0(OUTPUT_DIR, OUTPUT_FILE)

base::cat("==============================================\n")
base::cat("  Report Title :", REPORT_TITLE, "\n")
base::cat("  Output Path  :", OUTPUT_PATH,  "\n")
base::cat("  Self-Contained:", SELF_CONTAINED, "\n")
base::cat("==============================================\n")

# COMMAND ----------
# MAGIC %md
# MAGIC ## 📦 STEP 2 — Install & Load Packages

# COMMAND ----------

# ---- Install missing packages (run once, then comment out) ----
required_packages <- base::c(
  "rmarkdown",    # HTML rendering engine
  "knitr",        # Code chunk processor
  "kableExtra",   # Styled static tables
  "DT",           # Interactive DataTables
  "ggplot2",      # Static charts (Grammar of Graphics)
  "plotly",       # Interactive charts
  "dplyr",        # Data manipulation (filter, mutate, group_by …)
  "leaflet",      # Interactive maps
  "htmltools",    # Build HTML programmatically (tags$, HTML(), tagList())
  "htmlwidgets",  # Framework powering all interactive widgets
  "scales",       # Number/axis formatting (label_dollar, comma …)
  "RColorBrewer"  # Color palettes (brewer.pal)
)

new_packages <- required_packages[
  !required_packages %in% utils::installed.packages()[, "Package"]
]

if (base::length(new_packages) > 0) {
  base::cat("Installing:", base::paste(new_packages, collapse = ", "), "\n")
  utils::install.packages(new_packages, quiet = TRUE)
} else {
  base::cat("✅ All packages already installed.\n")
}

# ---- Load libraries ----------------------------------------
base::suppressPackageStartupMessages({
  base::library(rmarkdown)    # rmarkdown::render()
  base::library(knitr)        # knitr::kable(), knitr::opts_chunk$set()
  base::library(kableExtra)   # kableExtra::kable_styling(), row_spec(), column_spec()
  base::library(DT)           # DT::datatable(), formatCurrency(), formatStyle()
  base::library(ggplot2)      # ggplot2::ggplot(), geom_col(), theme_minimal() …
  base::library(plotly)       # plotly::ggplotly(), plot_ly(), add_trace(), layout()
  base::library(dplyr)        # dplyr::mutate(), select(), filter(), group_by() …
  base::library(leaflet)      # leaflet::leaflet(), addTiles(), addCircleMarkers()
  base::library(htmltools)    # htmltools::HTML(), tags$, tagList(), save_html()
  base::library(htmlwidgets)  # htmlwidgets::saveWidget(), as_widget()
  base::library(scales)       # scales::label_dollar(), comma(), percent()
  base::library(RColorBrewer) # RColorBrewer::brewer.pal()
})

base::cat("✅ All libraries loaded.\n")

# COMMAND ----------
# MAGIC %md
# MAGIC ## 🗄️ STEP 3 — Prepare Data
# MAGIC Replace Option B with your real Spark / Delta table (Option A).

# COMMAND ----------

# ---- Option A: Real Spark table (uncomment to use) ---------
# base::library(SparkR)
# SparkR::sparkR.session()
# df_spark   <- SparkR::sql("SELECT * FROM your_db.your_table")
# sales_data <- SparkR::as.data.frame(df_spark)   # SparkR::as.data.frame

# ---- Option B: Sample data (default) -----------------------
base::set.seed(42)

sales_data <- base::data.frame(
  Month      = base::month.abb,                          # base::month.abb  — built-in month abbreviations
  Region     = base::rep(base::c("North","South","East","West"), length.out = 12),  # base::rep
  Sales      = base::round(stats::runif(12, 50000, 200000)),   # stats::runif  — uniform random numbers
  Target     = base::round(stats::runif(12, 80000, 180000)),
  Growth_Pct = base::round(stats::runif(12, -10, 30), 1),
  Customers  = base::sample(100:500, 12),                # base::sample
  stringsAsFactors = FALSE
)

# dplyr::mutate  — add / transform columns
# base::ifelse   — vectorised if/else
sales_data <- dplyr::mutate(
  sales_data,
  Variance    = Sales - Target,
  Achievement = base::round((Sales / Target) * 100, 1),
  Status      = base::ifelse(Sales >= Target, "Met", "Missed")
)

# Summary stats
total_sales <- base::sum(sales_data$Sales)                      # base::sum
avg_growth  <- base::round(base::mean(sales_data$Growth_Pct), 1) # base::mean
met_count   <- base::sum(sales_data$Status == "Met")
best_month  <- sales_data$Month[base::which.max(sales_data$Sales)] # base::which.max
best_sales  <- base::max(sales_data$Sales)                      # base::max

base::cat("✅ Data ready —", base::nrow(sales_data), "rows,",   # base::nrow / ncol
          base::ncol(sales_data), "columns.\n")
base::cat("   Total Sales :", base::formatC(total_sales,         # base::formatC
           format = "f", big.mark = ",", digits = 0), "\n")
base::cat("   Best Month  :", best_month, "\n")
base::cat("   Targets Met :", met_count, "/ 12\n")

# COMMAND ----------
# MAGIC %md
# MAGIC ## 🏗️ STEP 4 — Build HTML Components
# MAGIC Each component is a self-contained function. Package source is noted inline.

# COMMAND ----------

# ----------------------------------------------------------
# COMPONENT A: KPI Cards  — htmltools::HTML()
# ----------------------------------------------------------
build_kpi_cards <- function(total_sales, avg_growth, met_count, best_month) {

  # htmltools::HTML()  — mark a string as trusted HTML (no escaping)
  # base::formatC()    — format numbers with thousand separators
  # base::paste0()     — concatenate strings
  htmltools::HTML(base::paste0('
  <div style="display:flex; gap:16px; flex-wrap:wrap; margin:20px 0;">

    <div style="flex:1; min-width:160px; background:white; border-radius:10px;
                padding:20px; box-shadow:0 2px 10px rgba(0,0,0,0.08); text-align:center;
                border-top:4px solid #1a73e8;">
      <div style="font-size:1.9em; font-weight:bold; color:#1a73e8;">
        $', base::formatC(total_sales, format="f", big.mark=",", digits=0), '
      </div>
      <div style="font-size:0.8em; color:#888; margin-top:6px;">💰 Total Sales</div>
    </div>

    <div style="flex:1; min-width:160px; background:white; border-radius:10px;
                padding:20px; box-shadow:0 2px 10px rgba(0,0,0,0.08); text-align:center;
                border-top:4px solid #27ae60;">
      <div style="font-size:1.9em; font-weight:bold; color:#27ae60;">
        ', avg_growth, '%
      </div>
      <div style="font-size:0.8em; color:#888; margin-top:6px;">📈 Avg Growth</div>
    </div>

    <div style="flex:1; min-width:160px; background:white; border-radius:10px;
                padding:20px; box-shadow:0 2px 10px rgba(0,0,0,0.08); text-align:center;
                border-top:4px solid #f39c12;">
      <div style="font-size:1.9em; font-weight:bold; color:#f39c12;">
        ', met_count, ' / 12
      </div>
      <div style="font-size:0.8em; color:#888; margin-top:6px;">🎯 Targets Met</div>
    </div>

    <div style="flex:1; min-width:160px; background:white; border-radius:10px;
                padding:20px; box-shadow:0 2px 10px rgba(0,0,0,0.08); text-align:center;
                border-top:4px solid #9b59b6;">
      <div style="font-size:1.9em; font-weight:bold; color:#9b59b6;">
        ', best_month, '
      </div>
      <div style="font-size:0.8em; color:#888; margin-top:6px;">🏆 Best Month</div>
    </div>

  </div>
  '))
}

kpi_html <- build_kpi_cards(total_sales, avg_growth, met_count, best_month)
base::cat("✅ KPI cards built.\n")

# ----------------------------------------------------------
# COMPONENT B: kableExtra styled table
# ----------------------------------------------------------
build_kable_table <- function(df) {

  df |>
    # dplyr::select()        — pick columns by name
    dplyr::select(Month, Region, Sales, Target, Variance, Achievement, Status) |>

    # knitr::kable()         — convert data frame to HTML table
    knitr::kable(
      format      = "html",
      format.args = base::list(big.mark = ","),
      caption     = "📋 Monthly Sales Detail"
    ) |>

    # kableExtra::kable_styling() — Bootstrap table classes
    kableExtra::kable_styling(
      bootstrap_options = base::c("striped","hover","condensed","responsive"),
      full_width        = TRUE,
      font_size         = 13
    ) |>

    # kableExtra::row_spec()   — style a specific row (0 = header row)
    kableExtra::row_spec(0, bold = TRUE, background = "#2c3e50", color = "white") |>

    # kableExtra::column_spec() — style a specific column by position
    kableExtra::column_spec(7,
      bold       = TRUE,
      color      = "white",
      background = base::ifelse(df$Status == "Met", "#27ae60", "#e74c3c")
    ) |>
    kableExtra::column_spec(5,
      color = base::ifelse(df$Variance >= 0, "#27ae60", "#e74c3c"),
      bold  = TRUE
    )
}

kable_html <- build_kable_table(sales_data)
base::cat("✅ kableExtra table built.\n")

# ----------------------------------------------------------
# COMPONENT C: DT interactive table
# ----------------------------------------------------------
build_dt_table <- function(df) {

  # DT::datatable()  — create an interactive HTML table widget
  DT::datatable(
    df |> dplyr::select(Month, Region, Sales, Target, Achievement, Growth_Pct, Status),
    rownames   = FALSE,
    filter     = "top",          # column-level filter boxes
    extensions = "Buttons",      # export buttons extension
    caption    = "🔍 Interactive Table — Search, Filter, Export",
    options    = base::list(
      pageLength = 6,
      scrollX    = TRUE,
      dom        = "Bfrtip",     # B=Buttons f=search r=processing t=table i=info p=pages
      buttons    = base::list("copy","csv","excel","pdf","print"),
      columnDefs = base::list(base::list(className = "dt-center", targets = "_all"))
    )
  ) |>
    # DT::formatCurrency()   — format columns as currency
    DT::formatCurrency(base::c("Sales","Target"), currency = "$", digits = 0) |>

    # DT::formatStyle() + DT::styleColorBar() — data bar background
    DT::formatStyle(
      "Achievement",
      background         = DT::styleColorBar(base::c(0, 150), "#1a73e8"),
      backgroundSize     = "100% 80%",
      backgroundRepeat   = "no-repeat",
      backgroundPosition = "center"
    ) |>

    # DT::formatStyle() + DT::styleEqual() — conditional text colour
    DT::formatStyle(
      "Status",
      color      = DT::styleEqual(base::c("Met","Missed"), base::c("#27ae60","#e74c3c")),
      fontWeight = "bold"
    )
}

dt_widget <- build_dt_table(sales_data)
base::cat("✅ DT table built.\n")

# ----------------------------------------------------------
# COMPONENT D: ggplot2 bar chart converted to plotly
# ----------------------------------------------------------
build_bar_chart <- function(df) {

  # ggplot2::ggplot()       — initialise a plot with data + aesthetic mapping
  # ggplot2::aes()          — define x, y, fill, text aesthetics
  # base::reorder()         — reorder factor levels by another variable
  p <- ggplot2::ggplot(df, ggplot2::aes(
      x    = base::reorder(Month, -Sales),
      y    = Sales,
      fill = Region,
      text = base::paste0(
        "Month: ",  Month,
        "<br>Region: ", Region,
        "<br>Sales: $",  base::formatC(Sales,  format="f", big.mark=",", digits=0),
        "<br>Target: $", base::formatC(Target, format="f", big.mark=",", digits=0),
        "<br>Achievement: ", Achievement, "%"
      )
    )) +

    # ggplot2::geom_col()             — bar chart (identity stat)
    ggplot2::geom_col(width = 0.75, show.legend = TRUE) +

    # ggplot2::geom_hline()           — horizontal reference line
    ggplot2::geom_hline(
      yintercept = base::mean(df$Target),     # base::mean
      linetype = "dashed", color = "#e74c3c", linewidth = 0.9
    ) +

    # ggplot2::scale_y_continuous()   — customise y-axis
    # scales::label_dollar()          — format y-axis labels as $100K
    ggplot2::scale_y_continuous(
      labels = scales::label_dollar(scale = 1e-3, suffix = "K")
    ) +

    # ggplot2::scale_fill_brewer()    — use a ColorBrewer palette
    ggplot2::scale_fill_brewer(palette = "Set2") +

    # ggplot2::labs()                 — titles and axis labels
    ggplot2::labs(
      title    = "Sales by Month (sorted high to low)",
      subtitle = "Red dashed line = average target",
      x = "Month", y = "Sales", fill = "Region"
    ) +

    # ggplot2::theme_minimal()        — clean minimal theme
    ggplot2::theme_minimal(base_size = 12) +

    # ggplot2::theme()                — fine-tune theme elements
    # ggplot2::element_text()         — text appearance helper
    # ggplot2::element_blank()        — remove a theme element
    ggplot2::theme(
      plot.title         = ggplot2::element_text(face = "bold", color = "#2c3e50"),
      plot.subtitle      = ggplot2::element_text(color = "#7f8c8d", size = 10),
      panel.grid.major.x = ggplot2::element_blank(),
      legend.position    = "top"
    )

  # plotly::ggplotly()   — convert ggplot to interactive plotly widget
  # plotly::layout()     — customise plotly layout options
  plotly::ggplotly(p, tooltip = "text") |>
    plotly::layout(legend = base::list(orientation = "h", y = -0.15))
}

# ----------------------------------------------------------
# COMPONENT E: Native plotly line chart
# ----------------------------------------------------------
build_line_chart <- function(df) {

  # plotly::plot_ly()    — create a plotly chart from scratch
  plotly::plot_ly(df, x = ~Month) |>

    # plotly::add_trace() — add a data series (line + markers)
    plotly::add_trace(
      y      = ~Sales, name = "Actual Sales",
      type   = "scatter", mode = "lines+markers",
      line   = base::list(color = "#1a73e8", width = 2.5),
      marker = base::list(size = 8, color = "#1a73e8")
    ) |>
    plotly::add_trace(
      y      = ~Target, name = "Target",
      type   = "scatter", mode = "lines+markers",
      line   = base::list(color = "#e74c3c", width = 2, dash = "dash"),
      marker = base::list(size = 7, color = "#e74c3c", symbol = "triangle-up")
    ) |>

    # plotly::layout()   — set title, axes, hover mode, legend
    plotly::layout(
      title     = base::list(text = "Sales vs Target — Monthly Trend", x = 0),
      xaxis     = base::list(title = "Month"),
      yaxis     = base::list(title = "Amount ($)", tickformat = "$,.0f"),
      hovermode = "x unified",
      legend    = base::list(orientation = "h", y = -0.2)
    )
}

# ----------------------------------------------------------
# COMPONENT F: leaflet interactive map
# ----------------------------------------------------------
build_map <- function() {

  offices <- base::data.frame(
    name  = base::c("New York HQ","London","Dubai","Singapore","Sydney"),
    lat   = base::c(40.7128,  51.5074,  25.2048,   1.3521, -33.8688),
    lng   = base::c(-74.006,  -0.1278,  55.2708, 103.819,  151.209),
    staff = base::c(500, 320, 180, 210, 150),
    sales = base::c(800000, 650000, 420000, 390000, 310000)
  )

  # leaflet::leaflet()           — initialise the map widget
  leaflet::leaflet(offices) |>

    # leaflet::addProviderTiles() — add a basemap tile layer
    leaflet::addProviderTiles(leaflet::providers$CartoDB.Positron) |>

    # leaflet::addCircleMarkers() — plot circles sized by data
    leaflet::addCircleMarkers(
      lat         = ~lat,
      lng         = ~lng,
      radius      = ~base::sqrt(staff) * 1.8,   # base::sqrt — size by staff
      color       = "#1a73e8",
      fillColor   = "#1a73e8",
      fillOpacity = 0.6,
      weight      = 2,
      popup  = ~base::paste0(
        "<b>", name, "</b><br>",
        "👥 Staff: ", staff, "<br>",
        "💰 Sales: $", base::formatC(sales, format="f", big.mark=",", digits=0)
      ),
      label = ~name
    ) |>

    # leaflet::setView()  — set initial map centre and zoom level
    leaflet::setView(lng = 20, lat = 20, zoom = 2)
}

base::cat("✅ All chart component functions defined.\n")

# COMMAND ----------
# MAGIC %md
# MAGIC ## 📝 STEP 5 — Write the .Rmd File Dynamically

# COMMAND ----------

# base::dir.exists() / base::dir.create() — check / create directory
if (!base::dir.exists(OUTPUT_DIR)) {
  base::dir.create(OUTPUT_DIR, recursive = TRUE)
  base::cat("📁 Created output directory:", OUTPUT_DIR, "\n")
}

# base::tempfile()   — create a temporary file path with given extension
rmd_path <- base::tempfile(fileext = ".Rmd")

# base::sprintf()    — string interpolation (inserts REPORT_TITLE etc.)
rmd_content <- base::sprintf('---
title: "%s"
author: "%s"
date: "`r Sys.Date()`"
output:
  html_document:
    theme: flatly
    highlight: tango
    toc: true
    toc_float:
      collapsed: false
      smooth_scroll: true
    toc_depth: 3
    self_contained: %s
    code_folding: hide
---

```{r setup, include=FALSE}
# knitr::opts_chunk$set()  — set global chunk options for the whole Rmd
knitr::opts_chunk$set(echo=TRUE, warning=FALSE, message=FALSE,
                      fig.width=10, fig.height=5, fig.align="center")

# Load all libraries (Rmd runs in its own fresh environment)
library(knitr); library(kableExtra); library(DT)
library(ggplot2); library(plotly); library(dplyr)
library(leaflet); library(htmltools); library(htmlwidgets)
library(scales); library(RColorBrewer)

# Rebuild data (Rmd cannot access the notebook global environment)
base::set.seed(42)
sales_data <- base::data.frame(
  Month      = base::month.abb,
  Region     = base::rep(base::c("North","South","East","West"), length.out=12),
  Sales      = base::round(stats::runif(12, 50000, 200000)),
  Target     = base::round(stats::runif(12, 80000, 180000)),
  Growth_Pct = base::round(stats::runif(12, -10, 30), 1),
  Customers  = base::sample(100:500, 12),
  stringsAsFactors = FALSE
)
# dplyr::mutate()  — add computed columns
sales_data <- dplyr::mutate(sales_data,
  Variance    = Sales - Target,
  Achievement = base::round((Sales / Target) * 100, 1),
  Status      = base::ifelse(Sales >= Target, "Met", "Missed")
)
total_sales <- base::sum(sales_data$Sales)
avg_growth  <- base::round(base::mean(sales_data$Growth_Pct), 1)
met_count   <- base::sum(sales_data$Status == "Met")
best_month  <- sales_data$Month[base::which.max(sales_data$Sales)]
```

```{css, echo=FALSE}
body      { font-family:"Segoe UI",Arial,sans-serif; background:#f5f7fa; color:#2c3e50; }
h1.title  { color:#1a73e8; border-bottom:3px solid #1a73e8; padding-bottom:8px; }
h2        { border-left:5px solid #1a73e8; padding-left:10px; margin-top:30px; }
.info-box { background:#e8f4fd; border-left:5px solid #1a73e8;
            padding:12px 16px; border-radius:4px; margin:12px 0; }
```

---

# Executive Summary

```{r kpis, echo=FALSE}
# htmltools::HTML()   — inject raw HTML into the Rmd output
# base::paste0()      — concatenate strings without separator
# base::formatC()     — format number with thousand commas
htmltools::HTML(base::paste0(
\'<div style="display:flex;gap:16px;flex-wrap:wrap;margin:20px 0;">\',
\'<div style="flex:1;min-width:150px;background:white;border-radius:10px;padding:20px;
             box-shadow:0 2px 10px rgba(0,0,0,0.08);text-align:center;
             border-top:4px solid #1a73e8;">
  <div style="font-size:1.9em;font-weight:bold;color:#1a73e8;">$\',
  base::formatC(total_sales, format="f", big.mark=",", digits=0),
\'</div><div style="font-size:0.8em;color:#888;margin-top:6px;">💰 Total Sales</div></div>\',
\'<div style="flex:1;min-width:150px;background:white;border-radius:10px;padding:20px;
             box-shadow:0 2px 10px rgba(0,0,0,0.08);text-align:center;
             border-top:4px solid #27ae60;">
  <div style="font-size:1.9em;font-weight:bold;color:#27ae60;">\',
  avg_growth, \'%%</div>
  <div style="font-size:0.8em;color:#888;margin-top:6px;">📈 Avg Growth</div></div>\',
\'<div style="flex:1;min-width:150px;background:white;border-radius:10px;padding:20px;
             box-shadow:0 2px 10px rgba(0,0,0,0.08);text-align:center;
             border-top:4px solid #f39c12;">
  <div style="font-size:1.9em;font-weight:bold;color:#f39c12;">\',
  met_count, \' / 12</div>
  <div style="font-size:0.8em;color:#888;margin-top:6px;">🎯 Targets Met</div></div>\',
\'<div style="flex:1;min-width:150px;background:white;border-radius:10px;padding:20px;
             box-shadow:0 2px 10px rgba(0,0,0,0.08);text-align:center;
             border-top:4px solid #9b59b6;">
  <div style="font-size:1.9em;font-weight:bold;color:#9b59b6;">\',
  best_month,
\'</div><div style="font-size:0.8em;color:#888;margin-top:6px;">🏆 Best Month</div></div>\',
\'</div>\'
))
```

<div class="info-box">
📌 **Report Period:** `r format(Sys.Date(), "%%B %%Y")` &nbsp;|&nbsp;
**Generated:** `r Sys.time()` &nbsp;|&nbsp;
**Source:** Sales Database
</div>

---

# Styled Table (kableExtra) {.tabset}

## Sales Detail

```{r kable-table}
# dplyr::select()              — choose columns to display
# knitr::kable()               — render data frame as HTML table
# kableExtra::kable_styling()  — add Bootstrap CSS classes
# kableExtra::row_spec()       — style the header row (row 0)
# kableExtra::column_spec()    — conditional colour on a column
# kableExtra::add_header_above() — merge column headers
sales_data |>
  dplyr::select(Month, Region, Sales, Target, Variance, Achievement, Status) |>
  knitr::kable(format="html", format.args=base::list(big.mark=","),
               caption="📋 Monthly Sales vs Target") |>
  kableExtra::kable_styling(
    bootstrap_options = base::c("striped","hover","condensed","responsive"),
    full_width=TRUE, font_size=13) |>
  kableExtra::row_spec(0, bold=TRUE, background="#2c3e50", color="white") |>
  kableExtra::column_spec(7, bold=TRUE, color="white",
    background=base::ifelse(sales_data$Status=="Met","#27ae60","#e74c3c")) |>
  kableExtra::column_spec(5,
    color=base::ifelse(sales_data$Variance>=0,"#27ae60","#e74c3c"), bold=TRUE) |>
  kableExtra::add_header_above(base::c(" "=2, "Financials"=3, "Performance"=2))
```

## Regional Summary

```{r kable-regional}
# dplyr::group_by()   — group rows for aggregation
# dplyr::summarise()  — compute summary statistics per group
# base::sum()         — column total
# base::round() + base::mean() — average with rounding
# dplyr::arrange()    — sort rows
# dplyr::desc()       — descending sort helper
sales_data |>
  dplyr::group_by(Region) |>
  dplyr::summarise(
    Total_Sales      = base::sum(Sales),
    Total_Target     = base::sum(Target),
    Avg_Achievement  = base::round(base::mean(Achievement), 1),
    Months_Met       = base::sum(Status == "Met"),
    .groups = "drop"
  ) |>
  dplyr::arrange(dplyr::desc(Total_Sales)) |>
  knitr::kable(format="html", format.args=base::list(big.mark=","),
               caption="📊 Regional Performance Summary") |>
  kableExtra::kable_styling(bootstrap_options=base::c("striped","hover"),
                            full_width=FALSE) |>
  kableExtra::row_spec(0, bold=TRUE, background="#1a73e8", color="white") |>
  kableExtra::row_spec(1, bold=TRUE, background="#fef9e7")
```

---

# Interactive Table (DT)

```{r dt-table}
# DT::datatable()      — interactive searchable/sortable table
# DT::formatCurrency() — format numeric columns as $1,234
# DT::formatStyle()    — conditional cell styling
# DT::styleColorBar()  — data bar fill based on value
# DT::styleEqual()     — map values to colours
DT::datatable(
  sales_data |> dplyr::select(Month,Region,Sales,Target,Achievement,Growth_Pct,Status),
  rownames=FALSE, filter="top", extensions="Buttons",
  caption="🔍 Searchable, Filterable, Exportable Table",
  options=base::list(
    pageLength=6, scrollX=TRUE, dom="Bfrtip",
    buttons=base::list("copy","csv","excel","pdf","print"),
    columnDefs=base::list(base::list(className="dt-center", targets="_all"))
  )
) |>
  DT::formatCurrency(base::c("Sales","Target"), currency="$", digits=0) |>
  DT::formatStyle("Achievement",
    background         = DT::styleColorBar(base::c(0,150), "#1a73e8"),
    backgroundSize     = "100%% 80%%",
    backgroundRepeat   = "no-repeat",
    backgroundPosition = "center"
  ) |>
  DT::formatStyle("Status",
    color      = DT::styleEqual(base::c("Met","Missed"), base::c("#27ae60","#e74c3c")),
    fontWeight = "bold"
  )
```

---

# Charts {.tabset}

## Bar Chart (ggplot2 + plotly)

```{r bar-chart}
# ggplot2::ggplot()            — initialise plot
# ggplot2::aes()               — aesthetic mapping
# base::reorder()              — sort bars by Sales descending
# ggplot2::geom_col()          — bar geometry (pre-summarised data)
# ggplot2::geom_hline()        — horizontal reference line
# ggplot2::scale_y_continuous()— customise y axis
# scales::label_dollar()       — format axis labels as $100K
# ggplot2::scale_fill_brewer() — ColorBrewer fill palette
# ggplot2::labs()              — titles / axis labels
# ggplot2::theme_minimal()     — minimal theme
# ggplot2::theme()             — override individual theme elements
# ggplot2::element_text()      — text styling helper
# ggplot2::element_blank()     — remove element
# plotly::ggplotly()           — convert ggplot to interactive plotly
# plotly::layout()             — configure legend position
p <- ggplot2::ggplot(sales_data, ggplot2::aes(
    x    = base::reorder(Month, -Sales),
    y    = Sales,
    fill = Region,
    text = base::paste0("Month: ",Month,
                        "<br>Sales: $", base::formatC(Sales,format="f",big.mark=",",digits=0),
                        "<br>Achievement: ",Achievement,"%%"))) +
  ggplot2::geom_col(width=0.75) +
  ggplot2::geom_hline(yintercept=base::mean(sales_data$Target),
                      linetype="dashed", color="#e74c3c", linewidth=0.9) +
  ggplot2::scale_y_continuous(labels=scales::label_dollar(scale=1e-3,suffix="K")) +
  ggplot2::scale_fill_brewer(palette="Set2") +
  ggplot2::labs(title="Monthly Sales (sorted high to low)",
                subtitle="Dashed = average target",
                x="Month", y="Sales", fill="Region") +
  ggplot2::theme_minimal(base_size=12) +
  ggplot2::theme(
    plot.title         = ggplot2::element_text(face="bold"),
    panel.grid.major.x = ggplot2::element_blank(),
    legend.position    = "top"
  )
plotly::ggplotly(p, tooltip="text") |>
  plotly::layout(legend=base::list(orientation="h", y=-0.15))
```

## Trend Line (plotly)

```{r line-chart}
# plotly::plot_ly()    — create plotly chart
# plotly::add_trace()  — add data series (lines + markers)
# plotly::layout()     — axis labels, hover mode, legend
plotly::plot_ly(sales_data, x=~Month) |>
  plotly::add_trace(y=~Sales, name="Actual", type="scatter", mode="lines+markers",
    line=base::list(color="#1a73e8",width=2.5),
    marker=base::list(size=8,color="#1a73e8")) |>
  plotly::add_trace(y=~Target, name="Target", type="scatter", mode="lines+markers",
    line=base::list(color="#e74c3c",width=2,dash="dash"),
    marker=base::list(size=7,color="#e74c3c",symbol="triangle-up")) |>
  plotly::layout(
    title     = base::list(text="Sales vs Target Trend", x=0),
    xaxis     = base::list(title="Month"),
    yaxis     = base::list(title="Amount ($)", tickformat="$,.0f"),
    hovermode = "x unified",
    legend    = base::list(orientation="h", y=-0.2)
  )
```

## Scatter Plot

```{r scatter}
# ggplot2::geom_point()          — scatter geometry
# ggplot2::geom_smooth()         — regression line with confidence band
# ggplot2::scale_size_continuous() — map Achievement to point size
# ggplot2::scale_color_brewer()  — ColorBrewer colour palette
# ggplot2::theme_light()         — light panel background theme
p2 <- ggplot2::ggplot(sales_data, ggplot2::aes(
    x=Customers, y=Sales, color=Region, size=Achievement,
    text=base::paste0(Month,"<br>Customers: ",Customers,
                      "<br>Sales: $",base::formatC(Sales,format="f",big.mark=",",digits=0)))) +
  ggplot2::geom_point(alpha=0.8) +
  ggplot2::geom_smooth(method="lm", se=TRUE, color="#2c3e50",
                       fill="#bdc3c7", linewidth=0.7, linetype="dashed") +
  ggplot2::scale_y_continuous(labels=scales::label_dollar(scale=1e-3,suffix="K")) +
  ggplot2::scale_size_continuous(range=base::c(4,12)) +
  ggplot2::scale_color_brewer(palette="Dark2") +
  ggplot2::labs(title="Sales vs Customers", subtitle="Size = Achievement %%",
                x="Customers", y="Sales") +
  ggplot2::theme_light(base_size=12) +
  ggplot2::theme(plot.title=ggplot2::element_text(face="bold"))
plotly::ggplotly(p2, tooltip="text")
```

---

# Interactive Map (leaflet)

```{r map}
# leaflet::leaflet()           — initialise map widget with data frame
# leaflet::addProviderTiles()  — basemap tiles (CartoDB, OpenStreetMap …)
# leaflet::providers           — list of available tile providers
# leaflet::addCircleMarkers()  — plot circles; radius scaled to data
# base::sqrt()                 — used to scale radius by staff count
# base::paste0()               — build popup HTML string
# base::formatC()              — format sales with thousand commas
# leaflet::setView()           — set initial centre and zoom
offices <- base::data.frame(
  name  = base::c("New York HQ","London","Dubai","Singapore","Sydney"),
  lat   = base::c(40.7128, 51.5074, 25.2048,  1.3521, -33.8688),
  lng   = base::c(-74.006, -0.1278, 55.2708, 103.819,  151.209),
  staff = base::c(500, 320, 180, 210, 150),
  sales = base::c(800000,650000,420000,390000,310000)
)
leaflet::leaflet(offices) |>
  leaflet::addProviderTiles(leaflet::providers$CartoDB.Positron) |>
  leaflet::addCircleMarkers(
    lat=~lat, lng=~lng,
    radius=~base::sqrt(staff)*1.8,
    color="#1a73e8", fillColor="#1a73e8", fillOpacity=0.6, weight=2,
    popup=~base::paste0("<b>",name,"</b><br>",
                        "👥 Staff: ",staff,"<br>",
                        "💰 Sales: $",base::formatC(sales,format="f",big.mark=",",digits=0)),
    label=~name
  ) |>
  leaflet::setView(lng=20, lat=20, zoom=2)
```

---

# Appendix — Session Info

```{r session}
# base::sessionInfo()  — R version, platform, loaded packages
si <- base::sessionInfo()
base::cat("R version:", si$R.version$version.string, "\n")
base::cat("Platform :", si$platform, "\n")
base::cat("Packages  :", base::paste(base::names(si$otherPkgs), collapse=", "), "\n")
```

*Report generated: `r Sys.time()`*
',
  REPORT_TITLE,
  REPORT_AUTHOR,
  base::tolower(base::as.character(SELF_CONTAINED))
)

# base::gsub()       — fix pipe operators mangled by sprintf %% escaping
rmd_content <- base::gsub("%%>%%", "%>%", rmd_content, fixed = TRUE)
rmd_content <- base::gsub("%%%%",  "%%",  rmd_content, fixed = TRUE)

# base::writeLines() — write the .Rmd string to disk
base::writeLines(rmd_content, rmd_path)
base::cat("✅ .Rmd written to:", rmd_path, "\n")

# COMMAND ----------
# MAGIC %md
# MAGIC ## 🚀 STEP 6 — Render & Save HTML

# COMMAND ----------

base::cat("⏳ Rendering — this may take 30–60 seconds...\n\n")

# base::tryCatch()         — catch and handle errors gracefully
base::tryCatch({

  # rmarkdown::render()    — knit the .Rmd and produce HTML output
  # rmarkdown::html_document() — output format options object
  rmarkdown::render(
    input         = rmd_path,
    output_format = rmarkdown::html_document(
      self_contained = SELF_CONTAINED,
      theme          = "flatly",
      highlight      = "tango",
      toc            = TRUE,
      toc_float      = base::list(collapsed = FALSE, smooth_scroll = TRUE),
      toc_depth      = 3,
      code_folding   = "hide"
    ),
    output_file = OUTPUT_FILE,
    output_dir  = OUTPUT_DIR,
    quiet       = FALSE
  )

  # base::file.exists()    — confirm the file was created
  # base::file.info()      — get file metadata (size)
  if (base::file.exists(OUTPUT_PATH)) {
    size_kb <- base::round(base::file.info(OUTPUT_PATH)$size / 1024, 1)
    base::cat("\n============================================\n")
    base::cat("  ✅ SUCCESS — Report generated!\n")
    base::cat("  📂 Path :", OUTPUT_PATH, "\n")
    base::cat("  📦 Size :", size_kb, "KB\n")
    base::cat("  🕐 Time :", base::format(base::Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
    base::cat("============================================\n")
  } else {
    base::stop("File not found after render — check errors above.")
  }

}, error = function(e) {
  base::cat("\n❌ ERROR during render:\n")
  base::cat(base::conditionMessage(e), "\n")   # base::conditionMessage  — extract error text
  base::cat("\nTroubleshooting tips:\n")
  base::cat("  1. Check OUTPUT_DIR is writable\n")
  base::cat("  2. Re-run Step 2 to install packages\n")
  base::cat("  3. Check .Rmd content for syntax errors\n")
})

# COMMAND ----------
# MAGIC %md
# MAGIC ## 🌐 STEP 7 — Display & Share

# COMMAND ----------

base::cat("📺 Displaying report inline in notebook...\n")

# base::readLines()  — read HTML file into a character vector
# base::paste()      — collapse lines back to a single string
html_lines   <- base::readLines(OUTPUT_PATH, warn = FALSE)
html_content <- base::paste(html_lines, collapse = "\n")

# IRdisplay::display_html()     — render HTML inline in Databricks / Jupyter
# base::requireNamespace()      — check if a package is available without loading it
if (base::requireNamespace("IRdisplay", quietly = TRUE)) {
  IRdisplay::display_html(html_content)
} else {
  base::cat("IRdisplay not available — open the file path directly.\n")
}

# base::Sys.getenv()   — read environment variable (Databricks workspace URL)
# base::gsub()         — convert DBFS path to FileStore URL path
workspace_url <- base::Sys.getenv("DATABRICKS_HOST", unset = "https://<your-workspace>")
file_path_url <- base::gsub("/dbfs/FileStore/", "/files/", OUTPUT_PATH)
share_url     <- base::paste0(workspace_url, file_path_url)

base::cat("\n🌐 Share URL:\n  ", share_url, "\n")
base::cat("\n📋 Databricks CLI download:\n")
base::cat("  databricks fs cp dbfs:/FileStore/reports/", OUTPUT_FILE,
          " ./", OUTPUT_FILE, "\n", sep="")

# COMMAND ----------
# MAGIC %md
# MAGIC ## 🔄 STEP 8 — Schedule / Automate (Optional)
# MAGIC
# MAGIC 1. Go to **Workflows** → **Create Job**
# MAGIC 2. Set **Task type** = Notebook
# MAGIC 3. Set **Cluster** = your existing cluster
# MAGIC 4. Under **Schedule**, choose your cron expression:
# MAGIC    - Daily 7am: `0 7 * * *`  |  Every Monday: `0 7 * * 1`
# MAGIC 5. Add **email notifications** for success / failure
# MAGIC
# MAGIC The report at `/dbfs/FileStore/reports/sales_report.html` refreshes automatically.

# COMMAND ----------
# MAGIC %md
# MAGIC ---
# MAGIC ## ✅ Summary
# MAGIC
# MAGIC | Step | Action | Key functions |
# MAGIC |------|--------|---------------|
# MAGIC | 1 | Configure paths | `base::paste0` |
# MAGIC | 2 | Install & load packages | `utils::install.packages`, `base::library` |
# MAGIC | 3 | Prepare data | `dplyr::mutate`, `base::data.frame`, `stats::runif` |
# MAGIC | 4 | Build components | `htmltools::HTML`, `knitr::kable`, `DT::datatable`, `ggplot2::ggplot`, `plotly::plot_ly`, `leaflet::leaflet` |
# MAGIC | 5 | Write .Rmd | `base::sprintf`, `base::writeLines`, `base::tempfile` |
# MAGIC | 6 | Render HTML | `rmarkdown::render`, `rmarkdown::html_document` |
# MAGIC | 7 | Display & share | `IRdisplay::display_html`, `base::readLines` |
# MAGIC | 8 | Schedule | Databricks Workflows UI |
