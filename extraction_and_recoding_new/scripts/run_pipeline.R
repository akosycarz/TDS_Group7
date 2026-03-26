UKB_PATH <- "/rds/general/project/hda_25-26/live/TDS/TDS_Group7/extraction_and_recoding/ukb_data.tab"

source("00_config.R")

args <- c(UKB_PATH)
source("1-make_data_dict.R")

args <- c(UKB_PATH)
source("2-extract_selected.R")

source("3-recode_variables_change.R")
source("4-recoding.R")
source("5-collapsing.R")
source("5.5-feature_engineering.R")
source("6-preprocessing.R")
source("7-cleaning.R")

message("⚠  Step 8: submit 8-imputation_full_dataset.R as a PBS job on the HPC.")

source("9-table1.R")
source("10-dataset_splitting.R")

message("⚠  Steps 11a-c: submit 11a/b/c imputation scripts as PBS jobs on the HPC.")

source("11d_relevel_imputed_splits_adjusted_ref.R")

message("⚠  Step 12: submit 12-lasso_stability_selection_model1.R as a PBS job.")
message("⚠  Step 13: submit 13-elastic_net_stability_selection_model1.R as a PBS job.")

source("14-model1_refit_logistic.R")

message("ℹ  Steps 15-16: run Python scripts from the terminal:")
message("     python 15-python-boost.py")
message("     python 16-logistic-python.py")

message("✅ R pipeline complete.")
