library(dplyr)
library(labelled)
library(table1)
library(htmltools)
rm(list = ls())

# ---- 1) Load datasets ----
ukb_cleaned  <- readRDS("../outputs/ukb_cleaned.rds")
ukb_imputed  <- readRDS("../outputs/ukb_final_imputed.rds")

# ---- 2) P-value function ----
pvalue <- function(x, ...) {
  y <- unlist(x)
  g <- factor(rep(seq_along(x), times = sapply(x, length)))
  keep <- !is.na(y); y <- y[keep]; g <- g[keep]
  if (length(y) == 0 || nlevels(g) < 2) return("")
  if (is.numeric(y)) {
    p <- if (nlevels(g) == 2) {
      tryCatch(t.test(y ~ g)$p.value, error = function(e) NA_real_)
    } else {
      tryCatch(anova(lm(y ~ g))$`Pr(>F)`[1], error = function(e) NA_real_)
    }
  } else {
    tbl <- table(y, g)
    p <- tryCatch({
      chi <- suppressWarnings(chisq.test(tbl))
      if (any(chi$expected < 5)) fisher.test(tbl)$p.value else chi$p.value
    }, error = function(e) NA_real_)
  }
  if (is.na(p)) return("")
  if (p < 0.001) return("&lt;0.001")
  sprintf("%.3f", p)
}

# ---- 3) Bold variable labels ----
render.varlabel.bold <- function(x, ...) {
  htmltools::HTML(paste0("<strong>", table1::render.varlabel(x, ...), "</strong>"))
}

# ---- 4) Pipeline function ----
make_table1 <- function(mydata) {
  mydata <- mydata %>%
    mutate(
      outcome_chr = as.character(outcome),
      cvd_event   = if_else(trimws(outcome_chr) == "No", "No", "Yes"),
      cvd_event   = factor(cvd_event, levels = c("No", "Yes"))
    )
  
  df <- mydata %>%
    transmute(
      cvd_event = cvd_event,
      sex       = droplevels(factor(sex)),
      age       = age_at_recruitment,
      ethnicity = droplevels(factor(eth_bg)),
      BMI       = droplevels(factor(bmi)),
      sys_bp    = sys_bp,
      dia_bp    = dia_bp
    )
  
  table1::label(df$sex)       <- "Sex"
  table1::label(df$age)       <- "Age (years)"
  table1::label(df$ethnicity) <- "Ethnicity"
  table1::label(df$BMI)       <- "BMI category"
  table1::label(df$sys_bp)    <- "Systolic BP (mmHg)"
  table1::label(df$dia_bp)    <- "Diastolic BP (mmHg)"
  table1::label(df$cvd_event) <- "CVD event"
  
  table1(
    ~ sex + age + ethnicity + BMI + sys_bp + dia_bp | cvd_event,
    data            = df,
    overall         = "TOTAL",
    extra.col       = list(`P-value` = pvalue),
    render.varlabel = render.varlabel.bold
  )
}

# ---- 5) Build both tables ----
tab1_before   <- make_table1(ukb_cleaned)
tab1_imputed  <- make_table1(ukb_imputed)

# ---- 6) Save helper ----
save_table_png <- function(tab, filename) {
  if (!dir.exists("../outputs/summary")) dir.create("../outputs/summary", recursive = TRUE)
  png_file <- file.path("../outputs/summary", filename)
  tmp_html <- tempfile(fileext = ".html")
  on.exit(unlink(tmp_html), add = TRUE)
  htmltools::save_html(tab, file = tmp_html)
  file_url <- paste0("file:///", normalizePath(tmp_html, winslash = "/"))
  
  chrome <- Sys.which(c("google-chrome", "chromium-browser", "chrome", "chromium"))
  chrome <- chrome[chrome != ""]
  
  if (length(chrome) > 0 && requireNamespace("webshot2", quietly = TRUE)) {
    Sys.setenv(CHROMOTE_CHROME = chrome[1])
    webshot2::webshot(url = file_url, file = png_file,
                      vwidth = 1600, vheight = 2200, zoom = 2)
  } else {
    if (!requireNamespace("webshot", quietly = TRUE))
      install.packages("webshot", repos = "https://cloud.r-project.org")
    webshot::install_phantomjs()
    webshot::webshot(url = file_url, file = png_file,
                     vwidth = 1600, vheight = 2200, zoom = 2, delay = 0.2)
  }
  message("Saved: ", normalizePath(png_file))
}

# ---- 7) Save both PNGs ----
save_table_png(tab1_before,  "table1_before_imputation.png")
save_table_png(tab1_imputed, "table1_imputed.png")
