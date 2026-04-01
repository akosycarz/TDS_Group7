# ============================================================
# COMPARE ROC CURVES:
# 1) Base model
# 2) LASSO-selected model
# 3) Elastic-net-selected model
# 4) XGBoost txt-selected model
# ============================================================

library(readr)
library(dplyr)
library(ggplot2)
library(pROC)

set.seed(123)

# ============================================================
# 0. INPUTS
# ============================================================

output_dir <- "../outputs"
if (!dir.exists(output_dir)) {
  dir.create(output_dir, recursive = TRUE)
}

base_vars <- c("age_at_recruitment", "sex", "eth_bg")

lasso_stable_vars <- read_csv(
  file.path(output_dir, "model1_lasso_stable_variables.csv"),
  show_col_types = FALSE
)

elastic_stable_vars <- read_csv(
  file.path(output_dir, "model1_stable_variables.csv"),
  show_col_types = FALSE
)

# XGBoost-selected variables from txt file
xgb_txt_file <- "../outputs/XGBoost_results/selected_features.txt"

xgb_lines <- readLines(xgb_txt_file, warn = FALSE)

# Extract variable names from lines like:
# 1. age_at_recruitment    SHAP=0.594340   Cum%=93.9%
xgb_selected_vars <- sub("^\\s*\\d+\\.\\s+([A-Za-z0-9_]+).*", "\\1", xgb_lines)

# Keep only numbered variable lines
xgb_selected_vars <- xgb_selected_vars[
  grepl("^\\s*\\d+\\.\\s+[A-Za-z0-9_]+", xgb_lines)
]

# Keep first 13 variables only
xgb_selected_vars <- xgb_selected_vars[1:13]

lasso_selected_vars <- lasso_stable_vars %>%
  distinct(base_var, .keep_all = TRUE) %>%
  arrange(desc(selection_proportion)) %>%
  pull(base_var)

elastic_selected_vars <- elastic_stable_vars %>%
  distinct(base_var, .keep_all = TRUE) %>%
  arrange(desc(selection_proportion)) %>%
  pull(base_var)

lasso_model_vars   <- unique(c(base_vars, lasso_selected_vars))
elastic_model_vars <- unique(c(base_vars, elastic_selected_vars))
xgb_model_vars     <- unique(c(base_vars, xgb_selected_vars))

all_needed_vars <- unique(c(
  base_vars,
  lasso_model_vars,
  elastic_model_vars,
  xgb_model_vars,
  "outcome"
))

cat("\nBase variables:\n")
print(base_vars)

cat("\nLASSO-selected variables:\n")
print(lasso_selected_vars)

cat("\nElastic-net-selected variables:\n")
print(elastic_selected_vars)

cat("\nXGBoost txt-selected variables:\n")
print(xgb_selected_vars)

# ============================================================
# 1. LOAD DATA
# ============================================================

refit_df <- readRDS(file.path(output_dir, "ukb_refit_20_imputed.rds"))
test_df  <- readRDS(file.path(output_dir, "ukb_test_20_imputed.rds"))

refit_df$y <- ifelse(trimws(as.character(refit_df$outcome)) == "No", 0L, 1L)
test_df$y  <- ifelse(trimws(as.character(test_df$outcome)) == "No", 0L, 1L)

# Keep only variables that actually exist in both datasets
base_vars <- base_vars[
  base_vars %in% names(refit_df) & base_vars %in% names(test_df)
]

lasso_model_vars <- lasso_model_vars[
  lasso_model_vars %in% names(refit_df) & lasso_model_vars %in% names(test_df)
]

elastic_model_vars <- elastic_model_vars[
  elastic_model_vars %in% names(refit_df) & elastic_model_vars %in% names(test_df)
]

xgb_model_vars <- xgb_model_vars[
  xgb_model_vars %in% names(refit_df) & xgb_model_vars %in% names(test_df)
]

cat("\nVariables actually available in both datasets:\n")
cat("Base:", paste(base_vars, collapse = ", "), "\n")
cat("LASSO:", paste(lasso_model_vars, collapse = ", "), "\n")
cat("Elastic net:", paste(elastic_model_vars, collapse = ", "), "\n")
cat("XGBoost txt:", paste(xgb_model_vars, collapse = ", "), "\n")

# ============================================================
# 2. ALIGN FACTOR LEVELS
# ============================================================

all_model_vars <- unique(c(
  base_vars,
  lasso_model_vars,
  elastic_model_vars,
  xgb_model_vars
))

for (v in all_model_vars) {
  if (v %in% names(refit_df) && (is.character(refit_df[[v]]) || is.factor(refit_df[[v]]))) {
    refit_df[[v]] <- factor(refit_df[[v]])
  }
  if (v %in% names(test_df) && (is.character(test_df[[v]]) || is.factor(test_df[[v]]))) {
    test_df[[v]] <- factor(test_df[[v]])
  }
}

for (v in all_model_vars) {
  if (v %in% names(refit_df) && v %in% names(test_df) && is.factor(refit_df[[v]])) {
    test_df[[v]] <- factor(test_df[[v]], levels = levels(refit_df[[v]]))
  }
}

# ============================================================
# 3. HELPER TO FIT MODEL AND COMPUTE ROC
# ============================================================

fit_and_roc <- function(model_vars, model_name, refit_df, test_df) {
  
  form <- as.formula(
    paste("y ~", paste(model_vars, collapse = " + "))
  )
  
  fit <- glm(form, data = refit_df, family = "binomial")
  
  pred <- predict(fit, newdata = test_df, type = "response")
  
  eval_df <- data.frame(
    y = test_df$y,
    pred_prob = pred
  ) %>%
    filter(!is.na(y), !is.na(pred_prob))
  
  roc_obj <- roc(eval_df$y, eval_df$pred_prob, quiet = TRUE)
  auc_val <- as.numeric(auc(roc_obj))
  auc_ci  <- as.numeric(ci.auc(roc_obj))
  
  roc_df <- data.frame(
    fpr = 1 - roc_obj$specificities,
    tpr = roc_obj$sensitivities,
    model = model_name
  )
  
  list(
    model_name = model_name,
    formula = form,
    fit = fit,
    roc_obj = roc_obj,
    roc_df = roc_df,
    auc = auc_val,
    auc_low = auc_ci[1],
    auc_high = auc_ci[3]
  )
}

# ============================================================
# 4. FIT FOUR MODELS
# ============================================================

base_res <- fit_and_roc(
  model_vars = base_vars,
  model_name = "Base",
  refit_df = refit_df,
  test_df = test_df
)

lasso_res <- fit_and_roc(
  model_vars = lasso_model_vars,
  model_name = "LASSO",
  refit_df = refit_df,
  test_df = test_df
)

elastic_res <- fit_and_roc(
  model_vars = elastic_model_vars,
  model_name = "Elastic net",
  refit_df = refit_df,
  test_df = test_df
)

xgb_res <- fit_and_roc(
  model_vars = xgb_model_vars,
  model_name = "XGBoost txt",
  refit_df = refit_df,
  test_df = test_df
)

# ============================================================
# 5. PRINT AUC SUMMARY
# ============================================================

auc_summary <- bind_rows(
  data.frame(
    model = base_res$model_name,
    auc = base_res$auc,
    auc_low = base_res$auc_low,
    auc_high = base_res$auc_high
  ),
  data.frame(
    model = lasso_res$model_name,
    auc = lasso_res$auc,
    auc_low = lasso_res$auc_low,
    auc_high = lasso_res$auc_high
  ),
  data.frame(
    model = elastic_res$model_name,
    auc = elastic_res$auc,
    auc_low = elastic_res$auc_low,
    auc_high = elastic_res$auc_high
  ),
  data.frame(
    model = xgb_res$model_name,
    auc = xgb_res$auc,
    auc_low = xgb_res$auc_low,
    auc_high = xgb_res$auc_high
  )
)

cat("\n=== Test-set AUC summary ===\n")
print(auc_summary)

write_csv(
  auc_summary,
  file.path(output_dir, "model_comparison_auc_summary.csv")
)

# ============================================================
# 6. COMBINED ROC PLOT
# ============================================================

roc_plot_df <- bind_rows(
  base_res$roc_df,
  lasso_res$roc_df,
  elastic_res$roc_df,
  xgb_res$roc_df
)

auc_label <- paste0(
  "Base: AUC = ", sprintf("%.3f", base_res$auc),
  " (", sprintf("%.3f", base_res$auc_low), "–", sprintf("%.3f", base_res$auc_high), ")\n",
  "LASSO: AUC = ", sprintf("%.3f", lasso_res$auc),
  " (", sprintf("%.3f", lasso_res$auc_low), "–", sprintf("%.3f", lasso_res$auc_high), ")\n",
  "Elastic net: AUC = ", sprintf("%.3f", elastic_res$auc),
  " (", sprintf("%.3f", elastic_res$auc_low), "–", sprintf("%.3f", elastic_res$auc_high), ")\n",
  "XGBoost txt: AUC = ", sprintf("%.3f", xgb_res$auc),
  " (", sprintf("%.3f", xgb_res$auc_low), "–", sprintf("%.3f", xgb_res$auc_high), ")"
)

p_roc_compare <- ggplot(roc_plot_df, aes(x = fpr, y = tpr, colour = model)) +
  geom_line(linewidth = 1.2) +
  geom_abline(linetype = "dashed", colour = "grey50") +
  annotate(
    "text",
    x = 0.72, y = 0.05,
    label = auc_label,
    hjust = 0,
    vjust = 0,
    size = 4
  ) +
  labs(
    title = "ROC Curve Comparison",
    x = "False Positive Rate",
    y = "True Positive Rate",
    colour = "Model"
  ) +
  theme_minimal(base_size = 12) +
  theme(
    plot.title = element_text(hjust = 0.5, face = "bold"),
    legend.position = "bottom"
  )

print(p_roc_compare)

ggsave(
  filename = file.path(output_dir, "model_comparison_roc.png"),
  plot = p_roc_compare,
  width = 7,
  height = 6,
  dpi = 300
)

cat("\nSaved:", file.path(output_dir, "model_comparison_roc.png"), "\n")

# ============================================================
# 7. OPTIONAL: SAVE ROC POINTS TOO
# ============================================================

write_csv(
  roc_plot_df,
  file.path(output_dir, "model_comparison_roc_points.csv")
)

cat("Saved:", file.path(output_dir, "model_comparison_auc_summary.csv"), "\n")
cat("Saved:", file.path(output_dir, "model_comparison_roc_points.csv"), "\n")

