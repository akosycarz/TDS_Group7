# ============================================================
# Combined forest plots by domain
# One PDF per domain
# Split across pages by VARIABLE blocks, not raw rows
# 3-panel layout preserved:
#   left   = variable / level labels
#   middle = forest plot with domain background colours
#   right  = OR text
# ============================================================

suppressPackageStartupMessages({
  library(ggplot2)
  library(dplyr)
  library(stringr)
  library(grid)
  library(gridExtra)
  library(ggtext)
  library(patchwork)
})

# ============================================================
# Input files
# ============================================================

results_file <- "../outputs/summary/uni_analysis_combined.csv"
label_file   <- "../outputs/plot_labels_domain.csv"

if (!file.exists(results_file)) {
  stop(paste("Results file not found:", results_file))
}

if (!file.exists(label_file)) {
  stop(paste("Label file not found:", label_file))
}

# ============================================================
# Read inputs
# ============================================================

unified <- read.csv(results_file, stringsAsFactors = FALSE)
label_table <- read.csv(label_file, stringsAsFactors = FALSE)

# ============================================================
# Output directory
# ============================================================

output_dir <- "../outputs/summary"

if (!dir.exists(output_dir)) {
  stop(paste("Output directory not found:", output_dir))
}

# ============================================================
# Clean label table first
# ============================================================

label_table <- label_table %>%
  mutate(
    variable     = trimws(as.character(variable)),
    plot_label   = trimws(as.character(plot_label)),
    domain       = trimws(as.character(domain)),
    domain_color = trimws(as.character(domain_color))
  )

plot_labels <- setNames(label_table$plot_label, label_table$variable)
plot_domains <- setNames(label_table$domain, label_table$variable)
plot_domain_colors <- setNames(label_table$domain_color, label_table$variable)

domain_order <- label_table %>%
  distinct(domain, .keep_all = TRUE) %>%
  pull(domain)

# ============================================================
# Check required columns in results file
# ============================================================

required_cols <- c(
  "variable", "variable_type", "level", "level_order", "ref_level",
  "OR", "LCL", "UCL", "p", "FDR", "N"
)

missing_cols <- setdiff(required_cols, names(unified))
if (length(missing_cols) > 0) {
  stop(
    paste(
      "Results file is missing required columns:",
      paste(missing_cols, collapse = ", ")
    )
  )
}

# ============================================================
# Clean results table
# ============================================================

unified <- unified %>%
  mutate(
    variable      = trimws(as.character(variable)),
    variable_type = trimws(as.character(variable_type)),
    level         = as.character(level),
    ref_level     = as.character(ref_level),
    level_order   = suppressWarnings(as.integer(level_order)),
    OR            = suppressWarnings(as.numeric(OR)),
    LCL           = suppressWarnings(as.numeric(LCL)),
    UCL           = suppressWarnings(as.numeric(UCL)),
    p             = suppressWarnings(as.numeric(p)),
    FDR           = suppressWarnings(as.numeric(FDR)),
    N             = suppressWarnings(as.numeric(N)),
    var_type      = case_when(
      variable_type == "continuous"  ~ "continuous",
      variable_type == "categorical" ~ "categorical",
      TRUE                           ~ variable_type
    )
  ) %>%
  filter(var_type %in% c("continuous", "categorical")) %>%
  filter(!is.na(OR), is.finite(OR), is.finite(LCL), is.finite(UCL)) %>%
  mutate(
    LCL_r = round(LCL, 2),
    UCL_r = round(UCL, 2),
    stable_direction = case_when(
      LCL_r > 1 ~ "IQR excludes 1",
      UCL_r < 1 ~ "IQR excludes 1",
      TRUE      ~ "IQR crosses 1"
    )
  )

cat("Unified table rows:", nrow(unified), "\n")

# ============================================================
# Clean plot labels table
# ============================================================

plot_labels_clean <- label_table %>%
  distinct(variable, .keep_all = TRUE)

# ============================================================
# Attach labels, domains, and domain colours
# ============================================================

unified <- unified %>%
  left_join(
    plot_labels_clean %>%
      select(variable, plot_label, domain, domain_color),
    by = "variable"
  ) %>%
  mutate(
    plot_label   = as.character(plot_label),
    domain       = trimws(as.character(domain)),
    domain_color = as.character(domain_color)
  )

# ============================================================
# Checks
# ============================================================

missing_domains <- unified %>%
  filter(is.na(domain) | domain == "") %>%
  distinct(variable)

if (nrow(missing_domains) > 0) {
  cat("\nVariables in results but missing domain in plot_labels:\n")
  print(missing_domains$variable)
}

missing_plot_labels <- unified %>%
  filter(is.na(plot_label) | plot_label == "") %>%
  distinct(variable)

if (nrow(missing_plot_labels) > 0) {
  cat("\nVariables in results but missing plot_label in plot_labels:\n")
  print(missing_plot_labels$variable)
}

missing_domain_colors <- unified %>%
  filter(is.na(domain_color) | domain_color == "") %>%
  distinct(variable)

if (nrow(missing_domain_colors) > 0) {
  cat("\nVariables in results but missing domain_color in plot_labels:\n")
  print(missing_domain_colors$variable)
}

unified <- unified %>%
  filter(!is.na(domain), domain != "")

# ============================================================
# Optional x-axis caps by domain
# ============================================================

xcap_map <- list(
  "Demographics & Socioeconomic" = 1.5,
  "Lifestyle"                    = 1.5,
  "Clinical"                     = 2.0,
  "Biomarkers"                   = 2.0,
  "Biomarkers II"                = 2.0,
  "Biomarkers III"               = 2.0,
  "Environment"                  = 1.5,
  "Medication"                   = 2.0,
  "Medications"                  = 2.0
)

# ============================================================
# Helper: make safe file name from domain
# ============================================================

make_file_stub <- function(x) {
  x %>%
    tolower() %>%
    gsub("&", "and", ., fixed = TRUE) %>%
    gsub("[^a-z0-9]+", "_", .) %>%
    gsub("^_+|_+$", "", .)
}

# ============================================================
# Helper: split a domain by VARIABLE blocks
# Keeps all rows of one variable on the same page
# max_rows_per_page controls how many total rows fit per page
# ============================================================

split_domain_by_variable_blocks <- function(plot_data, vars_in_order, max_rows_per_page = 30) {
  
  plot_data <- plot_data %>%
    mutate(variable = as.character(variable))
  
  vars_present <- vars_in_order[vars_in_order %in% unique(plot_data$variable)]
  
  if (length(vars_present) == 0) {
    return(list())
  }
  
  var_blocks <- lapply(vars_present, function(v) {
    plot_data %>%
      filter(variable == v) %>%
      arrange(level_order, level)
  })
  names(var_blocks) <- vars_present
  
  pages <- list()
  current_page <- NULL
  current_rows <- 0
  
  for (v in vars_present) {
    block <- var_blocks[[v]]
    block_n <- nrow(block)
    
    if (is.null(current_page)) {
      current_page <- block
      current_rows <- block_n
      next
    }
    
    if ((current_rows + block_n) <= max_rows_per_page) {
      current_page <- bind_rows(current_page, block)
      current_rows <- current_rows + block_n
    } else {
      pages[[length(pages) + 1]] <- current_page
      current_page <- block
      current_rows <- block_n
    }
  }
  
  if (!is.null(current_page) && nrow(current_page) > 0) {
    pages[[length(pages) + 1]] <- current_page
  }
  
  pages
}

# ============================================================
# Three-panel forest plot function
# Returns a plot object; saves only if filename is supplied
# ============================================================

make_subsample_forest_plot <- function(
    res_df,
    vars,
    title,
    filename = NULL,
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
  
  # ------------------------------------------------------------
  # Helpers
  # ------------------------------------------------------------
  
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
    var_chars   <- if (length(var_labels)   == 0) 1 else max(nchar(var_labels),   na.rm = TRUE)
    level_chars <- if (length(level_labels) == 0) 1 else max(nchar(level_labels), na.rm = TRUE)
    
    gap_chars <- 0.1
    
    var_x   <- var_chars
    level_x <- var_x + gap_chars + level_chars
    
    max_x <- max(var_x, level_x)
    
    left_xlim <- c(0, max_x + 2)
    
    list(
      var_x = var_x,
      level_x = level_x,
      left_xlim = left_xlim,
      width_weight = max(12, max_x + 2)
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
  
  # ------------------------------------------------------------
  # Prepare plotting data
  # ------------------------------------------------------------
  
  forest_data <- res_df %>%
    filter(as.character(variable) %in% vars, !is.na(OR)) %>%
    filter(is.finite(OR), is.finite(LCL), is.finite(UCL)) %>%
    mutate(
      variable_raw_chr = as.character(variable),
      variable_label = ifelse(
        is.na(plot_label) | plot_label == "",
        variable_raw_chr,
        plot_label
      ),
      var_type = case_when(
        variable_type == "continuous"  ~ "continuous",
        variable_type == "categorical" ~ "categorical",
        TRUE                           ~ as.character(variable_type)
      ),
      level_display = case_when(
        var_type == "continuous"       ~ "",
        is.na(level) | level == ""     ~ "",
        TRUE                           ~ as.character(level)
      ),
      domain = ifelse(is.na(domain) | domain == "", "Other", as.character(domain)),
      domain_color = ifelse(
        is.na(domain_color) | domain_color == "",
        "#F0F0F0",
        as.character(domain_color)
      ),
      ref_level = ifelse(is.na(ref_level), "", ref_level),
      stable_direction = case_when(
        round(LCL, 2) > null_x ~ "IQR excludes 1",
        round(UCL, 2) < null_x ~ "IQR excludes 1",
        TRUE                   ~ "IQR crosses 1"
      )
    )
  
  if (nrow(forest_data) == 0) {
    stop("No model terms found to plot.")
  }
  
  # ------------------------------------------------------------
  # Row ordering
  # ------------------------------------------------------------
  
  forest_data <- forest_data %>%
    mutate(
      domain = factor(
        domain,
        levels = unique(c(domain_order, setdiff(unique(domain), domain_order)))
      ),
      variable = factor(variable, levels = vars)
    ) %>%
    arrange(domain, variable, level_order, level_display)
  
  forest_data <- forest_data %>%
    mutate(plot_row = row_number())
  
  n_rows <- nrow(forest_data)
  
  forest_data <- forest_data %>%
    mutate(y_id = rev(seq_len(n_rows)))
  
  # ------------------------------------------------------------
  # Forest x-limits / breaks
  # ------------------------------------------------------------
  
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
  
  # ------------------------------------------------------------
  # Cap CI to plotting window
  # ------------------------------------------------------------
  
  forest_data <- forest_data %>%
    mutate(
      UCL_plot = pmin(UCL, x_right_forest),
      LCL_plot = pmax(LCL, x_left_forest),
      label_txt = paste0(
        sprintf("%.2f", OR), " (",
        sprintf("%.2f", LCL), "-",
        sprintf("%.2f", UCL), ")"
      )
    )
  
  # ------------------------------------------------------------
  # Domain bands
  # ------------------------------------------------------------
  
  domain_bands <- forest_data %>%
    group_by(domain, domain_color) %>%
    summarise(
      ymin = min(y_id) - 0.5,
      ymax = max(y_id) + 0.5,
      .groups = "drop"
    ) %>%
    mutate(domain = as.character(domain))
  
  fill_values <- setNames(domain_bands$domain_color, domain_bands$domain)
  
  # ------------------------------------------------------------
  # Variable and level text tables
  # ------------------------------------------------------------
  
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
  
  # ------------------------------------------------------------
  # Layout widths
  # ------------------------------------------------------------
  
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
  
  # ------------------------------------------------------------
  # Left panel
  # ------------------------------------------------------------
  
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
  
  # ------------------------------------------------------------
  # Middle panel
  # ------------------------------------------------------------
  
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
        "IQR crosses 1"  = "grey60"
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
      subtitle = paste(
        "Adjusted for age at recruitment, sex, and ethnicity",
        "Continuous: OR per 1 SD increase | Categorical: OR vs reference level",
        sep = "\n"
      ),
      x = "Odds ratio",
      y = NULL
    ) +
    theme_minimal(base_size = 11) +
    theme(
      plot.title = element_text(
        face = "bold",
        size = 27,
        hjust = 0.5,
        margin = margin(b = 6)
      ),
      plot.subtitle = element_text(
        size = 16,
        hjust = 0.5,
        colour = "grey30",
        margin = margin(b = 15)
      ),
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
  
  # ------------------------------------------------------------
  # Right panel
  # ------------------------------------------------------------
  
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
  
  # ------------------------------------------------------------
  # Combine panels
  # ------------------------------------------------------------
  
  p <- left_plot + forest_plot + right_plot +
    plot_layout(widths = panel_widths)
  
  if (!is.null(filename)) {
    pdf(
      file.path(output_dir, filename),
      width = pdf_width,
      height = max(min_pdf_height, nrow(forest_data) * row_height + 4)
    )
    print(p)
    dev.off()
    cat("Saved:", file.path(output_dir, filename), "\n")
  }
  
  invisible(p)
}

# ============================================================
# Domain order for output
# ============================================================

domains_ordered <- plot_labels_clean %>%
  filter(!is.na(domain), domain != "") %>%
  pull(domain) %>%
  unique()

# ============================================================
# Plot one PDF per domain, split across pages by variable blocks
# Change this value to control how many rows fit on one page
# ============================================================

max_rows_per_page <- 30

for (dom in domains_ordered) {
  
  cat("\n============================================================\n")
  cat("Plotting domain:", dom, "\n")
  cat("============================================================\n")
  
  plot_data <- unified %>%
    filter(domain == dom)
  
  if (nrow(plot_data) == 0) {
    cat("  SKIPPING — no data found for this domain.\n")
    next
  }
  
  vars_in_domain <- label_table %>%
    filter(domain == dom) %>%
    pull(variable) %>%
    unique()
  
  vars_in_domain <- intersect(vars_in_domain, unique(plot_data$variable))
  
  if (length(vars_in_domain) == 0) {
    cat("  SKIPPING — no labelled variables found for this domain.\n")
    next
  }
  
  plot_data <- plot_data %>%
    mutate(
      variable = as.character(variable)
    ) %>%
    filter(variable %in% vars_in_domain) %>%
    mutate(
      variable = factor(variable, levels = vars_in_domain)
    ) %>%
    arrange(variable, level_order, level)
  
  page_list <- split_domain_by_variable_blocks(
    plot_data = plot_data,
    vars_in_order = vars_in_domain,
    max_rows_per_page = max_rows_per_page
  )
  
  if (length(page_list) == 0) {
    cat("  SKIPPING — nothing to plot after page split.\n")
    next
  }
  
  file_stub <- make_file_stub(dom)
  pdf_file <- file.path(output_dir, paste0("forest_", file_stub, ".pdf"))
  
  pdf(pdf_file, width = 22, height = 14)
  
  for (i in seq_along(page_list)) {
    plot_chunk <- page_list[[i]]
    vars_chunk <- unique(as.character(plot_chunk$variable))
    
    page_title <- dom
    
    p <- make_subsample_forest_plot(
      res_df     = plot_chunk,
      vars       = vars_chunk,
      title      = page_title,
      filename   = NULL,
      output_dir = output_dir,
      x_cap      = xcap_map[[dom]],
      row_height = 0.48,
      pdf_width  = 22,
      min_pdf_height = 10
    )
    
    print(p)
  }
  
  dev.off()
  cat("Saved:", pdf_file, "\n")
}

cat("\n============================================================\n")
cat("ALL DOMAIN PDFs COMPLETE\n")
cat("============================================================\n")