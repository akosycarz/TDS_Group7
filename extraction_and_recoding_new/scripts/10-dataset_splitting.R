# ================================
# Stratified 60/20/20 split by outcome
# Compatible with imputation pipeline
# ================================

library(dplyr)

# ----------------
# 1. Load
# ----------------
df <- readRDS("/rds/general/project/hda_25-26/live/TDS/TDS_Group7/extraction_and_recoding/outputs/ukb_cleaned.rds")

# ----------------
# 2. Binary outcome for stratification
# ----------------
outcome_char <- as.character(df$outcome)

message("Outcome value check:")
message("  'No' (controls)   : ", sum(outcome_char == "No"))
message("  Date/event (cases): ", sum(outcome_char != "No"))
message("  NA                : ", sum(is.na(outcome_char)))

# Remove rows with missing outcome
keep         <- !is.na(outcome_char)
df           <- df[keep, ]
outcome_char <- outcome_char[keep]

# Temporary binary variable for splitting
df$y <- as.integer(outcome_char != "No")

message("Overall case rate: ", round(mean(df$y), 4))

# ----------------
# 3. Stratified split
# ----------------
set.seed(123)

split_strat <- function(idx, p_sel = 0.6, p_ref = 0.2) {
  
  idx <- sample(idx)
  n   <- length(idx)
  
  n1  <- floor(p_sel * n)
  n2  <- floor(p_ref * n)
  
  list(
    selection = idx[1:n1],
    refit     = idx[(n1 + 1):(n1 + n2)],
    test      = idx[(n1 + n2 + 1):n]
  )
}

case_split    <- split_strat(which(df$y == 1))
control_split <- split_strat(which(df$y == 0))

sel_idx  <- sample(c(case_split$selection, control_split$selection))
ref_idx  <- sample(c(case_split$refit,     control_split$refit))
test_idx <- sample(c(case_split$test,      control_split$test))

# ----------------
# 4. Create datasets
# ----------------
df_selection <- df[sel_idx, ]
df_refit     <- df[ref_idx, ]
df_test      <- df[test_idx, ]

# ----------------
# 5. Check balance
# ----------------
message("Selection : ", nrow(df_selection), " | case rate: ",
        round(mean(df_selection$y), 4))

message("Refit     : ", nrow(df_refit), " | case rate: ",
        round(mean(df_refit$y), 4))

message("Test      : ", nrow(df_test), " | case rate: ",
        round(mean(df_test$y), 4))

message("Row totals correct: ",
        nrow(df_selection) + nrow(df_refit) + nrow(df_test) == nrow(df))

# ----------------
# 6. Remove temporary y variable
# ----------------
df_selection$y <- NULL
df_refit$y     <- NULL
df_test$y      <- NULL

# ----------------
# 7. Save
# ----------------
out <- "/rds/general/project/hda_25-26/live/TDS/TDS_Group7/extraction_and_recoding/outputs"

saveRDS(df_selection, file.path(out, "ukb_selection_60_raw.rds"))
saveRDS(df_refit,     file.path(out, "ukb_refit_20_raw.rds"))
saveRDS(df_test,      file.path(out, "ukb_test_20_raw.rds"))

message("Done — selection/refit/test datasets saved.")