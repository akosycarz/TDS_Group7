# Setup library paths and load dependencies
.libPaths(c(Sys.getenv("R_LIBS_USER"), .libPaths()))
suppressPackageStartupMessages({
  library(dplyr)
  library(miceRanger)
  library(future) 
})

# --- HPC CORE ALLOCATION ---
# Detect cores from PBS environment; default to 8 if detection fails
n_cores <- future::availableCores()
print(n_cores)

# Set threading for the underlying 'ranger' Random Forest engine
options(ranger.num.threads = n_cores)
message("Resource Check: Running on ", n_cores, " cores.")

# --- DATA LOADING & CLEANING ---
df <- readRDS("/rds/general/project/hda_25-26/live/TDS/TDS_Group7/extraction_and_recoding/outputs/ukb_cleaned.rds")

# Extract EID and strip rownames to prevent index errors
eid <- if ("eid" %in% names(df)) df$eid else rownames(df)
if (is.null(eid) || length(eid) != nrow(df)) stop("Critical: EID mismatch.")
rownames(df) <- NULL

# Clean column names for R compatibility
names(df) <- gsub("[^[:alnum:]_]", "_", names(df))

# --- VARIABLE SETS ---
# Define groups based on expected causal flow (Exposures -> Biomarkers)
exposures <- c("smoking_status", "alcohol_intake", "household_income", 
               "smoking_pack_years", "sex", "age_at_recruitment", "eth_bg")

biomarkers <- grep("(^crp|^cholesterol|^hba1c|^hdl|^ldl|^triglycerides)", names(df), value = TRUE)

# Variables to keep in the final file but exclude from the imputation engine
core_demo <- c("sex", "dob", "age_at_recruitment", "eth_bg", "yr_imm_uk")
dx_timing <- grep("(^dis_age_|^dis_date_|^date_of_|^mh_|^med_)", names(df), value = TRUE)
health_states <- c("dis_diabetes_doc_yn", "dis_cancer_doc_yn", "mh_BPD_MD", 
                   "mh_neuroticism", "mh_loneliness", "mh_social_support_confide")
other_vars <- c("sur_major_surgery", "attending_assessment_date", "outcome", 
                "pregnant_yn", "hh_income_pre_tax", "qualifications")

all_excluded <- unique(c(core_demo, dx_timing, health_states, other_vars))

# --- FILTERING & PREP ---
# Retain variables with <= 30% missingness + force CRP inclusion
missing_pct <- colMeans(is.na(df))
safe_vars <- names(missing_pct)[missing_pct <= 0.30]
final_impute_vars <- unique(c(safe_vars, "crp"))

# Subset data and convert types for miceRanger (Factors/Numerics only)
df_impute <- df[, unique(c(final_impute_vars, intersect(all_excluded, names(df))))] %>%
  mutate(
    across(where(~inherits(.x, "Date") || inherits(.x, "POSIXt")), as.numeric),
    across(where(is.character), as.factor),
    across(where(is.logical), as.factor)
  )

# --- PREDICTION MATRIX LOGIC ---
# Define directed imputation to avoid circularity (e.g., biomarkers shouldn't predict exposures)
exclude_from_engine <- intersect(all_excluded, names(df_impute))
target_vars <- setdiff(names(df_impute), exclude_from_engine)
pred_list <- list()

for (v in target_vars) {
  if (v %in% exposures) {
    # Exposures only use other exposures as predictors
    pred_list[[v]] <- intersect(setdiff(exposures, v), names(df_impute))
  } else if (v %in% biomarkers) {
    # Biomarkers use both exposures and other biomarkers
    pred_list[[v]] <- intersect(setdiff(c(exposures, biomarkers), v), names(df_impute))
  } else {
    # Standard variables use all available targets
    pred_list[[v]] <- setdiff(target_vars, v)
  }
}

# --- RUN IMPUTATION ---
set.seed(123)
impute_obj <- miceRanger(
  returnModels = TRUE,
  data      = df_impute,
  m         = 1,             # Single dataset for exploration
  maxiter   = 5,
  vars      = pred_list,
  num.trees = 100,
  verbose   = TRUE  # False because we use ranger's internal threading
)

# --- MERGE & SAVE ---
# Extract imputed data, re-attach EIDs, and restore original excluded variables
data_final <- as.data.frame(completeData(impute_obj)[[1]]) %>%
  mutate(eid = eid) %>%
  select(-any_of(exclude_from_engine)) %>%
  left_join(mutate(df[, exclude_from_engine, drop = FALSE], eid = eid), by = "eid") %>%
  mutate(dob = as.Date(dob, origin = "1970-01-01"))

rownames(data_final) <- data_final$eid
data_final$eid <- NULL

saveRDS(data_final, "/rds/general/project/hda_25-26/live/TDS/TDS_Group7/extraction_and_recoding/outputs/ukb_final_ruben_imputed_500k.rds")
message("Process complete. Output saved.")