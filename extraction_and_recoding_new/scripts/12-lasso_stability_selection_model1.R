# =========================================================
# Purpose: Stability selection LASSO (60% split)
# Workflow:
#   1. Run stability selection using LASSO (alpha = 1) as the base learner
#   2. Extract stable variables and save all data to CSV/RDS FIRST
#   3. Draw Calibration and Selection plots LAST
#
# Predictors: fixed confounders (unpenalised) +
#             external exposures (penalised) +
#             biomarkers (penalised)
# =========================================================

.libPaths(c(Sys.getenv("R_LIBS_USER"), .libPaths()))
suppressPackageStartupMessages({
  library(dplyr)
  library(glmnet)
  library(sharp)
})

# 1. Paths
input_path <- "../outputs/ukb_selection_60_imputed.rds"
output_dir <- "../outputs/summary"

if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

# 2. Settings
seed_value   <- 42
K_subsamples <- 100
tau          <- 0.5

# 3. Load Data
df <- readRDS(input_path)
eid <- if ("eid" %in% names(df)) df$eid else rownames(df)
rownames(df) <- NULL

# 4. Prepare Binary Outcome
# outcome: "No" = 0, event = 1
df$y <- ifelse(trimws(as.character(df$outcome)) == "No", 0L, 1L)

# 5. Define Variable Blocks
always_in <- intersect(c("age_at_recruitment", "sex", "eth_bg"), names(df))

external_exposures <- intersect(c(
  "hh_income_pre_tax", "bmi", "body_fat_pct", "waist_circumference_cm",
  "hip_circumference_cm", "current_employ_status_grp", "smoking_status",
  "smoking_pack_years", "alcohol_status_with_freq", "diet_score",
  "diet_tea", "diet_coffee", "diet_water", "saturated_fat", "polyunsat_fat",
  "vitamin_b6", "vitamin_b12", "MET_summed", "sedentary_total_hours",
  "sleep_duration", "sleep_insomnia", "risky_driving_speeding", "air_no2_2010",
  "air_pm10_2010", "air_pm2_5_2010", "noise24h", "green_greenspace_300m",
  "green_garden_300m", "green_natural_300m", "blue_distance_coast",
  "n_treatments", "qualifications", "mh_loneliness",
  "mh_social_support_confide", "mh_neuroticism"
), names(df))

biomarkers <- intersect(c(
  "arterial_stiffness_index", "sys_bp", "dia_bp", "fvc", "fev1",
  "rbc_count", "haemoglobin_concent", "haematocrit_percent", "mean_corp_vol",
  "mean_corp_haem", "mean_corp_haem_con", "rdw", "platelet_count",
  "platelet_crit", "mean_platelet_volume", "platelet_distribution_width",
  "lymphocyte_count", "monocyte_count", "neutrophil_count", "eosinophil_count",
  "basophil_count", "lymphocyte_percentage", "monocyte_percentage",
  "neutrophil_percentage", "eosinophil_percentage", "basophil_percentage",
  "reticulocyte_percentage", "reticulocyte_count", "mean_reticulocyte_volume",
  "mean_sphered_cell_volume", "immature_reticulocyte_frac",
  "hlr_reticulocyte_percentage", "hlr_reticulocyte_count",
  "albumin", "alkaline_phos", "alanine_amino", "apolipoprotein_a",
  "apolipoprotein_b", "aspartate_amino", "bilirubin_direct", "urea",
  "calcium", "cholesterol", "creatinine", "crp", "cystatin_c",
  "gamma_glumy_tran", "glucose", "hba1c", "hdl", "igf1", "ldl",
  "lipoprotein_a", "oestradiol", "phosphate", "rheumatoid_factor",
  "shbg", "bilirubin_total", "testosterone", "triglycerides", "urate",
  "vitamin_d"
), names(df))

message("External exposures found : ", length(external_exposures))
message("Biomarkers found         : ", length(biomarkers))

# 6. Complete Case Filter
model_vars <- c("y", always_in, external_exposures, biomarkers)
dat <- df[complete.cases(df[, model_vars]), model_vars]

message("=== Complete-case filter ===")
message("Rows before : ", nrow(df))
message("Rows after  : ", nrow(dat), " (dropped: ", nrow(df) - nrow(dat), ")")
message("Case rate   : ", round(mean(dat$y), 4))

# 7. Build Model Matrix (expands factors to dummy terms)
x_df    <- dat[, c(always_in, external_exposures, biomarkers), drop = FALSE]
X       <- model.matrix(~ ., data = x_df)[, -1, drop = FALSE]
y       <- dat$y
x_names <- colnames(X)

message("Model matrix: ", nrow(X), " rows x ", ncol(X), " columns")

# 8. Penalty Factors
# 0 = always keep (confounders), 1 = penalise (exposures + biomarkers)
pf <- rep(1, length(x_names))
for (nm in always_in) {
  pf[grepl(paste0("^", nm), x_names)] <- 0
}
message("Unpenalised columns : ", sum(pf == 0))
message("Penalised columns   : ", sum(pf == 1))

# 9. Stability Selection using LASSO
set.seed(seed_value)
out_stability <- VariableSelection(
  xdata          = X,
  ydata          = y,
  family         = "binomial",
  penalty.factor = pf,
  alpha          = 1,             # Hardcoded to 1 for LASSO
  K              = K_subsamples,
  tau            = tau,
  n_cat          = 3,
  verbose        = FALSE
)

message("Base learner: LASSO (alpha = 1) - Computation Complete.")

# 10. Extract Parameters and Stable Variables
hat_params <- Argmax(out_stability)
lambda_hat <- hat_params[1]
pi_hat     <- hat_params[2]
message("Calibrated lambda : ", round(lambda_hat, 6))
message("Calibrated pi      : ", round(pi_hat, 4))

selprop <- SelectionProportions(out_stability)
stable_terms <- names(selprop)[selprop >= pi_hat]

# Remove confounder dummies from stable set
stable_terms <- stable_terms[
  !grepl(paste0("^", paste(always_in, collapse = "|^")), stable_terms)
]

get_base_var <- function(term, var_list) {
  for (v in var_list) {
    if (grepl(paste0("^", v), term)) return(v)
  }
  return(NA_character_)
}

all_selprop_df <- data.frame(
  term                 = names(selprop),
  selection_proportion = as.numeric(selprop),
  stringsAsFactors     = FALSE
) %>%
  filter(!grepl(paste0("^", paste(always_in, collapse = "|^")), term)) %>%
  mutate(
    base_var = sapply(term, get_base_var,
                      var_list = c(external_exposures, biomarkers)),
    var_type = case_when(
      base_var %in% external_exposures ~ "exposure",
      base_var %in% biomarkers         ~ "biomarker",
      TRUE                             ~ "other"
    )
  ) %>%
  arrange(desc(selection_proportion))

stable_vars_final <- all_selprop_df %>%
  filter(term %in% stable_terms)

message("=== STABLE VARIABLE SET ===")
message(nrow(stable_vars_final), " variables stably selected at pi >= ", round(pi_hat, 4))
message("  Exposures : ", sum(stable_vars_final$var_type == "exposure"))
message("  Biomarkers: ", sum(stable_vars_final$var_type == "biomarker"))
print(stable_vars_final)


# =========================================================
# 11. SAVE OUTPUTS FIRST (Bulletproofing against PDF crashes)
# =========================================================
message("\nSaving mathematical outputs to disk...")

saveRDS(out_stability,
        file.path(output_dir, "model1_lasso_stability_object.rds"))

write.csv(
  data.frame(
    base_learner            = "lasso",
    alpha_used              = 1,
    lambda_calibrated       = lambda_hat,
    pi_calibrated           = pi_hat,
    K_subsamples            = K_subsamples,
    tau                     = tau,
    n_rows_used             = nrow(dat),
    n_rows_dropped          = nrow(df) - nrow(dat),
    case_rate               = round(mean(dat$y), 4),
    n_stable_total          = nrow(stable_vars_final),
    n_stable_exposures      = sum(stable_vars_final$var_type == "exposure"),
    n_stable_biomarkers     = sum(stable_vars_final$var_type == "biomarker")
  ),
  file.path(output_dir, "model1_lasso_stability_summary.csv"),
  row.names = FALSE
)

write.csv(
  all_selprop_df,
  file.path(output_dir, "model1_lasso_all_selection_proportions.csv"),
  row.names = FALSE
)

write.csv(
  stable_vars_final,
  file.path(output_dir, "model1_lasso_stable_variables.csv"),
  row.names = FALSE
)

write.csv(
  filter(stable_vars_final, var_type == "exposure"),
  file.path(output_dir, "model1_lasso_stable_exposures.csv"),
  row.names = FALSE
)

message("All data saved successfully!")


# =========================================================
# 12. DRAW PLOTS LAST
# =========================================================
message("\nAttempting to generate PDF plots...")

# Calibration Plot
try({
  pdf(file.path(output_dir, "model1_lasso_calibration_plot.pdf"), width = 10, height = 7)
  CalibrationPlot(out_stability)
  dev.off()
}, silent = TRUE)

# Selection Proportions Plot
try({
  pdf(file.path(output_dir, "model1_lasso_selection_proportions.pdf"), width = 14, height = 7)
  par(mar = c(10, 5, 1, 1))
  plot(selprop, type = "h", lwd = 3, las = 1, xlab = "",
       ylab = "Selection Proportion", xaxt = "n",
       col  = ifelse(selprop >= pi_hat, "red", "grey"),
       cex.lab = 1.5)
  abline(h = pi_hat, lty = 2, col = "darkred")
  for (i in seq_along(selprop)) {
    axis(side = 1, at = i, labels = names(selprop)[i], las = 2,
         col      = ifelse(selprop[i] >= pi_hat, "red", "grey"),
         col.axis = ifelse(selprop[i] >= pi_hat, "red", "grey"))
  }
  dev.off()
}, silent = TRUE)

message("=== Script Complete ===")