# ============================================================
# SUBSAMPLE STABILITY FOREST PLOT FOR XGBOOST SHAP-SELECTED MODEL
# Refit logistic model 100 times on random 50% subsamples
# Plot median OR and IQR only
# Also produce cumulative incremental AUC plot
#
# TOP_N is set dynamically as:
#   max(n_stable_total from Lasso, n_stable_total from Elastic Net)
# Features are taken from XGBoost SHAP importance ranking
# ============================================================

library(readr)
library(dplyr)
library(stringr)
library(pROC)

# Shared plot functions (forest plot + incremental AUC)
# Resolve path relative to this script's own directory
source("7.6-plot_functions.R")

set.seed(123)

# ============================================================
# 0. INPUTS
# ============================================================

output_dir <- "../outputs/summary"

# Determine TOP_N dynamically: max of Lasso and Elastic Net stable feature counts
read_n_stable <- function(path) {
  tryCatch(
    as.integer(read_csv(path, show_col_types = FALSE)$n_stable_total[1]),
    error = function(e) { message("Could not read: ", path); 0L }
  )
}

lasso_n   <- read_n_stable("../outputs/summary/model1_lasso_stability_summary.csv")
elastic_n <- read_n_stable("../outputs/summary/model1_stability_summary.csv")
TOP_N     <- max(lasso_n, elastic_n)

if (TOP_N == 0L) {
  TOP_N <- 20L
  message("[WARN] Could not read stability summaries — using fallback TOP_N = ", TOP_N)
} else {
  message("TOP_N set dynamically:")
  message("  Lasso        n_stable_total = ", lasso_n)
  message("  Elastic Net  n_stable_total = ", elastic_n)
  message("  TOP_N = max(", lasso_n, ", ", elastic_n, ") = ", TOP_N)
}

# Load SHAP importance and take top TOP_N features
shap_df <- read_csv("../outputs/summary/XGBoost_results/shap_importance.csv",
                    show_col_types = FALSE)

shap_top <- shap_df %>%
  arrange(Rank) %>%
  slice_head(n = TOP_N) %>%
  pull(Feature)

cat("Top", TOP_N, "SHAP features:\n")
print(shap_top)

# Confounders are always included — remove from SHAP list to avoid duplication
base_vars     <- c("age_at_recruitment", "sex", "eth_bg")
selected_vars <- setdiff(shap_top, base_vars)

cat("\nSHAP-selected model features (excl. confounders):\n")
print(selected_vars)

full_model_vars <- unique(c(base_vars, selected_vars))

# domain_map and domains_ordered are loaded from plot_functions.R

# ============================================================
# 1. LOAD DATA
# ============================================================

refit_df      <- readRDS("../outputs/ukb_refit_20_imputed.rds")
refit_df$y    <- ifelse(trimws(as.character(refit_df$outcome)) == "No", 0L, 1L)

test_df       <- readRDS("../outputs/ukb_test_20_imputed.rds")
test_df$y     <- ifelse(trimws(as.character(test_df$outcome)) == "No", 0L, 1L)

# ============================================================
# 2. USE EXISTING FACTOR LEVELS AS REFERENCE GROUPS
# ============================================================

for (v in full_model_vars) {
  if (v %in% names(refit_df) &&
      (is.character(refit_df[[v]]) || is.factor(refit_df[[v]]))) {
    refit_df[[v]] <- factor(refit_df[[v]])
  }
  if (v %in% names(test_df) &&
      (is.character(test_df[[v]]) || is.factor(test_df[[v]]))) {
    test_df[[v]] <- factor(test_df[[v]])
  }
}

for (v in full_model_vars) {
  if (v %in% names(refit_df) && v %in% names(test_df) &&
      is.factor(refit_df[[v]])) {
    test_df[[v]] <- factor(test_df[[v]], levels = levels(refit_df[[v]]))
  }
}

cat("\nReference categories:\n")
for (v in full_model_vars) {
  if (v %in% names(refit_df) && is.factor(refit_df[[v]])) {
    cat(sprintf("  %s -> %s\n", v, levels(refit_df[[v]])[1]))
  }
}

# ============================================================
# 3. FIT FULL MODEL
# ============================================================

fit_formula <- as.formula(
  paste("y ~", paste(full_model_vars, collapse = " + "))
)

cat("\nFull model formula:\n")
print(fit_formula)

fit_refit <- glm(fit_formula, data = refit_df, family = "binomial")

cat("\n=== Logistic regression summary (full refit dataset) ===\n")
print(summary(fit_refit))

# ============================================================
# 4. REPEATED 50% SUBSAMPLING FOR STABILITY ANALYSIS
# ============================================================

n_runs      <- 100
sample_frac <- 0.50
all_terms   <- setdiff(names(coef(fit_refit)), "(Intercept)")

cat("\nRunning subsample stability (", n_runs, "runs,",
    sample_frac * 100, "% each):\n")

subsample_results <- vector("list", n_runs)

for (i in seq_len(n_runs)) {
  cat("Run", i, "of", n_runs, "\n")
  
  idx    <- sample(seq_len(nrow(refit_df)),
                   size = floor(sample_frac * nrow(refit_df)),
                   replace = FALSE)
  df_sub <- refit_df[idx, , drop = FALSE]
  
  for (v in full_model_vars) {
    if (v %in% names(refit_df) && is.factor(refit_df[[v]])) {
      df_sub[[v]] <- factor(df_sub[[v]], levels = levels(refit_df[[v]]))
    }
  }
  
  fit_i <- tryCatch(
    glm(fit_formula, data = df_sub, family = "binomial"),
    error = function(e) NULL
  )
  
  if (is.null(fit_i)) {
    subsample_results[[i]] <- data.frame(run = i, term = all_terms,
                                         estimate = NA_real_)
    next
  }
  
  coef_i        <- coef(fit_i)
  res_i         <- data.frame(run = i, term = all_terms,
                              estimate = NA_real_, row.names = NULL)
  matched_terms <- intersect(names(coef_i), all_terms)
  res_i$estimate[match(matched_terms, res_i$term)] <- coef_i[matched_terms]
  subsample_results[[i]] <- res_i
}

coef_long <- bind_rows(subsample_results)

# ============================================================
# 5. SUMMARISE: MEDIAN & IQR ON LOG-ODDS SCALE, THEN EXPONENTIATE
# ============================================================

coef_summary <- coef_long %>%
  group_by(term) %>%
  summarise(
    estimate_median = median(estimate, na.rm = TRUE),
    estimate_q25    = quantile(estimate, 0.25, na.rm = TRUE),
    estimate_q75    = quantile(estimate, 0.75, na.rm = TRUE),
    .groups = "drop"
  ) %>%
  mutate(
    OR  = exp(estimate_median),
    LCL = exp(estimate_q25),
    UCL = exp(estimate_q75)
  )

cat("\n=== Subsample stability summary ===\n")
print(coef_summary)

# ============================================================
# 6. BUILD PLOTTING TABLE
# ============================================================

factor_vars <- names(fit_refit$xlevels)

get_factor_var <- function(term, factor_vars) {
  hits <- factor_vars[str_detect(term, paste0("^", factor_vars))]
  if (length(hits) == 0) return(NA_character_)
  hits[which.max(nchar(hits))]
}

model_tbl <- coef_summary %>%
  mutate(
    factor_var     = sapply(term, get_factor_var, factor_vars = factor_vars),
    variable_raw   = if_else(!is.na(factor_var), factor_var, term),
    level          = if_else(!is.na(factor_var),
                             str_remove(term, paste0("^", factor_var)), ""),
    is_categorical = !is.na(factor_var)
  )

ref_lookup <- sapply(full_model_vars, function(v) {
  if (v %in% names(refit_df) && is.factor(refit_df[[v]])) {
    levels(refit_df[[v]])[1]
  } else {
    NA_character_
  }
}, USE.NAMES = TRUE)

model_tbl <- model_tbl %>%
  mutate(
    ref_level = unname(ref_lookup[variable_raw]),
    variable  = if_else(
      !is.na(ref_level),
      paste0(variable_raw, " (ref: ", ref_level, ")"),
      variable_raw
    )
  )

model_tbl$variable_raw <- factor(model_tbl$variable_raw, levels = full_model_vars)
model_tbl <- model_tbl %>% arrange(variable_raw, level)

# ============================================================
# 7. SAVE SUMMARY TABLE
# ============================================================

write_csv(model_tbl, file.path(output_dir, "xgboost_shap_subsample_summary.csv"))

# ============================================================
# 8. COMBINED FOREST PLOT (all variables)
# ============================================================

make_subsample_forest_plot(
  res_df     = model_tbl,
  vars       = full_model_vars,
  title      = paste0("Forest Plot: XGBoost SHAP-Selected Variables (Top ", TOP_N, ")"),
  filename   = "xgboost_shap_refit_forest.pdf",
  output_dir = output_dir
)

cat("\n=== Combined forest plot done ===\n")

# ============================================================
# 10. TEST SET PREDICTION
# ============================================================

test_df$pred_prob <- predict(fit_refit, newdata = test_df, type = "response")
test_eval         <- test_df %>% filter(!is.na(y), !is.na(pred_prob))

# ============================================================
# 11. AUC FOR FULL MODEL
# ============================================================

roc_obj <- roc(test_eval$y, test_eval$pred_prob, quiet = TRUE)
auc_val <- as.numeric(auc(roc_obj))
auc_ci  <- as.numeric(ci.auc(roc_obj))

cat("\n=== Full model test performance ===\n")
cat("AUC:", round(auc_val, 4), "\n")
cat("95% CI:", round(auc_ci[1], 4), "-", round(auc_ci[3], 4), "\n")

# ============================================================
# 12. CUMULATIVE INCREMENTAL AUC ANALYSIS
# ============================================================

add_order <- selected_vars

cat("\nVariables added in SHAP importance order:\n")
print(add_order)

get_cumulative_auc <- function(vars_added, step_label) {
  all_vars <- unique(c(base_vars, vars_added))
  form     <- as.formula(paste("y ~", paste(all_vars, collapse = " + ")))
  fit      <- glm(form, data = refit_df, family = "binomial")
  pred     <- predict(fit, newdata = test_df, type = "response")
  eval_df  <- data.frame(y = test_df$y, pred = pred) %>%
    filter(!is.na(y), !is.na(pred))
  roc_obj  <- roc(eval_df$y, eval_df$pred, quiet = TRUE)
  auc_val  <- as.numeric(auc(roc_obj))
  auc_ci   <- as.numeric(ci.auc(roc_obj))
  data.frame(
    step               = step_label,
    n_added            = length(vars_added),
    variables_in_model = paste(all_vars, collapse = " + "),
    auc                = auc_val,
    auc_low            = auc_ci[1],
    auc_high           = auc_ci[3]
  )
}

safe_get_auc <- function(vars_added, step_label) {
  tryCatch(
    get_cumulative_auc(vars_added, step_label),
    error = function(e) { cat("Failed at", step_label, ":", e$message, "\n"); NULL }
  )
}

cumulative_results    <- list()
cumulative_results[[1]] <- safe_get_auc(character(0), "Base")

for (i in seq_along(add_order)) {
  cumulative_results[[i + 1]] <- safe_get_auc(
    vars_added = add_order[1:i],
    step_label = paste0("+ ", add_order[i])
  )
}

cum_auc_df <- bind_rows(cumulative_results) %>%
  mutate(
    delta_auc = auc - first(auc),
    step      = factor(step, levels = step)
  )

cat("\n=== Cumulative AUC results ===\n")
print(cum_auc_df)

write_csv(cum_auc_df,
          file.path(output_dir, "xgboost_shap_incremental_auc_summary.csv"))

# ============================================================
# 13. INCREMENTAL AUC PLOT
# ============================================================

make_incremental_auc_plot(
  cum_auc_df = cum_auc_df,
  title      = paste0("XGBoost SHAP: Incremental AUC (Top ", TOP_N, ")"),
  filename   = "xgboost_shap_incremental_auc.png",
  output_dir = output_dir
)

# ============================================================
# 14. FINAL SUMMARY
# ============================================================

cat("\n=== Final summary ===\n")
print(data.frame(
  model    = paste0("XGBoost SHAP logistic refit (TOP_N=", TOP_N, ")"),
  auc      = auc_val,
  auc_low  = auc_ci[1],
  auc_high = auc_ci[3]
))

cat("\nSaved files:\n")
cat("- ../outputs/xgboost_shap_refit_forest.pdf\n")
cat("- ../outputs/xgboost_shap_domain_*_forest.pdf  (one per domain)\n")
cat("- ../outputs/xgboost_shap_subsample_summary.csv\n")
cat("- ../outputs/xgboost_shap_incremental_auc_summary.csv\n")
cat("- ../outputs/xgboost_shap_incremental_auc.png\n")
