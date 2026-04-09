# =========================================================
# relevel_imputed_splits.R
# Purpose: Apply chosen reference levels to ukb_collapsed3.rds
#          and save as ukb_collapsed4.rds
# =========================================================

# 1. Define Paths
input_file <- "../outputs/ukb_collapsed3.rds"
output_file <- "../outputs/ukb_collapsed4.rds"

# 2. Define the Master Cleaning Function
apply_uniform_releveling <- function(df) {
  
  preferred_refs <- list(
    sex.0.0                       = "Female",
    eth_bg.0.0                    = "White",
    bmi.0.0                       = "Healthy weight",
    body_fat_pct.0.0              = "Normal weight",
    sleep_duration.0.0            = "Normal",
    sleep_insomnia.0.0            = "Never/rarely",
    diet_tea.0.0                  = "None",
    diet_coffee.0.0               = "None",
    diet_water.0.0                = "Normal",
    MET_summed.0.0                = "Low",
    sedentary_total_hours         = "Low",
    smoking_status.0.0            = "Never",
    risky_driving_speeding.0.0    = "Never",
    pregnant_yn.0.0               = "No",
    current_employ_status         = "Employed",
    alcohol_status_with_freq      = "Never",
    hh_income_pre_tax.0.0         = "Less than 18,000",
    qualifications                = "School",
    dis_cvd_doc_yn                = "None of the above",
    job_walk_stand_yn.0.0         = "Never/rarely",
    mh_loneliness.0.0             = "No",
    mh_social_support_confide.0.0 = "Yes",
    sur_major_surgery.0.0         = "No",
    dis_diabetes_doc_yn.0.0       = "No",
    dis_cancer_doc_yn.0.0         = "No",
    mh_BPD_MD.0.0                 = "No"
  )
  
  set_ref <- function(x, ref, varname) {
    x <- droplevels(as.factor(x))
    if (ref %in% levels(x)) {
      relevel(x, ref = ref)
    } else {
      message("Reference '", ref, "' not found for variable: ", varname)
      x
    }
  }
  
  for (v in names(preferred_refs)) {
    if (v %in% names(df)) {
      df[[v]] <- set_ref(df[[v]], preferred_refs[[v]], v)
    } else {
      message("Variable not found: ", v)
    }
  }
  
  df
}

# 3. Load, Process, and Save
if (file.exists(input_file)) {
  message("Processing: ", input_file)
  temp_df <- readRDS(input_file)
  temp_df <- apply_uniform_releveling(temp_df)
  saveRDS(temp_df, output_file)
  message("Successfully releveled and saved: ", output_file)
} else {
  message("ERROR: Could not find ", input_file)
}

message("=== Releveling complete ===")

