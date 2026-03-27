# 28b_impute_refit.R
# Fits the imputation model on the refit split (20%) and saves it
# for use on the test split.
# Mirrors 28a_impute_selection.R exactly — same structure, same logic.

.libPaths(c(Sys.getenv("R_LIBS_USER"), .libPaths()))
suppressPackageStartupMessages({
  library(dplyr)
  library(miceRanger)
  library(future)
})

base        <- "../outputs"
input_path  <- file.path(base, "ukb_refit_20_raw.rds")
output_path <- file.path(base, "relevel_ukb_refit_20_imputed_copy.rds")
model_path  <- file.path(base, "ukb_refit_20_impute_model.rds")

message("Input:  ", input_path)
message("Output: ", output_path)
message("Model will be saved to: ", model_path)

n_cores <- future::availableCores()
options(ranger.num.threads = n_cores)
message("Running on ", n_cores, " cores.")

df  <- readRDS(input_path)
eid <- if ("eid" %in% names(df)) df$eid else rownames(df)
if (is.null(eid) || length(eid) != nrow(df)) stop("Critical: EID mismatch.")
rownames(df) <- NULL

message("Refit split loaded: ", nrow(df), " rows")

# --- VARIABLE SETS ---
exposures <- c(
  "hh_income_pre_tax", "bmi", "body_fat_pct",
  "waist_circumference_cm", "hip_circumference_cm",
  "current_employ_status", "smoking_status", "smoking_pack_years",
  "alcohol_status_with_freq", "diet_score", "diet_tea", "diet_coffee",
  "diet_water", "saturated_fat", "polyunsat_fat", "vitamin_b6", "vitamin_b12",
  "MET_summed", "sedentary_total_hours", "sleep_duration", "sleep_insomnia",
  "risky_driving_speeding", "air_no2_2010", "air_pm10_2010", "air_pm2_5_2010",
  "noise24h", "green_greenspace_300m", "green_garden_300m", "green_natural_300m",
  "blue_distance_coast", "n_treatments", "qualifications"
)

biomarkers <- c(
  "arterial_stiffness_index", "sys_bp", "dia_bp", "fvc", "fev1",
  "rbc_count", "haemoglobin_concent", "haematocrit_percent", "mean_corp_vol",
  "mean_corp_haem", "mean_corp_haem_con", "rdw", "platelet_count", "platelet_crit",
  "mean_platelet_volume", "platelet_distribution_width", "lymphocyte_count",
  "monocyte_count", "neutrophil_count", "eosinophil_count", "basophil_count",
  "lymphocyte_percentage", "monocyte_percentage", "neutrophil_percentage",
  "eosinophil_percentage", "basophil_percentage", "reticulocyte_percentage",
  "reticulocyte_count", "mean_reticulocyte_volume", "mean_sphered_cell_volume",
  "immature_reticulocyte_frac", "hlr_reticulocyte_percentage", "hlr_reticulocyte_count",
  "albumin", "alkaline_phos", "alanine_amino", "apolipoprotein_a", "apolipoprotein_b",
  "aspartate_amino", "bilirubin_direct", "urea", "calcium", "cholesterol",
  "creatinine", "crp", "cystatin_c", "gamma_glumy_tran", "glucose", "hba1c",
  "hdl", "igf1", "ldl", "lipoprotein_a", "oestradiol", "phosphate",
  "rheumatoid_factor", "shbg", "bilirubin_total", "testosterone",
  "triglycerides", "urate", "vitamin_d"
)

core_confounders <- c("sex", "age_at_recruitment", "eth_bg")
admin_vars       <- c("dob", "yr_imm_uk")
dx_timing        <- grep("(^dis|^date_of_|^mh_|^med_)", names(df), value = TRUE)
health_states    <- c("dis_diabetes_doc_yn", "dis_cancer_doc_yn", "mh_BPD_MD",
                      "mh_neuroticism", "mh_loneliness", "mh_social_support_confide",
                      "dis_cvd_doc_yn")
other_vars       <- c("sur_major_surgery", "attending_assessment_date", "outcome",
                      "pregnant_yn", "age_full_edu")

never_impute <- unique(c(core_confounders, admin_vars, dx_timing, health_states, other_vars))

impute_targets <- intersect(c(exposures, biomarkers), names(df))

df_impute <- df[, unique(c(impute_targets, intersect(never_impute, names(df))))] %>%
  mutate(
    across(where(~inherits(.x, "Date") || inherits(.x, "POSIXt")), as.numeric),
    across(where(is.character), as.factor),
    across(where(is.logical), as.factor)
  )

# --- CUSTOM PREDICTOR MATRIX ---
exclude_from_engine <- intersect(never_impute, names(df_impute))
target_vars         <- setdiff(names(df_impute), exclude_from_engine)
exposures_in_data   <- intersect(exposures, target_vars)
biomarkers_in_data  <- intersect(biomarkers, target_vars)
confounders_in_data <- intersect(core_confounders, names(df_impute))

pred_list <- list()
for (v in target_vars) {
  if (v %in% exposures_in_data) {
    pred_list[[v]] <- c(confounders_in_data, setdiff(exposures_in_data, v))
  } else if (v %in% biomarkers_in_data) {
    pred_list[[v]] <- c(confounders_in_data, exposures_in_data, setdiff(biomarkers_in_data, v))
  } else {
    pred_list[[v]] <- c(confounders_in_data, setdiff(target_vars, v))
  }
}

# Fit imputation model on the refit split
# returnModels = TRUE so it can be saved and applied to the test split
set.seed(123)
impute_obj <- miceRanger(
  returnModels = TRUE,
  data         = df_impute,
  m            = 1,
  maxiter      = 5,
  vars         = pred_list,
  num.trees    = 100,
  verbose      = TRUE
)

message("Saving refit imputation model to: ", model_path)
saveRDS(impute_obj, model_path)

# Stitch the never-imputed variables back on
data_final <- as.data.frame(completeData(impute_obj)[[1]]) %>%
  mutate(eid = eid) %>%
  select(-any_of(exclude_from_engine)) %>%
  left_join(
    mutate(df[, intersect(never_impute, names(df)), drop = FALSE], eid = eid),
    by = "eid"
  ) %>%
  mutate(dob = as.Date(dob, origin = "1970-01-01"))

rownames(data_final) <- data_final$eid
data_final$eid <- NULL

message("Refit imputation complete.")
message("Output rows    : ", nrow(data_final))
message("Output columns : ", ncol(data_final))

saveRDS(data_final, output_path)
message("Saved to: ", output_path)
