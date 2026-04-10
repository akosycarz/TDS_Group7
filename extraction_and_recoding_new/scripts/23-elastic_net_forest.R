# ============================================================
# SCRIPT: TOTAL + DIRECT ELASTIC NET LOGISTIC REGRESSION REFIT
#         + REPEATED 50% SUBSAMPLING
#         + FOREST PLOTS BASED ON SUBSAMPLING RESULTS
#
# PURPOSE
# - Refit standard logistic regression after elastic net stability selection
# - Assess robustness of coefficients using repeated 50% subsampling
# - Save conventional refit ORs + 95% CI
# - Save subsampling summaries
# - Draw forest plots from subsampling summaries
#
# OUTPUTS
#
# TOTAL EFFECT
# - outputs/total_elastic_net_logistic_summary.csv
# - outputs/total_elastic_net_subsample_summary.csv
# - outputs/total_elastic_net_forest_all.pdf          [optional]
#
# DIRECT EFFECT
# - outputs/direct_elastic_net_logistic_summary.csv
# - outputs/direct_elastic_net_subsample_summary.csv
# - outputs/direct_elastic_net_forest_exposure.pdf
#
# NOTES
# - Forest plots are based on median OR and IQR from subsampling
# - Logistic summary CSVs are based on full-data refit model
# - Domain background colours are taken from label_table
# - Domain appears in legend
# - IQR legend title is "IQR status"
# ============================================================

library(readr)
library(dplyr)
library(stringr)
library(ggplot2)
library(grid)
library(tibble)
library(patchwork)

set.seed(123)

# ============================================================
# 0. INPUTS
# ============================================================

output_dir <- "../outputs/summary"

if (!dir.exists(output_dir)) {
  dir.create(output_dir, recursive = TRUE)
}

# Single stable-variable file
stable_file <- "../outputs/summary/model1_stable_variables.csv"

# Optional total forest plot
make_total_plot <- TRUE

# Labels table
label_table <- read.csv("../outputs/plot_labels_domain.csv", stringsAsFactors = FALSE)

plot_labels <- setNames(label_table$plot_label, label_table$variable)
plot_domains <- setNames(label_table$domain, label_table$variable)
plot_domain_colors <- setNames(label_table$domain_color, label_table$variable)

# domain order as it appears in label table
domain_order <- label_table %>%
  distinct(domain, .keep_all = TRUE) %>%
  pull(domain)

# Base adjustment variables
base_vars <- c("age_at_recruitment", "sex", "eth_bg")

# Refit data
refit_df <- readRDS("../outputs/ukb_refit_20_imputed.rds")
refit_df$y <- ifelse(trimws(as.character(refit_df$outcome)) == "No", 0L, 1L)

# Read stable variables once
stable_vars_master <- read_csv(stable_file, show_col_types = FALSE)

# Total effect variables:
# all unique base_var values from the file
stable_vars_total <- stable_vars_master %>%
  distinct(base_var, .keep_all = TRUE)

# Direct effect variables:
# subset where var_type == "exposure"
stable_vars_direct <- stable_vars_master %>%
  filter(var_type == "exposure") %>%
  distinct(base_var, .keep_all = TRUE)

# ============================================================
# 1. HELPER FUNCTIONS
# ============================================================

get_factor_var <- function(term, factor_vars) {
  hits <- factor_vars[str_detect(term, paste0("^", factor_vars))]
  if (length(hits) == 0) return(NA_character_)
  hits[which.max(nchar(hits))]
}

make_subsample_forest_plot <- function(
    res_df,
    vars,
    title,
    filename,
    output_dir,
    x_cap = NULL,
    null_x = 1,
    domain_alpha = 0.28,
    forest_xlim = NULL,
    forest_breaks = NULL,
    forest_pad = 0.05,
    break_by = 0.10,
    pdf_width = 22,
    row_height = 0.48,
    min_pdf_height = 10
) {
  
  library(dplyr)
  library(ggplot2)
  library(patchwork)
  
  compute_forest_xlim <- function(lcl, ucl, pad = 0.03, null_x = 1) {
    xmin_raw <- min(lcl, na.rm = TRUE)
    xmax_raw <- max(ucl, na.rm = TRUE)
    
    xmin_raw <- min(xmin_raw, null_x)
    xmax_raw <- max(xmax_raw, null_x)
    
    xmin_pad <- xmin_raw - pad
    xmax_pad <- xmax_raw + pad
    
    xmin_nice <- floor(xmin_pad * 10) / 10
    xmax_nice <- ceiling(xmax_pad * 10) / 10
    
    c(xmin_nice, xmax_nice)
  }
  
  compute_forest_breaks <- function(xlim, by = 0.10) {
    seq(xlim[1], xlim[2], by = by)
  }
  
  compute_left_panel_layout <- function(var_labels, level_labels) {
    var_chars   <- if (length(var_labels) == 0) 1 else max(nchar(var_labels), na.rm = TRUE)
    level_chars <- if (length(level_labels) == 0) 1 else max(nchar(level_labels), na.rm = TRUE)
    
    gap_chars <- -6
    
    var_x   <- var_chars
    level_x <- var_chars + gap_chars + level_chars
    
    left_xlim <- c(0, level_x + 1)
    
    list(
      var_x = var_x,
      level_x = level_x,
      left_xlim = left_xlim,
      width_weight = max(8, level_x + 1)
    )
  }
  
  compute_right_panel_layout <- function(label_txt_vec) {
    label_chars <- if (length(label_txt_vec) == 0) 1 else max(nchar(label_txt_vec), na.rm = TRUE)
    
    text_x <- 1.5
    right_xlim <- c(0, text_x + label_chars + 1)
    
    list(
      text_x = text_x,
      right_xlim = right_xlim,
      width_weight = max(5, label_chars + 2)
    )
  }
  
  compute_panel_widths <- function(left_weight, forest_xlim, right_weight, break_by = 0.10) {
    forest_span <- diff(forest_xlim)
    forest_weight <- max(48, (forest_span / break_by) * 12)
    c(left_weight, forest_weight, right_weight)
  }
  
  forest_data <- res_df %>%
    filter(as.character(variable_raw) %in% vars, !is.na(OR)) %>%
    filter(is.finite(OR), is.finite(LCL), is.finite(UCL)) %>%
    mutate(
      variable_raw_chr = as.character(variable_raw),
      level_display = ifelse(is.na(level) | level == "", "", as.character(level)),
      domain = ifelse(is.na(domain) | domain == "", "Other", as.character(domain)),
      domain_color = ifelse(
        is.na(domain_color) | domain_color == "",
        "#F0F0F0",
        as.character(domain_color)
      ),
      stable_direction = ifelse(
        LCL > null_x | UCL < null_x,
        "IQR excludes 1",
        "IQR crosses 1"
      )
    )
  
  if (nrow(forest_data) == 0) {
    stop("No model terms found to plot.")
  }
  
  forest_data <- forest_data %>%
    mutate(
      domain = factor(
        domain,
        levels = unique(c(domain_order, setdiff(unique(domain), domain_order)))
      )
    ) %>%
    arrange(domain, match(variable_raw_chr, vars), level_display)
  
  forest_data <- forest_data %>%
    mutate(plot_row = row_number())
  
  n_rows <- nrow(forest_data)
  
  forest_data <- forest_data %>%
    mutate(y_id = rev(seq_len(n_rows)))
  
  if (is.null(forest_xlim)) {
    forest_xlim <- compute_forest_xlim(
      lcl = forest_data$LCL,
      ucl = forest_data$UCL,
      pad = forest_pad,
      null_x = null_x
    )
  }
  
  x_left_forest  <- forest_xlim[1]
  x_right_forest <- forest_xlim[2]
  
  if (!is.null(x_cap)) {
    x_right_forest <- min(x_right_forest, x_cap)
    forest_xlim <- c(x_left_forest, x_right_forest)
  }
  
  if (is.null(forest_breaks)) {
    forest_breaks <- compute_forest_breaks(forest_xlim, by = break_by)
  }
  
  forest_data <- forest_data %>%
    mutate(
      UCL_plot = pmin(UCL, x_right_forest),
      LCL_plot = pmax(LCL, x_left_forest),
      label_txt = paste0(
        sprintf("%.2f", OR), " (",
        sprintf("%.2f", LCL), "-", sprintf("%.2f", UCL), ")"
      )
    )
  
  domain_bands <- forest_data %>%
    group_by(domain, domain_color) %>%
    summarise(
      ymin = min(y_id) - 0.5,
      ymax = max(y_id) + 0.5,
      .groups = "drop"
    ) %>%
    mutate(domain = as.character(domain))
  
  fill_values <- setNames(domain_bands$domain_color, domain_bands$domain)
  
  var_text_df <- forest_data %>%
    group_by(variable_raw_chr, variable_label, ref_level) %>%
    summarise(
      y_var = max(y_id),
      .groups = "drop"
    ) %>%
    mutate(
      var_label_plot = ifelse(
        !is.na(ref_level) & ref_level != "",
        paste0(variable_label, " (ref: ", ref_level, ")"),
        variable_label
      )
    )
  
  level_text_df <- forest_data %>%
    filter(level_display != "") %>%
    transmute(
      y_id = y_id,
      level_label_plot = level_display
    )
  
  left_layout <- compute_left_panel_layout(
    var_labels = var_text_df$var_label_plot,
    level_labels = level_text_df$level_label_plot
  )
  
  right_layout <- compute_right_panel_layout(
    label_txt_vec = forest_data$label_txt
  )
  
  panel_widths <- compute_panel_widths(
    left_weight  = left_layout$width_weight,
    forest_xlim  = forest_xlim,
    right_weight = right_layout$width_weight,
    break_by     = break_by
  )
  
  left_plot <- ggplot() +
    geom_text(
      data = var_text_df,
      aes(x = left_layout$var_x, y = y_var, label = var_label_plot),
      hjust = 1,
      vjust = 0.5,
      fontface = "bold",
      size = 6.5,
      colour = "grey15"
    ) +
    geom_text(
      data = level_text_df,
      aes(x = left_layout$level_x, y = y_id, label = level_label_plot),
      hjust = 1,
      vjust = 0.5,
      size = 5,
      colour = "grey30"
    ) +
    scale_x_continuous(
      limits = left_layout$left_xlim,
      expand = c(0, 0)
    ) +
    scale_y_continuous(
      limits = c(0.5, n_rows + 0.5),
      breaks = forest_data$y_id,
      labels = rep("", nrow(forest_data)),
      expand = c(0, 0)
    ) +
    theme_void() +
    theme(
      plot.margin = margin(10, 0, 10, 10)
    ) +
    coord_cartesian(clip = "off")
  
  forest_plot <- ggplot(forest_data, aes(x = OR, y = y_id, colour = stable_direction)) +
    geom_rect(
      data = domain_bands,
      inherit.aes = FALSE,
      aes(
        xmin = x_left_forest,
        xmax = x_right_forest,
        ymin = ymin,
        ymax = ymax,
        fill = domain
      ),
      alpha = domain_alpha,
      colour = NA
    ) +
    geom_vline(
      xintercept = null_x,
      linetype = "dashed",
      colour = "grey40",
      linewidth = 0.7
    ) +
    geom_errorbar(
      aes(xmin = LCL_plot, xmax = UCL_plot),
      width = 0.30,
      linewidth = 1.15,
      na.rm = TRUE
    ) +
    geom_point(
      size = 3,
      na.rm = TRUE
    ) +
    scale_fill_manual(
      values = fill_values,
      name = "Domain"
    ) +
    scale_colour_manual(
      values = c(
        "IQR excludes 1" = "black",
        "IQR crosses 1" = "grey60"
      ),
      name = "IQR status"
    ) +
    guides(
      fill = guide_legend(
        order = 1,
        override.aes = list(alpha = 0.6)
      ),
      colour = guide_legend(
        order = 2,
        override.aes = list(size = 3)
      )
    ) +
    scale_y_continuous(
      limits = c(0.5, n_rows + 0.5),
      breaks = forest_data$y_id,
      labels = rep("", nrow(forest_data)),
      expand = c(0, 0)
    ) +
    scale_x_continuous(
      limits = c(x_left_forest, x_right_forest),
      breaks = forest_breaks,
      labels = function(x) sprintf("%.2f", x),
      expand = c(0, 0)
    ) +
    labs(
      title = title,
      x = "Odds ratio (median across subsamples)",
      y = NULL
    ) +
    theme_minimal(base_size = 11) +
    theme(
      plot.title = element_text(face = "bold", size = 27, hjust = 0.8, margin = margin(b = 17)),
      legend.position = "bottom",
      legend.box = "vertical",
      legend.title = element_text(size = 15, face = "bold"),
      legend.text = element_text(size = 14),
      axis.text.y = element_text(size = 14),
      axis.ticks.y = element_blank(),
      axis.text.x = element_text(size = 14),
      axis.title.x = element_text(size = 18),
      panel.grid.major.x = element_blank(),
      panel.grid.minor.x = element_blank(),
      panel.grid.major.y = element_blank(),
      panel.grid.minor = element_blank(),
      plot.margin = margin(10, 0, 10, 0)
    )
  
  right_plot <- ggplot(forest_data, aes(y = y_id)) +
    geom_text(
      aes(x = right_layout$text_x, label = label_txt),
      hjust = 0,
      vjust = 0.5,
      size = 5,
      colour = "grey20",
      lineheight = 0.95,
      na.rm = TRUE
    ) +
    scale_x_continuous(
      limits = right_layout$right_xlim,
      expand = c(0, 0)
    ) +
    scale_y_continuous(
      limits = c(0.5, n_rows + 0.5),
      breaks = forest_data$y_id,
      labels = rep("", nrow(forest_data)),
      expand = c(0, 0)
    ) +
    theme_void() +
    theme(
      plot.margin = margin(10, 10, 10, 8)
    ) +
    coord_cartesian(clip = "off")
  
  p <- left_plot + forest_plot + right_plot +
    plot_layout(widths = panel_widths) +
    plot_annotation(
      caption = "* indicates base variables",
      theme = theme(
        plot.caption = element_text(
          hjust = 1,
          size = 14,
          colour = "grey30"
        )
      )
    )
  
  pdf(
    file.path(output_dir, filename),
    width = pdf_width,
    height = max(min_pdf_height, nrow(forest_data) * row_height + 4)
  )
  print(p)
  dev.off()
  
  cat("Saved:", file.path(output_dir, filename), "\n")
  invisible(p)
}

run_elastic_net_pipeline <- function(
    stable_vars,
    analysis_name,
    refit_df,
    base_vars,
    plot_labels,
    output_dir,
    n_runs = 200,
    sample_frac = 0.50,
    x_cap = 1.5,
    make_all_plot = FALSE,
    make_exposure_plot = FALSE
) {
  
  cat("\n============================================================\n")
  cat("Running analysis:", analysis_name, "\n")
  cat("Stable variable file:", stable_file, "\n")
  cat("============================================================\n")
  
  selected_vars <- stable_vars %>%
    distinct(base_var, .keep_all = TRUE) %>%
    arrange(desc(selection_proportion)) %>%
    pull(base_var)
  
  cat("\nSelected variables from stable_vars:\n")
  print(selected_vars)
  
  full_model_vars <- unique(c(base_vars, selected_vars))
  
  exposure_vars <- stable_vars %>%
    filter(var_type == "exposure") %>%
    distinct(base_var, .keep_all = TRUE) %>%
    arrange(desc(selection_proportion)) %>%
    pull(base_var)
  
  plot_vars_exposure <- unique(c(base_vars, exposure_vars))
  
  full_model_vars <- full_model_vars[full_model_vars %in% names(refit_df)]
  plot_vars_exposure <- plot_vars_exposure[plot_vars_exposure %in% names(refit_df)]
  
  cat("\nVariables used in full model:\n")
  print(full_model_vars)
  
  cat("\nVariables used in exposure plot:\n")
  print(plot_vars_exposure)
  
  df_analysis <- refit_df
  
  for (v in full_model_vars) {
    if (is.character(df_analysis[[v]]) || is.factor(df_analysis[[v]])) {
      df_analysis[[v]] <- factor(df_analysis[[v]])
    }
  }
  
  fit_formula <- as.formula(
    paste("y ~", paste(full_model_vars, collapse = " + "))
  )
  
  cat("\nFull model formula:\n")
  print(fit_formula)
  
  fit_refit <- glm(
    fit_formula,
    data = df_analysis,
    family = binomial
  )
  
  cat("\n=== Odds ratios with 95% CI:", analysis_name, "===\n")
  
  coef_est <- coef(fit_refit)
  se_est   <- sqrt(diag(vcov(fit_refit)))
  
  lower_ci <- coef_est - 1.96 * se_est
  upper_ci <- coef_est + 1.96 * se_est
  
  or_results <- exp(cbind(
    OR = coef_est,
    Lower_95_CI = lower_ci,
    Upper_95_CI = upper_ci
  ))
  
  print(or_results)
  
  all_terms <- names(coef(fit_refit))
  all_terms <- setdiff(all_terms, "(Intercept)")
  
  cat("\nRunning subsample stability analysis:\n")
  cat("- Analysis:", analysis_name, "\n")
  cat("- Number of runs:", n_runs, "\n")
  cat("- Fraction sampled each run:", sample_frac, "\n")
  
  subsample_results <- vector("list", n_runs)
  
  for (i in seq_len(n_runs)) {
    cat("Run", i, "of", n_runs, "for", analysis_name, "\n")
    
    idx <- sample(
      seq_len(nrow(df_analysis)),
      size = floor(sample_frac * nrow(df_analysis)),
      replace = FALSE
    )
    
    df_sub <- df_analysis[idx, , drop = FALSE]
    
    for (v in full_model_vars) {
      if (is.factor(df_analysis[[v]])) {
        df_sub[[v]] <- factor(df_sub[[v]], levels = levels(df_analysis[[v]]))
      }
    }
    
    fit_i <- tryCatch(
      suppressWarnings(glm(fit_formula, data = df_sub, family = binomial)),
      error = function(e) NULL
    )
    
    if (is.null(fit_i)) {
      subsample_results[[i]] <- data.frame(
        run = i,
        term = all_terms,
        estimate = NA_real_
      )
      next
    }
    
    coef_i <- coef(fit_i)
    
    res_i <- data.frame(
      run = i,
      term = all_terms,
      estimate = NA_real_,
      row.names = NULL
    )
    
    matched_terms <- intersect(names(coef_i), all_terms)
    res_i$estimate[match(matched_terms, res_i$term)] <- coef_i[matched_terms]
    
    subsample_results[[i]] <- res_i
  }
  
  coef_long <- bind_rows(subsample_results)
  
  cat("\n=== First few rows of repeated-fit coefficient table ===\n")
  print(head(coef_long))
  
  coef_summary <- coef_long %>%
    group_by(term) %>%
    summarise(
      n_non_missing   = sum(!is.na(estimate)),
      selection_prop  = mean(!is.na(estimate)),
      estimate_median = ifelse(n_non_missing > 0, median(estimate, na.rm = TRUE), NA_real_),
      estimate_q25    = ifelse(n_non_missing > 0, quantile(estimate, 0.25, na.rm = TRUE), NA_real_),
      estimate_q75    = ifelse(n_non_missing > 0, quantile(estimate, 0.75, na.rm = TRUE), NA_real_),
      .groups = "drop"
    ) %>%
    mutate(
      OR  = exp(estimate_median),
      LCL = exp(estimate_q25),
      UCL = exp(estimate_q75)
    )
  
  cat("\n=== Subsample stability summary ===\n")
  print(coef_summary)
  
  factor_vars <- names(fit_refit$xlevels)
  
  model_tbl <- coef_summary %>%
    mutate(
      factor_var = sapply(term, get_factor_var, factor_vars = factor_vars),
      variable_raw = if_else(!is.na(factor_var), factor_var, term),
      level = if_else(
        !is.na(factor_var),
        str_remove(term, paste0("^", factor_var)),
        ""
      ),
      is_categorical = !is.na(factor_var)
    )
  
  ref_lookup <- sapply(full_model_vars, function(v) {
    if (is.factor(df_analysis[[v]])) {
      levels(df_analysis[[v]])[1]
    } else {
      NA_character_
    }
  }, USE.NAMES = TRUE)
  
  var_type_lookup <- stable_vars %>%
    distinct(base_var, var_type) %>%
    tibble::deframe()
  
  model_tbl <- model_tbl %>%
    mutate(
      ref_level = unname(ref_lookup[variable_raw]),
      variable_label = unname(plot_labels[variable_raw]),
      variable_label = if_else(is.na(variable_label), variable_raw, variable_label),
      variable_display = if_else(
        !is.na(ref_level),
        paste0(variable_label, " (ref: ", ref_level, ")"),
        variable_label
      ),
      domain = unname(plot_domains[variable_raw]),
      domain_color = unname(plot_domain_colors[variable_raw]),
      domain = if_else(is.na(domain), "Other", domain),
      domain_color = if_else(is.na(domain_color), "#F0F0F0", domain_color),
      var_type = case_when(
        variable_raw %in% base_vars ~ "base",
        variable_raw %in% names(var_type_lookup) ~ unname(var_type_lookup[variable_raw]),
        TRUE ~ NA_character_
      ),
      analysis = analysis_name
    )
  
  model_tbl$variable_raw <- factor(model_tbl$variable_raw, levels = full_model_vars)
  
  model_tbl <- model_tbl %>%
    mutate(
      domain = factor(domain, levels = unique(c(domain_order, setdiff(unique(domain), domain_order)))),
      variable_raw_chr = as.character(variable_raw)
    ) %>%
    arrange(domain, match(variable_raw_chr, full_model_vars), level) %>%
    select(-variable_raw_chr)
  
  cat("\n=== Plotting table ===\n")
  print(model_tbl)
  
  logistic_file  <- paste0(analysis_name, "_elastic_net_logistic_summary.csv")
  subsample_file <- paste0(analysis_name, "_elastic_net_subsample_summary.csv")
  
  write.csv(
    or_results,
    file.path(output_dir, logistic_file),
    row.names = TRUE
  )
  
  write_csv(
    model_tbl,
    file.path(output_dir, subsample_file)
  )
  
  cat("\nSaved summary files for", analysis_name, ":\n")
  cat("-", file.path(output_dir, logistic_file), "\n")
  cat("-", file.path(output_dir, subsample_file), "\n")
  
  if (make_all_plot) {
    forest_all_file <- paste0(analysis_name, "_elastic_net_forest_all.pdf")
    
    make_subsample_forest_plot(
      res_df     = model_tbl,
      vars       = full_model_vars,
      title      = paste("Forest Plot of", str_to_title(analysis_name), "Elastic Net-Selected Variables"),
      filename   = forest_all_file,
      output_dir = output_dir,
      x_cap      = x_cap
    )
  }
  
  if (make_exposure_plot) {
    forest_exp_file <- paste0(analysis_name, "_elastic_net_forest_exposure.pdf")
    
    make_subsample_forest_plot(
      res_df     = model_tbl,
      vars       = plot_vars_exposure,
      title      = paste("Elastic Net:", str_to_title(analysis_name), "Exposure Variables Based on Repeated Subsampling"),
      filename   = forest_exp_file,
      output_dir = output_dir,
      x_cap      = x_cap
    )
  }
  
  invisible(list(
    fit_refit        = fit_refit,
    or_results       = or_results,
    coef_long        = coef_long,
    subsample_table  = model_tbl,
    full_model_vars  = full_model_vars,
    exposure_vars    = plot_vars_exposure
  ))
}

# ============================================================
# 2. RUN TOTAL-EFFECT PIPELINE
# ============================================================

res_total <- run_elastic_net_pipeline(
  stable_vars        = stable_vars_total,
  analysis_name      = "total",
  refit_df           = refit_df,
  base_vars          = base_vars,
  plot_labels        = plot_labels,
  output_dir         = output_dir,
  n_runs             = 200,
  sample_frac        = 0.50,
  x_cap              = 1.5,
  make_all_plot      = make_total_plot,
  make_exposure_plot = FALSE
)

# ============================================================
# 3. RUN DIRECT-EFFECT PIPELINE
# ============================================================

res_direct <- run_elastic_net_pipeline(
  stable_vars        = stable_vars_direct,
  analysis_name      = "direct",
  refit_df           = refit_df,
  base_vars          = base_vars,
  plot_labels        = plot_labels,
  output_dir         = output_dir,
  n_runs             = 200,
  sample_frac        = 0.50,
  x_cap              = 1.5,
  make_all_plot      = FALSE,
  make_exposure_plot = TRUE
)

# ============================================================
# 4. FINAL OUTPUT LIST
# ============================================================

cat("\n============================================================\n")
cat("ALL ANALYSES COMPLETE\n")
cat("============================================================\n")
cat("Saved files:\n")
cat("- ../outputs/total_elastic_net_logistic_summary.csv\n")
cat("- ../outputs/total_elastic_net_subsample_summary.csv\n")
if (make_total_plot) {
  cat("- ../outputs/total_elastic_net_forest_all.pdf\n")
}
cat("- ../outputs/direct_elastic_net_logistic_summary.csv\n")
cat("- ../outputs/direct_elastic_net_subsample_summary.csv\n")
cat("- ../outputs/direct_elastic_net_forest_exposure.pdf\n")