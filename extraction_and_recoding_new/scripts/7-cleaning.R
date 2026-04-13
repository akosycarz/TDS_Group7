library(dplyr)
library(tibble)

df <- readRDS("../outputs/ukb_collapsed4.rds")

# bring rownames (participant ids) into a column for counting
df <- df %>% rownames_to_column(var = "participant_id")

# Ensure date variables are Date
df <- df %>%
  mutate(
    outcome_date = as.character(outcome),
    outcome_date = na_if(outcome_date, "No"),
    outcome_date = as.Date(outcome_date),
    dis_date_of_cancer.0.0 = as.Date(dis_date_of_cancer.0.0),
    attending_assessment_date.0.0 = as.Date(attending_assessment_date.0.0)
  )

cat("Initial number of participants:", n_distinct(df$participant_id), "\n\n")

# -----------------------------
# Step 1: outcome before assessment
# -----------------------------
flag_outcome_pre_assessment <-
  !is.na(df$outcome_date) &
  !is.na(df$attending_assessment_date.0.0) &
  df$outcome_date < df$attending_assessment_date.0.0

n_remove_step1 <- n_distinct(df$participant_id[flag_outcome_pre_assessment])

cat("Step 1 - Outcome before assessment:\n")
cat("Participants to remove:", n_remove_step1, "\n")
cat("Participants remaining:", n_distinct(df$participant_id) - n_remove_step1, "\n\n")

df <- df %>%
  filter(!flag_outcome_pre_assessment)

# -----------------------------
# Step 2: pregnancy
# -----------------------------
flag_pregnant <-
  !is.na(df$pregnant_yn.0.0) &
  df$pregnant_yn.0.0 == "Yes"

n_remove_step2 <- n_distinct(df$participant_id[flag_pregnant])

cat("Step 2 - Pregnant:\n")
cat("Participants to remove:", n_remove_step2, "\n")
cat("Participants remaining:", n_distinct(df$participant_id) - n_remove_step2, "\n\n")

df <- df %>%
  filter(!flag_pregnant)

# -----------------------------
# Step 3: cancer within 2 years
# -----------------------------
flag_cancer_2y <-
  !is.na(df$dis_date_of_cancer.0.0) &
  !is.na(df$attending_assessment_date.0.0) &
  abs(as.numeric(df$dis_date_of_cancer.0.0 - df$attending_assessment_date.0.0)) <= 730

n_remove_step3 <- n_distinct(df$participant_id[flag_cancer_2y])

cat("Step 3 - Cancer within 2 years of assessment:\n")
cat("Participants to remove:", n_remove_step3, "\n")
cat("Participants remaining:", n_distinct(df$participant_id) - n_remove_step3, "\n\n")

df <- df %>%
  filter(!flag_cancer_2y)

cat("Final number of participants remaining:", n_distinct(df$participant_id), "\n")

# optional: drop helper date column and restore rownames
df <- df %>%
  select(-outcome_date) %>%
  column_to_rownames(var = "participant_id")

# missingness 
#
#
#

# ---- Exclude selected variables from missingness calculation ----
exclude_vars <- c(
  "date_of_death.0.0","dis_date_of_cancer.0.0","dis_chronic_hepatitis.0.0",
  "dis_dt_e10_first.0.0","dis_schizophrenia.0.0",
  "mh_depr_single_icd.0.0","mh_depr_recurrent_icd.0.0",
  "mh_anxiety_phobic_icd.0.0","mh_anxiety_general_icd.0.0",
  "dis_parkinsons_disease.0.0","dis_alzheimers_disease.0.0",
  "dis_multiple_sclerosis.0.0","dis_migraine.0.0","dis_other_headaches.0.0",
  "dis_sleep_disorders.0.0","dis_dt_l10_first.0.0",
  "dis_hypertensive_renal_disease.0.0","dis_hypertensive_heart_renal_disease.0.0",
  "dis_asthma.0.0","dis_crohns_disease.0.0","dis_ulcerative_colitis.0.0",
  "dis_alcoholic_liver_disease.0.0","dis_liver_fibrosis_and_cirrhosis.0.0",
  "dis_psoriasis.0.0","dis_lupus.0.0","dis_rheumatoid_arthritis.0.0",
  "dis_chronic_renal_failure.0.0","age_full_edu.0.0",
  "dis_age_highbp.0.0","dis_age_diabetes.0.0","dis_age_mi.0.0",
  "age_at_recruitment.0.0","dis_age_copd.0.0",
  "dis_age_pulmonary_fibrosis.0.0","dis_history_cancer_tumour.0.0",
  "dis_insulin_dep_diabetes.0.0","dis_non_insulin_dep_diabetes.0.0"
)

# save it as table 
NA_not_missing <- data.frame(
  variable = exclude_vars
)
saveRDS(NA_not_missing, "../outputs/NA_not_missing.rds")

# column missingness 
missing_summary_column <- data.frame(
  variable = names(df),
  missing_n = colSums(is.na(df)),
  missing_pct = round(colMeans(is.na(df)) * 100, 2)
) %>% arrange(desc(missing_pct))


# -------------------------

# remove variables due to column missingness

vars_over35 <- missing_summary_column %>%
  mutate(variable = as.character(variable)) %>%
  filter(missing_pct >= 35 & !variable %in% as.character(exclude_vars)) %>%
  pull(variable)

# identify medication variables
med_vars <- grep("^med_", names(df), value = TRUE)

# remove them from the variables to drop
vars_over35 <- setdiff(vars_over35, med_vars)

df <- df %>%
  select(-all_of(vars_over35))


# remove participants if it has more than 15% missingness
# removing variables NA not because of missing before calculating missingness 

exclude_vars2 <- intersect(exclude_vars, names(df))

df_for_missing <- df %>%
  select(-any_of(exclude_vars2))


# Keep only rows with < 15% missing
missing_prop <- rowMeans(is.na(df_for_missing))
df_new <- df[missing_prop < 0.15, ]

removed_n <- sum(missing_prop >= 0.15)

# checking threshold, in case needed 
# ---- Define thresholds ----
thresholds <- c(0.05, 0.10, 0.15, 0.20, 0.25)

# ---- Create summary table ----
missing_summary_row <- data.frame(
  Threshold = thresholds * 100,
  N_threshold = sapply(thresholds, function(t) sum(missing_prop >= t)),
  Percent_threshold = sapply(thresholds, function(t)
    round(mean(missing_prop >= t) * 100, 2))
)


df_new <- df_new %>%
  rename_with(
    ~ gsub("\\.", "_", .x),
    starts_with("med_")
  )

colnames(df_new) <- gsub("\\.0\\.0$", "", colnames(df_new))

names(df_new) <- gsub("\\.", "_", names(df_new))

saveRDS(df_new, "../outputs/ukb_cleaned.rds")

