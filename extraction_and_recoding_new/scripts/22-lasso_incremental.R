# ============================================================
# LASSO INCREMENTAL AUC PLOT
# Includes:
# - base model AUC
# - cumulative addition of selected variables
# - incremental AUC summary
# - incremental AUC plot
# - relabelled plot steps using plot_label_domain.csv
# - NEW: exposure-only incremental AUC plot
# - NEW: all-stable-variable plot with exposures first, then biomarkers
# ============================================================

library(readr)
library(dplyr)
library(ggplot2)
library(pROC)

set.seed(123)

# ============================================================
# 0. INPUTS
# ============================================================

stable_vars <- read_csv(
  "../outputs/summary/model1_lasso_stable_variables.csv",
  show_col_types = FALSE
)

plot_label_domain <- read_csv(
  "../outputs/plot_labels_domain.csv",
  show_col_types = FALSE
)

base_vars <- c("age_at_recruitment", "sex", "eth_bg")

# Assumes plot_label_domain.csv has:
# - variable   = original variable name
# - plot_label = label to display on plot
label_lookup <- setNames(plot_label_domain$plot_label, plot_label_domain$variable)

# keep one row per variable, ordered by selection proportion
stable_vars_unique <- stable_vars %>%
  distinct(base_var, .keep_all = TRUE) %>%
  arrange(desc(selection_proportion))

# all selected vars
selected_vars <- stable_vars_unique %>%
  pull(base_var)

# exposure selected vars only
selected_exposure_vars <- stable_vars_unique %>%
  filter(var_type == "exposure") %>%
  pull(base_var)

# non-exposure vars (e.g. biomarkers etc.)
selected_non_exposure_vars <- stable_vars_unique %>%
  filter(var_type != "exposure") %>%
  pull(base_var)

cat("Selected variables (all):\n")
print(selected_vars)

cat("\nSelected exposure variables:\n")
print(selected_exposure_vars)

cat("\nSelected non-exposure variables:\n")
print(selected_non_exposure_vars)

# ============================================================
# 1. LOAD DATA
# ============================================================

refit_df <- readRDS("../outputs/ukb_refit_20_imputed.rds")
refit_df$y <- ifelse(trimws(as.character(refit_df$outcome)) == "No", 0L, 1L)

test_df <- readRDS("../outputs/ukb_test_20_imputed.rds")
test_df$y <- ifelse(trimws(as.character(test_df$outcome)) == "No", 0L, 1L)

# keep only variables available in both datasets
full_model_vars <- unique(c(base_vars, selected_vars))
full_model_vars <- full_model_vars[
  full_model_vars %in% names(refit_df) & full_model_vars %in% names(test_df)
]

selected_vars <- selected_vars[selected_vars %in% full_model_vars]
selected_exposure_vars <- selected_exposure_vars[selected_exposure_vars %in% full_model_vars]
selected_non_exposure_vars <- selected_non_exposure_vars[selected_non_exposure_vars %in% full_model_vars]

cat("\nVariables available for cumulative AUC analysis:\n")
print(full_model_vars)

# ============================================================
# 2. USE EXISTING FACTOR LEVELS AS REFERENCE GROUPS
# ============================================================

for (v in full_model_vars) {
  if (is.character(refit_df[[v]]) || is.factor(refit_df[[v]])) {
    refit_df[[v]] <- factor(refit_df[[v]])
  }
  if (is.character(test_df[[v]]) || is.factor(test_df[[v]])) {
    test_df[[v]] <- factor(test_df[[v]])
  }
}

for (v in full_model_vars) {
  if (is.factor(refit_df[[v]])) {
    test_df[[v]] <- factor(test_df[[v]], levels = levels(refit_df[[v]]))
  }
}

cat("\nUsing existing factor levels in refit_df as reference categories:\n")
for (v in full_model_vars) {
  if (is.factor(refit_df[[v]])) {
    cat(sprintf("%s -> %s\n", v, levels(refit_df[[v]])[1]))
  }
}

# ============================================================
# 3. FIT FULL MODEL (OPTIONAL: for overall test AUC)
# ============================================================

fit_formula <- as.formula(
  paste("y ~", paste(full_model_vars, collapse = " + "))
)

fit_refit <- glm(
  fit_formula,
  data = refit_df,
  family = binomial
)

test_df$pred_prob <- predict(
  fit_refit,
  newdata = test_df,
  type = "response"
)

test_eval <- test_df %>%
  filter(!is.na(y), !is.na(pred_prob))

roc_obj <- roc(test_eval$y, test_eval$pred_prob, quiet = TRUE)
auc_val <- as.numeric(auc(roc_obj))
auc_ci  <- as.numeric(ci.auc(roc_obj))

cat("\n=== Full model test performance ===\n")
cat("AUC:", round(auc_val, 4), "\n")
cat("95% CI:", round(auc_ci[1], 4), "-", round(auc_ci[3], 4), "\n")

# ============================================================
# 4. FUNCTIONS FOR CUMULATIVE INCREMENTAL AUC ANALYSIS
# ============================================================

get_cumulative_auc <- function(vars_added, step_label, step_group = "base") {
  all_vars <- unique(c(base_vars, vars_added))
  all_vars <- all_vars[all_vars %in% names(refit_df) & all_vars %in% names(test_df)]
  
  form <- as.formula(
    paste("y ~", paste(all_vars, collapse = " + "))
  )
  
  fit <- glm(form, data = refit_df, family = binomial)
  
  pred <- predict(fit, newdata = test_df, type = "response")
  
  eval_df <- data.frame(y = test_df$y, pred = pred) %>%
    filter(!is.na(y), !is.na(pred))
  
  roc_obj <- roc(eval_df$y, eval_df$pred, quiet = TRUE)
  auc_val <- as.numeric(auc(roc_obj))
  auc_ci  <- as.numeric(ci.auc(roc_obj))
  
  pretty_all_vars <- ifelse(
    all_vars %in% names(label_lookup),
    label_lookup[all_vars],
    all_vars
  )
  
  data.frame(
    step = step_label,
    step_group = step_group,
    n_added = length(vars_added),
    variables_in_model = paste(pretty_all_vars, collapse = " + "),
    auc = auc_val,
    auc_low = auc_ci[1],
    auc_high = auc_ci[3]
  )
}

safe_get_auc <- function(vars_added, step_label, step_group = "base") {
  tryCatch(
    get_cumulative_auc(vars_added, step_label, step_group),
    error = function(e) {
      cat("Failed at", step_label, ":", e$message, "\n")
      NULL
    }
  )
}

# helper to create a cumulative AUC dataframe
build_cumulative_auc_df <- function(add_order, add_group, include_base_only = TRUE) {
  
  results_list <- list()
  
  if (include_base_only) {
    results_list[[1]] <- safe_get_auc(
      vars_added = character(0),
      step_label = "Base",
      step_group = "base"
    )
  }
  
  for (i in seq_along(add_order)) {
    vars_added_i <- add_order[1:i]
    
    pretty_label_i <- ifelse(
      add_order[i] %in% names(label_lookup),
      label_lookup[add_order[i]],
      add_order[i]
    )
    
    step_label_i <- paste0("+ ", pretty_label_i)
    
    results_list[[length(results_list) + 1]] <- safe_get_auc(
      vars_added = vars_added_i,
      step_label = step_label_i,
      step_group = add_group[i]
    )
  }
  
  bind_rows(results_list) %>%
    mutate(
      delta_auc = auc - first(auc),
      step_index = row_number(),
      step = factor(step, levels = step)
    )
}

# ============================================================
# 5. EXPOSURE-ONLY CUMULATIVE INCREMENTAL AUC ANALYSIS
# ============================================================

add_order_exposure <- selected_exposure_vars
add_group_exposure <- rep("exposure", length(add_order_exposure))

cat("\nOrder of cumulatively added exposure variables:\n")
print(add_order_exposure)

cum_auc_exposure_df <- build_cumulative_auc_df(
  add_order = add_order_exposure,
  add_group = add_group_exposure
)

cat("\n=== Exposure-only cumulative AUC results ===\n")
print(cum_auc_exposure_df)

write_csv(
  cum_auc_exposure_df,
  "../outputs/summary/lasso_incremental_auc_summary_exposure.csv"
)

# ============================================================
# 6. ALL-STABLE-VARIABLE CUMULATIVE AUC ANALYSIS
#    exposures first, then biomarkers/non-exposures
# ============================================================

add_order_all <- c(selected_exposure_vars, selected_non_exposure_vars)
add_group_all <- c(
  rep("exposure", length(selected_exposure_vars)),
  rep("biomarker", length(selected_non_exposure_vars))
)

cat("\nOrder of cumulatively added variables (exposures first, then biomarkers/non-exposures):\n")
print(add_order_all)

cum_auc_all_df <- build_cumulative_auc_df(
  add_order = add_order_all,
  add_group = add_group_all
)

cat("\n=== All-stable-variable cumulative AUC results ===\n")
print(cum_auc_all_df)

write_csv(
  cum_auc_all_df,
  "../outputs/summary/lasso_incremental_auc_summary_all.csv"
)

# ============================================================
# 7. EXPOSURE-ONLY INCREMENTAL AUC PLOT
# ============================================================

p_cum_auc_exposure <- ggplot(
  cum_auc_exposure_df,
  aes(x = step, y = auc)
) +
  geom_errorbar(
    aes(ymin = auc_low, ymax = auc_high),
    width = 0.6,
    linewidth = 0.4,
    colour = "blue3"
  ) +
  geom_point(
    colour = "blue3",
    size = 2
  ) +
  labs(
    title = "LASSO: Incremental AUC of Stable Exposures",
    x = "Model step",
    y = "AUC"
  ) +
  coord_cartesian(ylim = c(0.5, 1)) +
  theme_minimal(base_size = 11) +
  theme(
    plot.title = element_text(face = "bold", hjust = 0.5),
    axis.text.x = element_text(angle = 45, hjust = 1)
  )

print(p_cum_auc_exposure)

ggsave(
  filename = "../outputs/summary/lasso_incremental_auc_exposure.png",
  plot = p_cum_auc_exposure,
  width = 10,
  height = 6,
  dpi = 300
)

cat("Saved: ../outputs/summary/lasso_incremental_auc_exposure.png\n")

# ============================================================
# 8. ALL-STABLE-VARIABLE INCREMENTAL AUC PLOT
#    exposures in light blue, biomarkers/non-exposures in blue
# ============================================================

p_cum_auc_all <- ggplot(
  cum_auc_all_df,
  aes(x = step_index, y = auc, colour = step_group)
) +
  geom_errorbar(
    aes(ymin = auc_low, ymax = auc_high),
    width = 0.6,
    linewidth = 0.4
  ) +
  geom_point(size = 2) +
  scale_colour_manual(
    values = c(
      "base" = "grey40",
      "exposure" = "blue3",
      "biomarker" = "darkorange2"
    )
  ) +
  scale_x_continuous(
    breaks = cum_auc_all_df$step_index,
    labels = cum_auc_all_df$step
  ) +
  labs(
    title = "LASSO: incremental AUC of stable variables",
    x = "Model step",
    y = "AUC",
    colour = "Variable group"
  ) +
  coord_cartesian(ylim = c(0.5, 1)) +
  theme_minimal(base_size = 11) +
  theme(
    plot.title = element_text(face = "bold", hjust = 0.5),
    axis.text.x = element_text(angle = 45, hjust = 1)
  )

print(p_cum_auc_all)

ggsave(
  filename = "../outputs/summary/lasso_incremental_auc_all.png",
  plot = p_cum_auc_all,
  width = 11,
  height = 6,
  dpi = 300
)

cat("Saved: ../outputs/summary/lasso_incremental_auc_all.png\n")

# ============================================================
# 9. FINAL PRINTED SUMMARY
# ============================================================

cat("\n=== Final summary ===\n")
print(data.frame(
  model = "LASSO-selected refit logistic model",
  auc = auc_val,
  auc_low = auc_ci[1],
  auc_high = auc_ci[3]
))

cat("\nSaved files:\n")
cat("- ../outputs/lasso_incremental_auc_summary_exposure.csv\n")
cat("- ../outputs/lasso_incremental_auc_summary_all.csv\n")
cat("- ../outputs/lasso_incremental_auc_exposure.png\n")
cat("- ../outputs/lasso_incremental_auc_all.png\n")

