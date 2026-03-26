# =========================================================
# 0X_relevel_imputed_splits.R
# Purpose: Apply uniform category collapsing and reference 
#          levels to ukb_collapsed3.rds and save as
#          ukb_collapsed4.rds
# =========================================================
suppressPackageStartupMessages({
  library(dplyr)
  library(forcats)
})

# 1. Define Paths
base_dir <- "/rds/general/project/hda_25-26/live/TDS/TDS_Group7/extraction_and_recoding"
input_file <- file.path(base_dir, "outputs", "ukb_collapsed3.rds")
output_file <- file.path(base_dir, "outputs", "ukb_collapsed4.rds")

# 2. Define the Master Cleaning Function
apply_uniform_releveling <- function(df) {
  
  # A. Collapse Categories
  df <- df %>%
    mutate(
      current_employ_status_grp = case_when(
        as.character(current_employ_status) == "In paid employment or self-employed" ~ "Employed",
        as.character(current_employ_status) == "Retired" ~ "Retired",
        as.character(current_employ_status) == "Unable to work because of sickness or disability" ~ "Unable to work",
        as.character(current_employ_status) %in% c(
          "Full or part-time student",
          "Unemployed", 
          "Looking after home and/or family", 
          "Doing unpaid or voluntary work",
          "None of the above"
        ) ~ "Other not in paid work",
        TRUE ~ NA_character_
      ),
      qualifications = fct_collapse(
        qualifications,
        "University" = "College or University degree",
        "School"     = c(
          "CSEs or equivalent",
          "O levels/GCSEs or equivalent",
          "A levels/AS levels or equivalent"
        ),
        "Other"      = c(
          "Other professional qualifications eg: nursing, teaching",
          "NVQ or HND or HNC or equivalent"
        ),
        "None"       = "None of the above"
      )
    )
  
  # B. Force Interpretable Reference Groups
  preferred_refs <- list(
    sex                       = "Female",
    eth_bg                    = "White",
    bmi                       = "Healthy weight",
    body_fat_pct              = "Normal weight",
    sleep_duration            = "Normal",
    sleep_insomnia            = "Never/rarely",
    diet_tea                  = "None",
    diet_coffee               = "None",
    diet_water                = "Normal",
    MET_summed                = "Low",
    sedentary_total_hours     = "Low",
    smoking_status            = "Never",
    risky_driving_speeding    = "Never",
    pregnant_yn               = "No",
    current_employ_status_grp = "Employed",
    alcohol_status_with_freq  = "Never",
    hh_income_pre_tax         = "Less than 18,000",
    qualifications            = "School",
    dis_cvd_doc_yn            = "None of the above"
  )
  
  set_ref <- function(x, ref) {
    x <- droplevels(as.factor(x))
    if (ref %in% levels(x)) relevel(x, ref = ref) else x
  }
  
  for (v in names(preferred_refs)) {
    if (v %in% names(df)) {
      df[[v]] <- set_ref(df[[v]], preferred_refs[[v]])
    }
  }
  
  # C. Set "No" as reference for all _yn suffix variables
  yn_vars <- grep("_yn$", names(df), value = TRUE)
  for (v in yn_vars) {
    if (v %in% names(df)) df[[v]] <- set_ref(df[[v]], "No")
  }
  
  return(df)
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