# ============================================================
# 6-preprocessing.R
# - This file currently mixes:
#   (A) Basic cleaning (sentinel to NA, range checks)
#   (B) Biochem negative -> NA
#   (C) Banding / categorisation (overwrites selected variables with categorical versions)
#   (D) Numeric type conversion for selected variables
#   (E) Global type fixing (convert remaining to factors)
#   (F) Nonresponse handling (PNA/DNK -> NA or "Other")
# ============================================================

library(dplyr)
rm(list = ls())

# ------------------------------------------------------------
# 0) Load input data
# ------------------------------------------------------------
df <- readRDS("outputs/ukb_collapsed2.rds")

# ============================================================
# 1) BASIC CLEANING / SENTINEL HANDLING
# ============================================================

# change "Never went to school" to 0 in age_full_edu, if present
if ("age_full_edu.0.0" %in% names(df)) {
  df$age_full_edu.0.0[df$age_full_edu.0.0 == "Never went to school"] <- "0"
}

# change sentinel values to NA
df <- df %>%
  mutate(
    across(where(is.numeric),   ~ dplyr::na_if(., -999909999)),
    across(where(is.character), ~ dplyr::na_if(., "-999909999")),
    across(where(is.factor),    ~ dplyr::na_if(as.character(.), "-999909999"))
  )

# ============================================================
# 2) RANGE CHECKS / OUTLIER RULES
# ============================================================

# limit sys bp to <= 250 if present
if ("sys_bp" %in% names(df)) {
  df$sys_bp[df$sys_bp > 250] <- NA
}

# ============================================================
# 3) BIOCHEM + RELATED CONTINUOUS VARIABLES: NEGATIVE -> NA
# ============================================================

biochem_cols <- c(
  "microalbuminuria_urine.0.0",
  "albumin.0.0",
  "alkaline_phos.0.0",
  "alanine_amino.0.0",
  "apolipoprotein_a.0.0",
  "apolipoprotein_b.0.0",
  "aspartate_amino.0.0",
  "bilirubin_direct.0.0",
  "urea.0.0",
  "calcium.0.0",
  "cholesterol.0.0",
  "creatinine.0.0",
  "crp.0.0",
  "cystatin_c.0.0",
  "gamma_glumy_tran.0.0",
  "glucose.0.0",
  "hba1c.0.0",
  "hdl.0.0",
  "igf1.0.0",
  "ldl.0.0",
  "lipoprotein_a.0.0",
  "oestradiol.0.0",
  "phosphate.0.0",
  "rheumatoid_factor.0.0",
  "shbg.0.0",
  "bilirubin_total.0.0",
  "testosterone.0.0",
  "triglycerides.0.0",
  "urate.0.0",
  "vitamin_d.0.0",
  "saturated_fat.0.0",
  "polyunsat_fat.0.0",
  "vitamin_b6.0.0",
  "vitamin_b12.0.0",
  "arterial_stiffness_index.0.0",
  "air_no2_2010.0.0",
  "green_greenspace_300m.0.0",
  "green_garden_300m.0.0",
  "platelet_count.0.0",
  "lymphocyte_count.0.0",
  "neutrophil_count.0.0",
  "lymphocyte_percentage.0.0",
  "hlr_reticulocyte_count.0.0",
  "reticulocyte_percentage.0.0",
  "reticulocyte_count.0.0",
  "hlr_reticulocyte_percentage.0.0",
  "eosinophil_percentage.0.0",
  "basophil_percentage.0.0",
  "nucleated_rbc_percentage.0.0",
  "basophil_count.0.0",
  "nucleated_rbc_count.0.0",
  "monocyte_percentage.0.0",
  "blue_distance_coast.0.0",
  "monocyte_count.0.0",
  "eosinophil_count.0.0",
  "body_fat_pct.0.0",
  "blue_water_300m.0.0",
  "green_natural_300m.0.0",
  "smoking_pack_years.0.0"
)

biochem_cols <- intersect(biochem_cols, names(df))

df[biochem_cols] <- lapply(df[biochem_cols], function(x) {
  x <- as.numeric(as.character(x))
  x[x < 0] <- NA_real_
  x
})

# ============================================================
# 4) BANDING / CATEGORISATION
# ============================================================

safe_num <- function(x) suppressWarnings(as.numeric(x))
refusal_responses <- c("Prefer not to answer", "Do not know")

df <- df %>%
  mutate(
    diet_water.0.0 = case_when(
      diet_water.0.0 %in% refusal_responses ~ diet_water.0.0,
      safe_num(diet_water.0.0) < 6 ~ "Low",
      safe_num(diet_water.0.0) >= 6 & safe_num(diet_water.0.0) <= 11 ~ "Normal",
      safe_num(diet_water.0.0) >= 12 ~ "Not normal",
      TRUE ~ NA_character_
    ),
    
    diet_coffee.0.0 = case_when(
      diet_coffee.0.0 %in% refusal_responses ~ diet_coffee.0.0,
      safe_num(diet_coffee.0.0) == 0 ~ "None",
      safe_num(diet_coffee.0.0) >= 1 & safe_num(diet_coffee.0.0) <= 3 ~ "Moderate",
      safe_num(diet_coffee.0.0) > 3 ~ "Heavy",
      TRUE ~ NA_character_
    ),
    
    diet_tea.0.0 = case_when(
      diet_tea.0.0 %in% refusal_responses ~ diet_tea.0.0,
      safe_num(diet_tea.0.0) == 0 ~ "None",
      safe_num(diet_tea.0.0) == 1 ~ "Low",
      safe_num(diet_tea.0.0) >= 2 & safe_num(diet_tea.0.0) <= 5 ~ "Medium",
      safe_num(diet_tea.0.0) >= 6 ~ "High",
      TRUE ~ NA_character_
    ),
    
    MET_summed.0.0 = case_when(
      MET_summed.0.0 < 600 ~ "Low",
      MET_summed.0.0 >= 600 & MET_summed.0.0 <= 3000 ~ "Moderate",
      MET_summed.0.0 > 3000 ~ "High",
      TRUE ~ NA_character_
    ),
    
    bmi.0.0 = case_when(
      bmi.0.0 < 15 ~ NA_character_,
      bmi.0.0 >= 15 & bmi.0.0 < 18.5 ~ "Underweight",
      bmi.0.0 >= 18.5 & bmi.0.0 < 25 ~ "Healthy weight",
      bmi.0.0 >= 25 & bmi.0.0 < 30 ~ "Overweight",
      bmi.0.0 >= 30 ~ "Obese",
      TRUE ~ NA_character_
    ),
    
    `body_fat_pct.0.0` = case_when(
      `body_fat_pct.0.0` < 5 ~ NA_character_,
      sex.0.0 == "Male" & `body_fat_pct.0.0` < 13 ~ "Underweight",
      sex.0.0 == "Male" & `body_fat_pct.0.0` >= 13 & `body_fat_pct.0.0` < 23 ~ "Normal weight",
      sex.0.0 == "Male" & `body_fat_pct.0.0` >= 23 & `body_fat_pct.0.0` < 29 ~ "Overweight",
      sex.0.0 == "Male" & `body_fat_pct.0.0` >= 29 ~ "Obesity",
      sex.0.0 == "Female" & `body_fat_pct.0.0` < 26 ~ "Underweight",
      sex.0.0 == "Female" & `body_fat_pct.0.0` >= 26 & `body_fat_pct.0.0` < 35 ~ "Normal weight",
      sex.0.0 == "Female" & `body_fat_pct.0.0` >= 35 & `body_fat_pct.0.0` < 41 ~ "Overweight",
      sex.0.0 == "Female" & `body_fat_pct.0.0` >= 41 ~ "Obesity",
      TRUE ~ NA_character_
    ),
    
    sleep_duration.0.0 = case_when(
      sleep_duration.0.0 %in% refusal_responses ~ sleep_duration.0.0,
      safe_num(sleep_duration.0.0) >= 7 & safe_num(sleep_duration.0.0) <= 9 ~ "Normal",
      safe_num(sleep_duration.0.0) < 7 | safe_num(sleep_duration.0.0) > 9 ~ "Not normal",
      TRUE ~ NA_character_
    ),
    
    waist_circumference_cm.0.0 = if_else(
      waist_circumference_cm.0.0 < 60,
      NA_real_,
      waist_circumference_cm.0.0
    ),
    
    sedentary_total_hours = case_when(
      sedentary_total_hours %in% refusal_responses ~ sedentary_total_hours,
      safe_num(sedentary_total_hours) < 4 ~ "Low",
      safe_num(sedentary_total_hours) >= 4 & safe_num(sedentary_total_hours) <= 8 ~ "Moderate",
      safe_num(sedentary_total_hours) > 8 ~ "High",
      TRUE ~ NA_character_
    )
  )

# ============================================================
# 5) TYPE / NUMERIC CONVERSION FOR SELECTED VARIABLES
# ============================================================

change_num <- c(
  "age_full_edu.0.0",
  "dis_age_highbp.0.0",
  "dis_age_diabetes.0.0",
  "yr_imm_uk.0.0",
  "dis_age_mi.0.0",
  "age_at_recruitment.0.0",
  "dis_age_copd.0.0",
  "dis_age_pulmonary_fibrosis.0.0"
)
change_num <- intersect(change_num, names(df))

df[change_num] <- lapply(df[change_num], function(x) {
  x <- suppressWarnings(as.numeric(as.character(x)))
  x[x < 0] <- NA_real_
  x
})

# ============================================================
# 6) GLOBAL TYPE FIXING
# ============================================================

df[] <- lapply(df, function(x) {
  if (is.numeric(x) || inherits(x, c("Date", "POSIXct", "POSIXlt"))) {
    x
  } else {
    droplevels(as.factor(x))
  }
})

# safer education age <16 -> NA
if ("age_full_edu.0.0" %in% names(df)) {
  tmp_edu <- suppressWarnings(as.numeric(as.character(df$age_full_edu.0.0)))
  df$age_full_edu.0.0[tmp_edu < 16] <- NA_real_
}

# ============================================================
# 8) NONRESPONSE HANDLING (PNA/DNK -> NA or "Other")
# ============================================================

vars_with_nonresponse <- c(
  "hh_income_pre_tax.0.0",
  "job_walk_stand_yn.0.0",
  "age_full_edu.0.0",
  "sedentary_tv.0.0",
  "sedentary_computer.0.0",
  "sedentary_driving.0.0",
  "risky_driving_speeding.0.0",
  "sleep_duration.0.0",
  "sleep_insomnia.0.0",
  "smoking_current_status.0.0",
  "smoking_past_status.0.0",
  "diet_cooked_vegetables.0.0",
  "diet_raw_vegetables.0.0",
  "diet_fruit_fresh.0.0",
  "diet_fruit_dried.0.0",
  "diet_oily_fish.0.0",
  "diet_non_oily_fish.0.0",
  "diet_processed_meat.0.0",
  "diet_poultry.0.0",
  "diet_beef.0.0",
  "diet_lamb.0.0",
  "diet_pork.0.0",
  "diet_cheese.0.0",
  "diet_milk_type.0.0",
  "diet_spread_type.0.0",
  "diet_bread_intake.0.0",
  "diet_bread_type.0.0",
  "diet_cereal_intake.0.0",
  "diet_cereal_type.0.0",
  "diet_salt.0.0",
  "diet_tea.0.0",
  "diet_coffee.0.0",
  "diet_water.0.0",
  "mh_loneliness.0.0",
  "mh_social_support_confide.0.0",
  "sur_major_surgery.0.0",
  "dis_diabetes_doc_yn.0.0",
  "dis_cancer_doc_yn.0.0",
  "dis_age_highbp.0.0",
  "dis_age_diabetes.0.0",
  "yr_imm_uk.0.0",
  "dis_age_mi.0.0",
  "eth_bg.0.0",
  "qualifications",
  "dis_cvd_doc_yn",
  "med_chol_bp_dm_or_horm_yn.0.0",
  "med_chol_bp_dm_or_horm_yn.0.1",
  "med_chol_bp_dm_or_horm_yn.0.2",
  "med_chol_bp_dm_or_horm_yn.0.3",
  "med_symptom_relief_yn.0.0",
  "med_symptom_relief_yn.0.1",
  "med_symptom_relief_yn.0.2",
  "med_symptom_relief_yn.0.3",
  "med_symptom_relief_yn.0.4",
  "med_symptom_relief_yn.0.5",
  "med_chol_bp_dm_yn.0.0",
  "med_chol_bp_dm_yn.0.1",
  "med_chol_bp_dm_yn.0.2",
  "med_pain_cons_hrt.0.0",
  "med_pain_cons_hrt.0.1",
  "med_pain_cons_hrt.0.2",
  "med_pain_cons_hrt.0.3",
  "med_pain_cons_hrt.0.4",
  "sedentary_total_hours"
)

to_other_vars <- c(
  "eth_bg.0.0",
  "mh_loneliness.0.0",
  "sex.0.0",
  "mh_social_support_confide.0.0",
  "dis_diabetes_doc_yn.0.0",
  "dis_cancer_doc_yn.0.0",
  "dis_cvd_doc_yn",
  "sur_major_surgery.0.0",
  "sleep_insomnia.0.0"
)

vars_with_nonresponse <- intersect(vars_with_nonresponse, names(df))
to_other_vars <- intersect(to_other_vars, names(df))

nonresponse_pattern <- "(?i)(prefer\\s*not\\s*to\\s*answer|do\\s*not\\s*know)"

for (v in vars_with_nonresponse) {
  x <- df[[v]]
  if (!(is.character(x) || is.factor(x))) next
  
  x_chr <- as.character(x)
  idx <- grepl(nonresponse_pattern, x_chr, perl = TRUE)
  
  if (v %in% to_other_vars) {
    x_chr[idx] <- "Other"
  } else {
    x_chr[idx] <- NA_character_
  }
  
  df[[v]] <- if (is.factor(x)) factor(x_chr) else x_chr
}

# Greenspace percentage
df$green_greenspace_300m.0.0[
  df$green_greenspace_300m.0.0 < 0 | df$green_greenspace_300m.0.0 > 100
] <- NA

# Natural environment percentage
df$green_natural_300m.0.0[
  df$green_natural_300m.0.0 < 0 | df$green_natural_300m.0.0 > 100
] <- NA

# Domestic garden percentage
df$green_garden_300m.0.0[
  df$green_garden_300m.0.0 < 0 | df$green_garden_300m.0.0 > 100
] <- NA

# Neutrophil percentage
df$neutrophil_percentage.0.0[
  df$neutrophil_percentage.0.0 < 0 | df$neutrophil_percentage.0.0 > 100
] <- NA

#
#
# categorisation of employment status and qualifications
library(dplyr)

df <- df %>%
  mutate(
    current_employ_status = case_when(
      current_employ_status == "In paid employment or self-employed" ~ "Employed",
      current_employ_status == "Retired" ~ "Retired",
      current_employ_status == "Unable to work because of sickness or disability" ~ "Unable to work",
      current_employ_status %in% c(
        "Full or part-time student",
        "Unemployed",
        "Looking after home and/or family",
        "Doing unpaid or voluntary work",
        "None of the above"
      ) ~ "Other not in paid work",
      TRUE ~ NA_character_
    ),
    current_employ_status = factor(
      current_employ_status,
      levels = c("Employed", "Retired", "Other not in paid work", "Unable to work")
    ),
    
    qualifications = case_when(
      qualifications == "College or University degree" ~ "University",
      qualifications %in% c(
        "CSEs or equivalent",
        "O levels/GCSEs or equivalent",
        "A levels/AS levels or equivalent"
      ) ~ "School",
      qualifications %in% c(
        "Other professional qualifications eg: nursing, teaching",
        "NVQ or HND or HNC or equivalent"
      ) ~ "Other",
      qualifications == "None of the above" ~ "None",
      TRUE ~ NA_character_
    ),
    qualifications = factor(
      qualifications,
      levels = c("University", "School", "Other", "None")
    )
  )
# ============================================================
# 9) Save output
# ============================================================
saveRDS(df, "outputs/ukb_collapsed3.rds")