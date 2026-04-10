# ============================================================
# Full Exposure PCA Analysis — UKB data (all variables)
# Uses prcomp with dummy encoding for categorical variables
# ============================================================
library(ggplot2)
library(dplyr)
library(tidyr)
library(tibble)

# ------------------------------------------------------------
# 1. Load data
# ------------------------------------------------------------
final_imputed <- readRDS("../outputs/ukb_selection_60_imputed.rds")

# ------------------------------------------------------------
# 2. Recode outcome
# ------------------------------------------------------------
outcome_raw <- trimws(as.character(final_imputed$outcome))
final_imputed$outcome <- dplyr::case_when(
  is.na(outcome_raw) | outcome_raw == "" ~ NA_character_,
  outcome_raw == "No"                    ~ "No",
  TRUE                                   ~ "Yes"
)
cat("Outcome distribution after recoding:\n")
print(table(final_imputed$outcome, useNA = "ifany"))
cat("\n")

# ------------------------------------------------------------
# 3. Define columns to exclude from PCA
# ------------------------------------------------------------
target_outcome <- "outcome"

if (!target_outcome %in% names(final_imputed)) {
  stop(paste("Outcome column not found:", target_outcome))
}

exclude_vars <- unique(c(
  target_outcome,
  grep("_yn$", names(final_imputed), value = TRUE),
  "eid", "id", "f.eid",
  "age_at_recruitment",
  "sex", "eth_bg"
))
exclude_vars <- exclude_vars[exclude_vars %in% names(final_imputed)]

all_vars <- setdiff(names(final_imputed), exclude_vars)
cat("Variables selected for PCA:", length(all_vars), "\n\n")

# ------------------------------------------------------------
# 4. Handle missing data
#    Data is already imputed so complete.cases should keep most rows.
#    If not, fall back to dropping high-missingness columns.
# ------------------------------------------------------------
complete_rows <- complete.cases(final_imputed[, all_vars])
cat("Rows with complete data:", sum(complete_rows), "of", nrow(final_imputed), "\n")

if (sum(complete_rows) < 100) {
  cat("\nWARNING: Very few complete cases. Dropping variables with >20% missing instead.\n")
  missing_pct <- colMeans(is.na(final_imputed[, all_vars]))
  all_vars    <- all_vars[missing_pct <= 0.20]
  cat("Variables retained:", length(all_vars), "\n")
  complete_rows <- complete.cases(final_imputed[, all_vars])
  cat("Rows after relaxed filter:", sum(complete_rows), "\n")
}

exp_data      <- final_imputed[complete_rows, ]
analysis_data <- exp_data[, all_vars, drop = FALSE]
cat("Final dataset:", nrow(analysis_data), "rows x", length(all_vars), "variables\n\n")

# ------------------------------------------------------------
# 5. Prepare variables
# ------------------------------------------------------------
# Convert characters to factors
analysis_data <- analysis_data %>%
  mutate(across(where(is.character), as.factor))

# Report types
num_vars <- names(analysis_data)[sapply(analysis_data, is.numeric)]
cat_vars <- names(analysis_data)[sapply(analysis_data, is.factor)]
cat("Numeric variables:   ", length(num_vars), "\n")
cat("Categorical variables:", length(cat_vars), "\n\n")

# Drop single-level factors
single_level <- sapply(analysis_data, function(x) is.factor(x) && nlevels(x) < 2)
if (any(single_level)) {
  cat("Dropping single-level factor(s):",
      paste(names(analysis_data)[single_level], collapse = ", "), "\n")
  analysis_data <- analysis_data[, !single_level, drop = FALSE]
}

# Drop zero-variance / all-NA numerics
zero_var <- sapply(analysis_data, function(x) {
  if (!is.numeric(x)) return(FALSE)
  v <- var(x, na.rm = TRUE)
  isTRUE(is.na(v) || v == 0)
})
if (any(zero_var)) {
  cat("Dropping zero-variance numeric(s):",
      paste(names(analysis_data)[zero_var], collapse = ", "), "\n")
  analysis_data <- analysis_data[, !zero_var, drop = FALSE]
}

# ------------------------------------------------------------
# 6. Dummy-encode categorical variables
# ------------------------------------------------------------
pca_matrix <- model.matrix(~ . - 1, data = analysis_data)

# Remove any constant columns produced by dummy encoding
col_var       <- apply(pca_matrix, 2, var)
constant_cols <- is.na(col_var) | col_var == 0
if (any(constant_cols)) {
  cat("Removing", sum(constant_cols), "constant column(s) after dummy encoding:",
      paste(colnames(pca_matrix)[constant_cols], collapse = ", "), "\n")
  pca_matrix <- pca_matrix[, !constant_cols, drop = FALSE]
}

cat("\npca_matrix dimensions:", nrow(pca_matrix), "rows x", ncol(pca_matrix), "cols\n")
cat("  Original numeric columns :", length(num_vars), "\n")
cat("  Dummy-encoded columns    :", ncol(pca_matrix) - length(num_vars), "\n\n")

if (ncol(pca_matrix) == 0) stop("All columns removed as constant — check your data.")
if (nrow(pca_matrix) == 0) stop("No rows remaining after filtering — check your data.")

# ------------------------------------------------------------
# 7. Run PCA
# ------------------------------------------------------------
cat("Running PCA...\n")
pca <- prcomp(pca_matrix, scale. = TRUE)
cat("PCA complete.\n\n")

pct        <- round(100 * pca$sdev^2 / sum(pca$sdev^2), 1)
cum_pct    <- cumsum(pct)
dim1_label <- paste0("PC1 (", pct[1], "%)")
dim2_label <- paste0("PC2 (", pct[2], "%)")

# ------------------------------------------------------------
# 8. Build scores data frame
# ------------------------------------------------------------
scores        <- as.data.frame(pca$x[, 1:2])
names(scores) <- c("PC1", "PC2")

scores$outcome <- factor(
  dplyr::case_when(
    exp_data[[target_outcome]] == "No"  ~ "Control",
    exp_data[[target_outcome]] == "Yes" ~ "Case",
    TRUE                                ~ NA_character_
  ),
  levels = c("Control", "Case")
)
scores$sex    <- factor(exp_data$sex, levels = c("Female", "Male"))
scores$eth_bg <- factor(exp_data$eth_bg)
scores$age    <- exp_data$age_at_recruitment

cat("Outcome distribution in PCA scores:\n")
print(table(scores$outcome, useNA = "ifany"))
cat("\nSex distribution:\n")
print(table(scores$sex, useNA = "ifany"))
cat("\n")

# ------------------------------------------------------------
# 9. Output directory & shared theme
# ------------------------------------------------------------
out_dir  <- "../outputs/summary/PCA_results"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

pca_theme <- theme_bw(base_size = 14) +
  theme(
    plot.title      = element_text(face = "bold", size = 16),
    plot.subtitle   = element_text(size = 11, colour = "grey40"),
    legend.position = "right",
    panel.grid      = element_blank(),
    axis.title      = element_text(size = 13)
  )

# ------------------------------------------------------------
# Figure 1 — Case vs Control
# ------------------------------------------------------------
scores_plot1 <- scores[!is.na(scores$outcome), ]
cat("Cases:   ", sum(scores_plot1$outcome == "Case"), "\n")
cat("Controls:", sum(scores_plot1$outcome == "Control"), "\n")

p1 <- ggplot(scores_plot1, aes(PC1, PC2, colour = outcome)) +
  geom_point(data = scores_plot1[scores_plot1$outcome == "Control", ],
             alpha = 0.4, size = 0.7) +
  geom_point(data = scores_plot1[scores_plot1$outcome == "Case", ],
             alpha = 0.4, size = 0.7) +
  scale_colour_manual(
    values = c("Control" = "#457B9D", "Case" = "#E63946"),
    name   = "Status"
  ) +
  labs(
    title    = paste0("PCA coloured by Case vs Control (", target_outcome, ")"),
    subtitle = "Do cases cluster differently in exposure space?",
    x = dim1_label, y = dim2_label
  ) +
  pca_theme

ggsave(file.path(out_dir, "pca_case_control.png"), p1, width = 8, height = 6, dpi = 300)

# ------------------------------------------------------------
# Figure 2 — Sex
# ------------------------------------------------------------
p2 <- ggplot(scores[!is.na(scores$sex), ], aes(PC1, PC2, colour = sex)) +
  geom_point(alpha = 0.4, size = 0.8) +
  scale_colour_manual(
    values = c("Female" = "#E9C46A", "Male" = "#2A9D8F"),
    name   = "Sex"
  ) +
  labs(
    title    = "PCA coloured by Sex",
    subtitle = "Does biological sex explain exposure variance?",
    x = dim1_label, y = dim2_label
  ) +
  pca_theme

ggsave(file.path(out_dir, "pca_sex.png"), p2, width = 8, height = 6, dpi = 300)

# ------------------------------------------------------------
# Figure 3 — Age
# ------------------------------------------------------------
p3 <- ggplot(scores[!is.na(scores$age), ], aes(PC1, PC2, colour = age)) +
  geom_point(alpha = 0.4, size = 0.8) +
  scale_colour_viridis_c(name = "Age", option = "plasma") +
  labs(
    title    = "PCA coloured by Age at Recruitment",
    subtitle = "Does age drive exposure variation?",
    x = dim1_label, y = dim2_label
  ) +
  pca_theme

ggsave(file.path(out_dir, "pca_age.png"), p3, width = 8, height = 6, dpi = 300)

# ------------------------------------------------------------
# Figure 4 — Ethnicity
# ------------------------------------------------------------
eth_palette <- c("#E63946","#457B9D","#2A9D8F","#E9C46A","#F4A261",
                 "#9B2226","#6A4C93","#52B788","#264653","#A8DADC")

p4 <- ggplot(scores[!is.na(scores$eth_bg), ], aes(PC1, PC2, colour = eth_bg)) +
  geom_point(alpha = 0.4, size = 0.8) +
  scale_colour_manual(values = eth_palette, name = "Ethnicity") +
  labs(
    title    = "PCA coloured by Ethnicity",
    subtitle = "Population structure in exposure space",
    x = dim1_label, y = dim2_label
  ) +
  pca_theme +
  guides(colour = guide_legend(override.aes = list(size = 3, alpha = 1)))

ggsave(file.path(out_dir, "pca_ethnicity.png"), p4, width = 9, height = 6, dpi = 300)

# ------------------------------------------------------------
# Figure 5 — Scree plot
# ------------------------------------------------------------
n_show <- min(20, length(pct))

var_df <- data.frame(
  PC         = seq_along(pct),
  variance   = pct,
  cumulative = cum_pct
)

p5a <- ggplot(var_df[1:n_show, ], aes(PC, variance)) +
  geom_col(fill = "#457B9D", width = 0.7) +
  geom_line(colour = "#E63946", linewidth = 0.8) +
  geom_point(colour = "#E63946", size = 2) +
  scale_x_continuous(breaks = 1:n_show) +
  scale_y_continuous(labels = function(x) paste0(x, "%")) +
  labs(
    title    = "Scree Plot",
    subtitle = paste0("All variables after dummy encoding (", ncol(pca_matrix), " columns)"),
    x = "Principal Component", y = "Variance Explained (%)"
  ) +
  pca_theme

# ------------------------------------------------------------
# Figure 6 — Cumulative variance
# ------------------------------------------------------------
p5b <- ggplot(var_df[1:n_show, ], aes(PC, cumulative)) +
  geom_line(colour = "#457B9D", linewidth = 1) +
  geom_point(colour = "#457B9D", size = 2) +
  geom_hline(yintercept = c(70, 80, 90),
             linetype = "dashed", colour = "grey60", linewidth = 0.6) +
  annotate("text", x = n_show, y = c(71, 81, 91),
           label = c("70%", "80%", "90%"),
           hjust = 1, size = 3.5, colour = "grey40") +
  scale_x_continuous(breaks = 1:n_show) +
  scale_y_continuous(limits = c(0, 100), labels = function(x) paste0(x, "%")) +
  labs(
    title    = "Cumulative Variance Explained",
    subtitle = "Dashed lines at 70%, 80%, 90% thresholds",
    x = "Principal Component", y = "Cumulative Variance (%)"
  ) +
  pca_theme

ggsave(file.path(out_dir, "scree_plot.png"),          p5a, width = 9, height = 5, dpi = 300)
ggsave(file.path(out_dir, "cumulative_variance.png"), p5b, width = 9, height = 5, dpi = 300)

# ------------------------------------------------------------
# Figure 7 — Loadings plot (top 20 per component)
# ------------------------------------------------------------
loadings_df <- as.data.frame(pca$rotation[, 1:2]) %>%
  rownames_to_column("variable") %>%
  pivot_longer(cols = c(PC1, PC2), names_to = "component", values_to = "loading") %>%
  mutate(
    component = case_when(
      component == "PC1" ~ dim1_label,
      component == "PC2" ~ dim2_label
    ),
    direction = ifelse(loading >= 0, "Positive", "Negative")
  )

loadings_top <- loadings_df %>%
  group_by(component) %>%
  slice_max(abs(loading), n = 20) %>%
  mutate(variable = reorder(variable, loading)) %>%
  ungroup()

p7 <- ggplot(loadings_top, aes(loading, variable, fill = direction)) +
  geom_col(show.legend = FALSE) +
  geom_vline(xintercept = 0, linewidth = 0.5, colour = "grey30") +
  scale_fill_manual(values = c("Positive" = "#457B9D", "Negative" = "#E63946")) +
  facet_wrap(~ component, scales = "free") +
  labs(
    title    = "PCA — Top 20 Variable Loadings per Component",
    subtitle = "Blue = positive loading  |  Red = negative loading",
    x = "Loading", y = NULL
  ) +
  pca_theme +
  theme(
    strip.text       = element_text(face = "bold", size = 13),
    strip.background = element_rect(fill = "grey92"),
    axis.text.y      = element_text(size = 10)
  )

ggsave(file.path(out_dir, "loadings_plot.png"), p7, width = 12, height = 8, dpi = 300)

# ------------------------------------------------------------
# Save supporting CSVs
# ------------------------------------------------------------
write.csv(var_df,
          file.path(out_dir, "pca_variance_explained.csv"), row.names = FALSE)

write.csv(as.data.frame(pca$rotation),
          file.path(out_dir, "pca_loadings_all.csv"), row.names = TRUE)

write.csv(as.data.frame(pca$x[, 1:min(5, ncol(pca$x))]),
          file.path(out_dir, "pca_scores_first5PCs.csv"), row.names = TRUE)

# ------------------------------------------------------------
# Console summary
# ------------------------------------------------------------
cat("\n=== Full-Variable PCA Summary ===\n")
cat("Outcome variable:          ", target_outcome, "\n")
cat("Original variables:        ", length(all_vars), "\n")
cat("  Numeric:                 ", length(num_vars), "\n")
cat("  Categorical:             ", length(cat_vars), "\n")
cat("Columns after dummy enc.:  ", ncol(pca_matrix), "\n")
cat("Complete-case rows:        ", nrow(pca_matrix), "\n\n")
cat("Variance explained:\n")
cat("  PC1:                     ", pct[1], "%\n")
cat("  PC2:                     ", pct[2], "%\n")
cat("  PC1 + PC2:               ", sum(pct[1:2]), "%\n")
cat("  First 5 PCs:             ", sum(pct[1:min(5,  length(pct))]), "%\n")
cat("  First 10 PCs:            ", sum(pct[1:min(10, length(pct))]), "%\n\n")
cat("Files saved to:", out_dir, "\n")
cat("\nFigures produced:\n")
cat("  pca_case_control.png\n")
cat("  pca_sex.png\n")
cat("  pca_age.png\n")
cat("  pca_ethnicity.png\n")
cat("  scree_plot.png\n")
cat("  cumulative_variance.png\n")
cat("  loadings_plot.png\n")
