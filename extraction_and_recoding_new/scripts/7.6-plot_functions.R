# ============================================================
# SHARED PLOT FUNCTIONS
# Used by: lasso_analysis.R, elastic_net_analysis.R,
#          xgboost_shap_logistic_refit.R
#
# Forest plot settings:
#   - No left facet-strip labels
#   - Black  = IQR excludes 1
#   - Grey   = IQR crosses 1
#   - Legend shown for colour meaning
#   - X-axis fixed 0.25 to 2
#
# Incremental AUC plot settings:
#   - Y-axis fixed 0.5 to 1.0
# ============================================================

library(ggplot2)
library(dplyr)
library(stringr)
library(tibble)

# ============================================================
# DOMAIN MAPPING
# Used by all three analysis scripts for domain-split forest plots
# ============================================================

domain_map <- tribble(
  ~variable_raw,                    ~domain,
  # Demographics & Socioeconomic
  "age_at_recruitment",             "Demographics & Socioeconomic",
  "sex",                            "Demographics & Socioeconomic",
  "eth_bg",                         "Demographics & Socioeconomic",
  "pregnant_yn",                    "Demographics & Socioeconomic",
  "hh_income_pre_tax",              "Demographics & Socioeconomic",
  "qualifications",                 "Demographics & Socioeconomic",
  "current_employ_status_grp",      "Demographics & Socioeconomic",
  "age_full_edu",                   "Demographics & Socioeconomic",
  # Lifestyle
  "smoking_status",                 "Lifestyle",
  "smoking_pack_years",             "Lifestyle",
  "alcohol_status_with_freq",       "Lifestyle",
  "risky_driving_speeding",         "Lifestyle",
  "diet_tea",                       "Lifestyle",
  "diet_coffee",                    "Lifestyle",
  "diet_water",                     "Lifestyle",
  "sleep_duration",                 "Lifestyle",
  "sleep_insomnia",                 "Lifestyle",
  "mh_loneliness",                  "Lifestyle",
  "mh_social_support_confide",      "Lifestyle",
  "mh_neuroticism",                 "Lifestyle",
  "MET_summed",                     "Lifestyle",
  "sedentary_total_hours",          "Lifestyle",
  "job_walk_stand_yn",              "Lifestyle",
  # Clinical
  "bmi",                            "Clinical",
  "body_fat_pct",                   "Clinical",
  "waist_circumference_cm",         "Clinical",
  "hip_circumference_cm",           "Clinical",
  "sys_bp",                         "Clinical",
  "dia_bp",                         "Clinical",
  "arterial_stiffness_index",       "Clinical",
  "fvc",                            "Clinical",
  "fev1",                           "Clinical",
  # Biomarkers
  "glucose",                        "Biomarkers",
  "hba1c",                          "Biomarkers",
  "cholesterol",                    "Biomarkers",
  "hdl",                            "Biomarkers",
  "ldl",                            "Biomarkers",
  "triglycerides",                  "Biomarkers",
  "apolipoprotein_a",               "Biomarkers",
  "apolipoprotein_b",               "Biomarkers",
  "creatinine",                     "Biomarkers",
  "urea",                           "Biomarkers",
  "cystatin_c",                     "Biomarkers",
  "urate",                          "Biomarkers",
  "bilirubin_total",                "Biomarkers",
  "bilirubin_direct",               "Biomarkers",
  "alanine_amino",                  "Biomarkers",
  "aspartate_amino",                "Biomarkers",
  "gamma_glumy_tran",               "Biomarkers",
  "albumin",                        "Biomarkers",
  "alkaline_phos",                  "Biomarkers",
  "oestradiol",                     "Biomarkers",
  "testosterone",                   "Biomarkers",
  "igf1",                           "Biomarkers",
  "shbg",                           "Biomarkers",
  "vitamin_d",                      "Biomarkers",
  "vitamin_b12",                    "Biomarkers ",
  "vitamin_b6",                     "Biomarkers",
  "calcium",                        "Biomarkers",
  "phosphate",                      "Biomarkers",
  "rbc_count",                      "Biomarkers",
  "haemoglobin_concent",            "Biomarkers",
  "haematocrit_percent",            "Biomarkers",
  "rdw",                            "Biomarkers",
  "mean_corp_vol",                  "Biomarkers",
  "mean_corp_haem",                 "Biomarkers",
  "mean_corp_haem_con",             "Biomarkers",
  "platelet_count",                 "Biomarkers",
  "mean_platelet_volume",           "Biomarkers",
  "platelet_distribution_width",    "Biomarkers",
  "platelet_crit",                  "Biomarkers",
  "lymphocyte_count",               "Biomarkers",
  
  "monocyte_count",                 "Biomarkers",
  "neutrophil_count",               "Biomarkers",
  "eosinophil_count",               "Biomarkers",
  "basophil_count",                 "Biomarkers",
  "reticulocyte_count",             "Biomarkers",
  "hlr_reticulocyte_count",         "Biomarkers",
  "lymphocyte_percentage",          "Biomarkers",
  "monocyte_percentage",            "Biomarkers",
  "neutrophil_percentage",          "Biomarkers",
  "eosinophil_percentage",          "Biomarkers",
  "basophil_percentage",            "Biomarkers",
  "reticulocyte_percentage",        "Biomarkers",
  "hlr_reticulocyte_percentage",    "Biomarkers",
  "mean_reticulocyte_volume",       "Biomarkers",
  "mean_sphered_cell_volume",       "Biomarkers",
  "immature_reticulocyte_frac",     "Biomarkers",
  "crp",                            "Biomarkers",
  "rheumatoid_factor",              "Biomarkers",
  "lipoprotein_a",                  "Biomarkers",
  #Environment
  "air_no2_2010",                   "Environment",
  "air_pm10_2010",                  "Environment",
  "air_pm2_5_2010",                 "Environment",
  "noise24h",                       "Environment",
  "green_greenspace_300m",          "Environment",
  "green_garden_300m",              "Environment",
  "green_natural_300m",             "Environment",
  "blue_distance_coast",            "Environment"
)

domains_ordered <- c(
  "Demographics & Socioeconomic",
  "Lifestyle",
  "Clinical",
  "Biomarkers",
  "Biomarkers II",
  "Biomarkers III",
  "Environment"
)

# ============================================================
# DOMAIN COLOUR PALETTE
# ============================================================

# ============================================================
# DOMAIN COLOUR PALETTE
# ============================================================

domain_colours <- c(
  "Demographics & Socioeconomic" = "#1f77b4",
  "Lifestyle"                    = "#2ca02c",
  "Clinical"                     = "#9467bd",
  "Biomarkers"                   = "#ff7f0e",
  "Environment"                  = "#17becf",
  "Other"                        = "grey50"
)

# ============================================================
# VARIABLE LABELS LOADER
# Reads outputs/plot_labels_domain.csv and returns a named vector
#   names  = raw variable name  (e.g. "bmi")
#   values = display label      (e.g. "BMI")
# Pass the result as `variable_labels` to make_subsample_forest_plot().
# ============================================================

load_variable_labels <- function(path = "../outputs/plot_labels_domain.csv") {
  tryCatch({
    lab_df <- read_csv(path, show_col_types = FALSE)
    setNames(lab_df$plot_label, lab_df$variable)
  }, error = function(e) {
    message("[WARN] Could not load variable labels from: ", path,
            " — raw names will be used.")
    NULL
  })
}

# ============================================================
# FOREST PLOT
# Single graph, variables ordered by domain
# - Categorical variables: bold header row (no point) + indented level rows
# - Continuous variables: single row with variable name
# - Background bands coloured by domain (fill legend)
# - Points/bars: black = IQR excludes 1, dark grey = IQR crosses 1
# - X-axis fixed 0.25 to 2
# ============================================================

make_subsample_forest_plot <- function(res_df, vars, title, filename,
                                       output_dir      = "../outputs",
                                       variable_labels = NULL,
                                       labels_path     = "../outputs/plot_labels_domain.csv") {
  
  # Auto-load labels from CSV if not supplied
  if (is.null(variable_labels)) {
    variable_labels <- load_variable_labels(labels_path)
  }
  
  # ---- 1. Build base data ----
  forest_data <- res_df %>%
    filter(as.character(variable_raw) %in% vars, !is.na(OR)) %>%
    filter(is.finite(OR), is.finite(LCL), is.finite(UCL)) %>%
    left_join(domain_map, by = "variable_raw") %>%
    mutate(
      domain        = coalesce(domain, "Other"),
      domain        = factor(domain, levels = c(domains_ordered, "Other")),
      level_display = as.character(level),   # "" for continuous variables
      is_header     = FALSE,
      var_level     = paste0(as.character(variable_raw), "|||", level_display),
      iqr_status    = ifelse(LCL > 1 | UCL < 1, "IQR excludes 1", "IQR crosses 1"),
      OR_plot       = pmin(pmax(OR,  0.5), 2),
      LCL_plot      = pmin(pmax(LCL, 0.5), 2),
      UCL_plot      = pmin(pmax(UCL, 0.5), 2)
    ) %>%
    arrange(domain, variable_raw, level_display)
  
  if (nrow(forest_data) == 0) stop("No model terms found to plot.")
  
  # ---- 2. Insert header rows for categorical variables ----
  # A header row is a label-only row that shows the variable name with no point/CI
  cat_vars <- forest_data %>%
    filter(nchar(level_display) > 0) %>%
    pull(variable_raw) %>%
    as.character() %>%
    unique()
  
  if (length(cat_vars) > 0) {
    
    cat_domains <- forest_data %>%
      filter(as.character(variable_raw) %in% cat_vars) %>%
      distinct(variable_raw, domain)
    
    header_rows <- cat_domains %>%
      mutate(
        level_display = "__HEADER__",
        is_header     = TRUE,
        var_level     = paste0(as.character(variable_raw), "|||__HEADER__"),
        iqr_status    = NA_character_,
        OR_plot       = NA_real_,  LCL_plot = NA_real_,  UCL_plot = NA_real_,
        OR            = NA_real_,  LCL      = NA_real_,  UCL      = NA_real_
      )
    
    # Fill any remaining columns from forest_data with NA
    for (col in setdiff(names(forest_data), names(header_rows))) {
      header_rows[[col]] <- NA
    }
    header_rows <- header_rows[, names(forest_data), drop = FALSE]
    
    forest_data <- bind_rows(forest_data, header_rows) %>%
      arrange(
        domain,
        variable_raw,
        !is_header,      # headers sort first (is_header=TRUE → !is_header=FALSE → 0)
        level_display
      )
  }
  
  # ---- 3. Set y-axis factor order (top of plot = first in data) ----
  level_order           <- unique(forest_data$var_level)
  forest_data$var_level <- factor(forest_data$var_level, levels = rev(level_order))
  
  # ---- 4. Y-axis label function ----
  # Helper: look up human-readable label; fall back to raw name if not found
  get_label <- function(raw_name) {
    if (!is.null(variable_labels)) {
      lbl <- variable_labels[raw_name]   # NA if key not present
      if (!is.na(lbl)) return(unname(lbl))
    }
    raw_name
  }
  
  y_labels <- function(x) {
    sapply(x, function(lbl) {
      parts <- strsplit(lbl, "\\|\\|\\|")[[1]]
      var   <- parts[1]
      lvl   <- if (length(parts) >= 2) parts[2] else ""
      if (lvl == "__HEADER__") {
        # Categorical variable name header — shown in bold via fontface below
        get_label(var)
      } else if (nchar(trimws(lvl)) == 0) {
        # Continuous variable — show human-readable label
        get_label(var)
      } else {
        # Categorical level — show variable label as prefix, level indented
        paste0(get_label(var), ":  \u2514 ", lvl)
      }
    }, USE.NAMES = FALSE)
  }
  
  # Rows that are headers (for bold y-axis text)
  header_var_levels <- forest_data %>%
    filter(is_header) %>%
    pull(var_level) %>%
    as.character()
  
  all_var_levels <- levels(forest_data$var_level)
  y_face <- ifelse(all_var_levels %in% header_var_levels, "bold", "plain")
  
  # ---- 5. Domain background bands ----
  n_levels  <- length(all_var_levels)
  level_pos <- data.frame(var_level = all_var_levels, y_pos = seq_len(n_levels))
  
  domain_bands <- forest_data %>%
    distinct(var_level, domain) %>%
    filter(!is.na(domain)) %>%
    left_join(level_pos, by = "var_level") %>%
    group_by(domain) %>%
    summarise(ymin = min(y_pos) - 0.5, ymax = max(y_pos) + 0.5, .groups = "drop")
  
  # ---- 6. Build plot ----
  p <- ggplot(forest_data, aes(x = OR_plot, y = var_level)) +
    # Domain background bands
    geom_rect(
      data        = domain_bands,
      aes(ymin = ymin, ymax = ymax, fill = domain),
      xmin        = -Inf, xmax = Inf,
      alpha       = 0.18,
      inherit.aes = FALSE
    ) +
    geom_vline(xintercept = 1, linetype = "dashed",
               colour = "grey30", linewidth = 0.7) +
    geom_errorbar(
      aes(xmin = LCL_plot, xmax = UCL_plot, colour = iqr_status),
      width = 0.30, linewidth = 1.15, na.rm = TRUE, orientation = "y"
    ) +
    geom_point(aes(colour = iqr_status), size = 3, na.rm = TRUE) +
    scale_fill_manual(
      name   = "Domain",
      values = domain_colours,
      drop   = TRUE
    ) +
    scale_colour_manual(
      name         = "IQR status",
      values       = c("IQR excludes 1" = "black", "IQR crosses 1" = "grey55"),
      na.translate = FALSE   # don't show NA (headers) in legend
    ) +
    scale_x_continuous(limits = c(0.5, 2), breaks = c(0.5, 0.75, 1, 1.25, 1.5, 1.75, 2)) +
    scale_y_discrete(labels = y_labels) +
    labs(title = title, x = "Odds Ratio (Median & IQR)", y = NULL) +
    theme_minimal(base_size = 11) +
    theme(
      plot.title         = element_text(face = "bold", size = 13, hjust = 0.5),
      legend.position    = "bottom",
      legend.title       = element_text(size = 9, face = "bold"),
      legend.text        = element_text(size = 9),
      # Bold for header rows, plain for levels/continuous
      axis.text.y        = element_text(size = 8, face = y_face),
      axis.text.x        = element_text(size = 9),
      panel.grid.major.y = element_blank(),
      panel.grid.minor   = element_blank(),
      plot.margin        = margin(10, 10, 10, 10)
    ) +
    guides(
      fill   = guide_legend(order = 1, nrow = 2, override.aes = list(alpha = 0.5)),
      colour = guide_legend(order = 2)
    )
  
  pdf(file.path(output_dir, filename),
      width  = 11,
      height = max(8, n_levels * 0.35 + 3))
  print(p)
  dev.off()
  
  cat("Saved:", file.path(output_dir, filename), "\n")
  invisible(p)
}

# ============================================================
# INCREMENTAL AUC PLOT
# ============================================================

make_incremental_auc_plot <- function(cum_auc_df, title, filename,
                                      output_dir      = "../outputs",
                                      variable_labels = NULL,
                                      labels_path     = "../outputs/plot_labels_domain.csv") {
  
  # Auto-load labels from CSV if not supplied
  if (is.null(variable_labels)) {
    variable_labels <- load_variable_labels(labels_path)
  }
  
  # Replace raw variable names in step labels with human-readable labels.
  # Steps are formatted as "Base" or "+ raw_var_name".
  if (!is.null(variable_labels)) {
    cum_auc_df <- cum_auc_df %>%
      mutate(step = sapply(as.character(step), function(s) {
        if (startsWith(s, "+ ")) {
          raw  <- sub("^\\+ ", "", s)
          lbl  <- variable_labels[raw]
          if (!is.na(lbl)) paste0("+ ", unname(lbl)) else s
        } else {
          s   # "Base" stays as-is
        }
      }),
      step = factor(step, levels = unique(step)))
  }
  
  p <- ggplot(cum_auc_df, aes(x = step, y = auc, group = 1)) +
    geom_errorbar(
      aes(ymin = auc_low, ymax = auc_high),
      width     = 0.5,
      linewidth = 0.6,
      colour    = "blue2"
    ) +
    geom_point(size = 2.5, colour = "blue2") +
    labs(title = title, x = "Model step", y = "AUC") +
    coord_cartesian(ylim = c(0.5, 1.0)) +
    theme_minimal(base_size = 11) +
    theme(
      plot.title  = element_text(face = "bold", hjust = 0.5),
      axis.text.x = element_text(angle = 45, hjust = 1)
    )
  
  ggsave(
    filename = file.path(output_dir, filename),
    plot     = p,
    width    = 10,
    height   = 6,
    dpi      = 300
  )
  
  cat("Saved:", file.path(output_dir, filename), "\n")
  invisible(p)
}
