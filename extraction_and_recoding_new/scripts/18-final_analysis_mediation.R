# =========================================================
# 29-model1_mediation_analysis.R
# Purpose:
#   1. Step 2 Stability Selection (All Exposures -> Selected Biomarkers)
#   2. Load Total (C), Direct (C'), and Path B effects strictly from Script 11
#   3. Calculate Path A & Bootstrapped Indirect Effects
#   4. Classify pathways by stability selection status only
#
# CHANGES FROM PREVIOUS VERSION (per W10 supervisor feedback):
#
#   [1] ALPHA TUNING: Replaced cv.glmnet + optimize() with the SHARP
#       handbook approach: optimise() wrapping VariableSelection(),
#       returning max(stab$S). CV and stability selection must not be
#       combined (W10 meeting note #5). Mirrors Script 10 exactly.
#
#   [2] K=50 -> K=100 throughout (tuning + final run) to match Script 10.
#
#   [3] n_cat=3 added to both VariableSelection() calls (was missing in
#       the final run, causing mismatch with the tuning call).
#
#   [4] optimise() upper bound corrected to 1.0 (SHARP handbook).
#       lower=0.1 because alpha=0 is pure ridge (no variable selection).
#
#   [5] proportion_mediated removed. Not appropriate in a high-dimensional
#       variable selection framework (W10 meeting note #9).
#
#   [6] mediation_type classification rewritten. Now based purely on
#       stability selection status (was the exposure in Script 11 Step 1?
#       Step 2?). P-values and boot_ci_significant removed from the
#       classification entirely. Boot CI kept as a descriptive output
#       column only. Supervisors: do not filter by significance; report
#       all stable relationships (W10 meeting note #9).
#
#   [7] R=20 -> R=1000 for bootstrap (comment said set for final run).
# =========================================================

options(warn = 1)

.libPaths(c(Sys.getenv("R_LIBS_USER"), .libPaths()))
suppressPackageStartupMessages({
  library(dplyr)
  library(broom)
  library(boot)
  library(glmnet)
  library(sharp)
  library(future)
  library(future.apply)
})

# =========================================================
# PARALLELISATION SET UP
# =========================================================
pbs_cores_raw  <- Sys.getenv("PBS_NCPUS", "")
pbs_cores      <- suppressWarnings(as.numeric(pbs_cores_raw))
detected_cores <- parallel::detectCores(logical = FALSE)

if (is.na(pbs_cores) || pbs_cores < 1) pbs_cores <- detected_cores
n_cores <- min(16, pbs_cores)
message("Resource Check: Parallel backend is set to ", n_cores, " cores.")
future::plan(multicore, workers = n_cores)

# =========================================================
# 1. Define Paths & Load Data (STRICTLY FROM SCRIPT 11)
# =========================================================
base_dir               <- "../outputs"
refit_data_path        <- file.path(base_dir, "ukb_refit_20_imputed.rds")
stable_vars_path       <- file.path(base_dir, "model1_stable_variables.csv")
total_path_c_path      <- file.path(base_dir, "model1_refit_ORs_total_effect_pathC.csv")
direct_and_path_b_path <- file.path(base_dir, "model1_refit_ORs_direct_and_pathB.csv")
output_file            <- file.path(base_dir, "model1_mediation_indirect_effects_FINAL_6.csv")

message("Loading pre-cleaned data and Script 11 baselines...")
df_refit <- readRDS(refit_data_path)

stable_vars               <- read.csv(stable_vars_path,       stringsAsFactors = FALSE)
results_total_path_c      <- read.csv(total_path_c_path,      stringsAsFactors = FALSE)
results_direct_and_path_b <- read.csv(direct_and_path_b_path, stringsAsFactors = FALSE)

# =========================================================
# 2. Identify Variable Groups
# =========================================================
confounders <- c("age_at_recruitment", "sex", "eth_bg")
outcome_var <- "outcome"

step1_exposures  <- unique(stable_vars$base_var[stable_vars$var_type == "exposure"])
step1_biomarkers <- unique(stable_vars$base_var[stable_vars$var_type == "biomarker"])

all_external_exposures <- intersect(c(
  "hh_income_pre_tax", "bmi", "body_fat_pct", "waist_circumference_cm",
  "hip_circumference_cm", "current_employ_status_grp", "smoking_status",
  "smoking_pack_years", "alcohol_status_with_freq", "diet_score",
  "diet_tea", "diet_coffee", "diet_water", "saturated_fat", "polyunsat_fat",
  "vitamin_b6", "vitamin_b12", "MET_summed", "sedentary_total_hours",
  "sleep_duration", "sleep_insomnia", "risky_driving_speeding",
  "air_no2_2010", "air_pm10_2010", "air_pm2_5_2010", "noise24h",
  "green_greenspace_300m", "green_garden_300m", "green_natural_300m",
  "blue_distance_coast", "n_treatments", "qualifications",
  "mh_loneliness", "mh_social_support_confide", "mh_neuroticism"
), names(df_refit))

# =========================================================
# 3. Standardise Continuous Variables
# =========================================================
continuous_vars <- c(all_external_exposures, step1_biomarkers)
for (var in continuous_vars) {
  if (var %in% names(df_refit) && is.numeric(df_refit[[var]]) && length(unique(df_refit[[var]])) > 2) {
    df_refit[[var]] <- scale(df_refit[[var]])[, 1]
  }
}

# =========================================================
# 4. Extract Coefficients from Script 11 Output
# =========================================================
get_base_var <- function(term_name, base_list) {
  for (b in base_list) {
    if (startsWith(term_name, b)) return(b)
  }
  return(NA_character_)
}

# 4A. Path B: biomarker -> outcome coefficients (from direct effect model)
path_b_clean <- results_direct_and_path_b %>%
  mutate(base_var = sapply(term, get_base_var, base_list = step1_biomarkers)) %>%
  filter(!is.na(base_var)) %>%
  mutate(path_b_coef = log(estimate), path_b_pvalue = p.value) %>%
  select(mediator = term, path_b_coef, path_b_pvalue)

# 4B. Path C': direct effect of exposures on outcome (exposures + biomarkers model)
direct_clean <- results_direct_and_path_b %>%
  mutate(base_var = sapply(term, get_base_var, base_list = step1_exposures)) %>%
  filter(!is.na(base_var)) %>%
  mutate(direct_effect_logodds = log(estimate), direct_effect_pvalue = p.value) %>%
  select(exposure = term, direct_effect_logodds, direct_effect_pvalue)

# 4C. Path C: total effect of exposures on outcome (exposures only model)
total_clean <- results_total_path_c %>%
  mutate(base_var = sapply(term, get_base_var, base_list = step1_exposures)) %>%
  filter(!is.na(base_var)) %>%
  mutate(total_effect_logodds = log(estimate), total_effect_pvalue = p.value) %>%
  select(exposure = term, total_effect_logodds, total_effect_pvalue)

# =========================================================
# 5. STEP 2 STABILITY SELECTION: All Exposures -> Each Biomarker
# =========================================================
# FIX [1][2][3][4]: Alpha tuned using optimise() wrapping VariableSelection()
# returning max(stab$S) — the SHARP handbook approach, same as Script 10.
# cv.glmnet removed entirely. K=100, n_cat=3, upper=1 throughout.
# =========================================================
message("\n=== Commencing Step 2 Stability Selection (Gaussian) ===")

eval_XM_pairs <- list()

for (biomarker in step1_biomarkers) {
  message("-> Running Stability Selection for Mediator: ", biomarker)
  
  model_vars_m <- c(biomarker, confounders, all_external_exposures)
  dat_m        <- df_refit[complete.cases(df_refit[, model_vars_m]), model_vars_m]
  
  x_df_m <- dat_m[, c(confounders, all_external_exposures), drop = FALSE]
  X_m    <- model.matrix(~ ., data = x_df_m)[, -1, drop = FALSE]
  y_m    <- dat_m[[biomarker]]
  
  pf_m <- rep(1, ncol(X_m))
  for (nm in confounders) {
    pf_m[grepl(paste0("^", nm), colnames(X_m))] <- 0
  }
  
  # --- Tune alpha via stability score (SHARP handbook / Script 10 approach) ---
  message("   Tuning alpha via stability score...")
  
  TuneElasticNet_m <- function(alpha_val) {
    set.seed(42)
    tmp <- VariableSelection(
      xdata          = X_m,
      ydata          = y_m,
      family         = "gaussian",
      penalty.factor = pf_m,
      alpha          = alpha_val,
      K              = 100,   # FIX [2]: matches Script 10
      tau            = 0.5,
      n_cat          = 3,     # FIX [3]: consistent across tuning and final call
      verbose        = FALSE
    )
    return(max(tmp$S, na.rm = TRUE))  # stab$S is the stability score matrix
  }
  
  opt_result_m <- optimise(
    f       = TuneElasticNet_m,
    lower   = 0.1,  # alpha=0 is pure ridge (no variable selection) — excluded
    upper   = 1,    # FIX [4]: SHARP handbook uses upper=1 (was 0.9 implicitly via old CV)
    maximum = TRUE
  )
  
  best_alpha_m <- opt_result_m$maximum
  message(sprintf("   Best alpha: %.4f  (stability score: %.4f)",
                  best_alpha_m, opt_result_m$objective))
  
  # --- Final stability selection with tuned alpha ---
  message("   Running final stability selection...")
  set.seed(42)
  out_stability_m <- VariableSelection(
    xdata          = X_m,
    ydata          = y_m,
    family         = "gaussian",
    penalty.factor = pf_m,
    alpha          = best_alpha_m,
    K              = 100,   # FIX [2]: matches tuning call and Script 10
    tau            = 0.5,
    n_cat          = 3,     # FIX [3]: matches tuning call
    verbose        = FALSE
  )
  
  pi_hat_m  <- Argmax(out_stability_m)[2]
  selprop_m <- SelectionProportions(out_stability_m)
  
  stable_terms_m <- names(selprop_m)[selprop_m >= pi_hat_m]
  stable_terms_m <- stable_terms_m[
    !grepl(paste0("^", paste(confounders, collapse = "|^")), stable_terms_m)
  ]
  
  step2_bases_m <- unique(sapply(stable_terms_m, get_base_var,
                                 base_list = all_external_exposures))
  step2_bases_m <- step2_bases_m[!is.na(step2_bases_m)]
  
  eval_XM_pairs[[biomarker]] <- step2_bases_m
  message("   Found ", length(step2_bases_m), " Step 2 exposures for this biomarker.")
}

# =========================================================
# 6. Bootstrap Function (Path A)
# =========================================================
boot_path_a <- function(data, indices, mediator, confounders, exposure_term, step2_exposures) {
  d       <- data[indices, ]
  form_a  <- as.formula(paste(mediator, "~",
                              paste(c(confounders, step2_exposures), collapse = " + ")))
  model_a <- tryCatch(lm(form_a, data = d), error = function(e) NULL)
  if (is.null(model_a) || !(exposure_term %in% names(coef(model_a)))) return(NA)
  return(coef(model_a)[exposure_term])
}

# =========================================================
# 7. Calculate Path A & Bootstrapped Indirect Effects
# =========================================================
message("\n=== Calculating Path A and Indirect Effects ===")

path_a_results_list <- future_lapply(step1_biomarkers, function(biomarker) {
  
  step2_bases <- eval_XM_pairs[[biomarker]]
  if (length(step2_bases) == 0) return(NULL)
  
  # Point estimate for Path A
  form_a  <- as.formula(paste(biomarker, "~",
                              paste(c(confounders, step2_bases), collapse = " + ")))
  model_a <- lm(form_a, data = df_refit)
  
  # Fetch Path B coefficient
  b_coef <- path_b_clean$path_b_coef[path_b_clean$mediator == biomarker]
  if (length(b_coef) == 0) b_coef <- NA
  
  tidy_a <- broom::tidy(model_a) %>%
    dplyr::filter(!term %in% c("(Intercept)", confounders)) %>%
    dplyr::rowwise() %>%
    dplyr::mutate(base_var_match = get_base_var(term, step2_bases)) %>%
    dplyr::ungroup() %>%
    dplyr::filter(!is.na(base_var_match)) %>%
    dplyr::mutate(
      mediator      = biomarker,
      path_a_coef   = estimate,
      path_a_se     = std.error,
      path_a_pvalue = p.value
    ) %>%
    dplyr::select(exposure = term, base_var_match, mediator,
                  path_a_coef, path_a_se, path_a_pvalue)
  
  boot_ci_lower <- rep(NA, nrow(tidy_a))
  boot_ci_upper <- rep(NA, nrow(tidy_a))
  
  RNGkind("L'Ecuyer-CMRG")
  set.seed(123)
  
  for (i in seq_along(tidy_a$exposure)) {
    exposure_term_i <- tidy_a$exposure[i]
    
    boot_result <- tryCatch(
      boot(
        data            = df_refit,
        statistic       = boot_path_a,
        R               = 1000,  # FIX [7]: set to 1000 for final run (was R=20)
        mediator        = biomarker,
        confounders     = confounders,
        exposure_term   = exposure_term_i,
        step2_exposures = step2_bases,
        parallel        = "no"
      ),
      error = function(e) NULL
    )
    
    if (!is.null(boot_result) && !is.na(b_coef)) {
      indirect_samples <- boot_result$t * b_coef
      boot_ci_lower[i] <- quantile(indirect_samples, 0.025, na.rm = TRUE)
      boot_ci_upper[i] <- quantile(indirect_samples, 0.975, na.rm = TRUE)
    }
  }
  
  tidy_a$boot_ci_lower <- boot_ci_lower
  tidy_a$boot_ci_upper <- boot_ci_upper
  
  return(tidy_a)
  
}, future.seed = TRUE)

path_a_results <- dplyr::bind_rows(path_a_results_list)

# =========================================================
# 8. Join Everything & Classify Pathways
# =========================================================
# FIX [5]: proportion_mediated removed. Not appropriate in a high-dimensional
#   variable selection framework (W10 meeting note #9). If needed for the
#   appendix it can be computed as: indirect_effect_logodds / total_effect_logodds
#
# FIX [6]: mediation_type now based purely on stability selection status.
#   The old classification gated everything through boot_ci_significant and
#   direct_effect_pvalue < 0.05 — both removed. Supervisors: do not filter
#   by significance; report all stable relationships (W10 meeting note #9).
#   boot_ci_crosses_zero is kept as a descriptive column only so readers
#   can see the uncertainty, but it does NOT drive the classification.
#
# Classification logic (stability-selection-based only):
#   Partial Mediation  — exposure in Script 11 total AND direct effect model
#                        (consistent direct + indirect pathway)
#   Full Mediation     — exposure in Script 11 total effect only (effect
#                        absorbed when biomarkers added to model)
#   Indirect Only      — exposure NOT in Script 11 but found in Step 2
#                        (predicts a biomarker but no direct CVD selection)
# =========================================================
message("Finalising mediation table and classifying pathways...")

mediation_final <- path_a_results %>%
  inner_join(path_b_clean, by = "mediator") %>%
  mutate(
    indirect_effect_logodds = path_a_coef * path_b_coef,
    # Descriptive only — not used as a classification filter
    boot_ci_crosses_zero = ifelse(
      !is.na(boot_ci_lower) & !is.na(boot_ci_upper),
      boot_ci_lower <= 0 & boot_ci_upper >= 0,
      NA
    )
  ) %>%
  left_join(total_clean,  by = "exposure") %>%
  left_join(direct_clean, by = "exposure") %>%
  mutate(
    # Classify purely by stability selection status — no p-value gating
    mediation_type = case_when(
      !is.na(total_effect_logodds) & !is.na(direct_effect_logodds) ~ "Partial Mediation (Primary)",
      !is.na(total_effect_logodds) & is.na(direct_effect_logodds)  ~ "Full Mediation (Primary)",
      is.na(total_effect_logodds)  & is.na(direct_effect_logodds)  ~ "Indirect Only (Path A)",
      TRUE ~ "Unclassified"
    )
  ) %>%
  select(
    exposure, mediator,
    path_a_coef, path_a_se, path_a_pvalue,
    path_b_coef, path_b_pvalue,
    indirect_effect_logodds, boot_ci_lower, boot_ci_upper, boot_ci_crosses_zero,
    direct_effect_logodds, direct_effect_pvalue,
    total_effect_logodds,   total_effect_pvalue,
    mediation_type
    # NOTE: proportion_mediated removed per W10 supervisor feedback.
    # If needed for appendix: indirect_effect_logodds / total_effect_logodds
  )

write.csv(mediation_final, output_file, row.names = FALSE)
message("=== DONE! Master table saved to: ", output_file, " ===")