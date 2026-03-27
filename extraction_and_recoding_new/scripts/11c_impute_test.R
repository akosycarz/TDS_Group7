# 28c_impute_test.R
# Applies the refit imputation model to the test split.
# The test split never fits its own model — it must remain completely unseen.
# The refit model (ukb_refit_20_impute_model.rds) is used here.

.libPaths(c(Sys.getenv("R_LIBS_USER"), .libPaths()))
suppressPackageStartupMessages({
  library(dplyr)
  library(miceRanger)
  library(future)
})

base        <- "../outputs"
input_path  <- file.path(base, "ukb_test_20_raw.rds")
output_path <- file.path(base, "relevel_ukb_test_20_imputed_copy.rds")
model_path  <- file.path(base, "ukb_refit_20_impute_model.rds")  # refit model, not selection

if (!file.exists(model_path)) stop("Refit imputation model not found at: ", model_path)

n_cores <- future::availableCores()
options(ranger.num.threads = n_cores)
message("Running on ", n_cores, " cores.")

df  <- readRDS(input_path)
eid <- if ("eid" %in% names(df)) df$eid else rownames(df)
if (is.null(eid) || length(eid) != nrow(df)) stop("Critical: EID mismatch.")
rownames(df) <- NULL

message("Test split loaded: ", nrow(df), " rows")

# --- VARIABLE LISTS ---
core_confounders <- c("sex", "age_at_recruitment", "eth_bg")
admin_vars       <- c("dob", "yr_imm_uk")
dx_timing        <- grep("(^dis|^date_of_|^mh_|^med_)", names(df), value = TRUE)
health_states    <- c("dis_diabetes_doc_yn", "dis_cancer_doc_yn", "mh_BPD_MD",
                      "mh_neuroticism", "mh_loneliness", "mh_social_support_confide",
                      "dis_cvd_doc_yn")
other_vars       <- c("sur_major_surgery", "attending_assessment_date", "outcome",
                      "pregnant_yn", "age_full_edu")

never_impute <- unique(c(core_confounders, admin_vars, dx_timing, health_states, other_vars))

# --- FORMAT FOR MODEL COMPATIBILITY ---
df_impute <- df %>%
  mutate(
    across(where(~inherits(.x, "Date") || inherits(.x, "POSIXt")), as.numeric),
    across(where(is.character), as.factor),
    across(where(is.logical), as.factor)
  )

# --- APPLY SAVED REFIT IMPUTATION MODEL ---
refit_impute_obj <- readRDS(model_path)
message("Refit imputation model loaded. Applying to test split...")

impute_obj <- miceRanger::impute(refit_impute_obj, data = df_impute, verbose = TRUE)

message("Return class from impute(): ", paste(class(impute_obj), collapse = ", "))

# --- EXTRACT COMPLETED DATA ---
# completeData() only accepts "miceDefs"; impute() returns "impDefs".
# Extract via $imputedData[[1]] and slot back into df_impute.
if (inherits(impute_obj, "miceDefs")) {
  message("miceDefs — extracting via completeData()")
  imputed_df <- as.data.frame(completeData(impute_obj)[[1]])
  
} else if (inherits(impute_obj, "impDefs")) {
  message("impDefs — extracting via $imputedData[[1]]")
  imp_vals   <- impute_obj$imputedData[[1]]
  imputed_df <- df_impute
  for (col in names(imp_vals)) {
    imputed_df[[col]] <- imp_vals[[col]]
  }
  imputed_df <- as.data.frame(imputed_df)
  
} else {
  stop("Unrecognised class from miceRanger::impute(): ",
       paste(class(impute_obj), collapse = ", "))
}

message("Imputed data frame: ", nrow(imputed_df), " rows x ", ncol(imputed_df), " columns")

# --- CHECK RESIDUAL NAs IN IMPUTATION TARGETS ONLY ---
imputed_cols <- names(impute_obj$imputedData[[1]])
target_cols  <- setdiff(imputed_cols, never_impute)
remaining_na <- sapply(imputed_df[, target_cols, drop = FALSE], function(x) sum(is.na(x)))
if (any(remaining_na > 0)) {
  warning("Residual NAs in imputation target columns: ",
          paste(names(remaining_na[remaining_na > 0]), collapse = ", "))
} else {
  message("No residual NAs in imputation target columns.")
}

# --- RESTORE NEVER-IMPUTED VARIABLES ---
imputed_df$eid <- eid

never_impute_in_df  <- intersect(never_impute, names(df))
never_impute_df     <- df[, never_impute_in_df, drop = FALSE]
never_impute_df$eid <- eid

data_final <- imputed_df %>%
  select(-any_of(setdiff(never_impute, "eid"))) %>%
  left_join(never_impute_df, by = "eid") %>%
  mutate(dob = as.Date(dob, origin = "1970-01-01"))

rownames(data_final) <- data_final$eid
data_final$eid <- NULL

message("Test imputation complete.")
message("Output rows    : ", nrow(data_final))
message("Output columns : ", ncol(data_final))

saveRDS(data_final, output_path)
message("Saved to: ", output_path)