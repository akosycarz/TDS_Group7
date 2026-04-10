# =========================================================
# 11_model1_refit_logistic.R
# Purpose: Fit unpenalised logistic regression on the 20% Refit Set
# Workflow:
#   1. Dynamically load stable variables from Script 10
#   2. Fit Total Effect Model (Path C: Exposures only)
#   3. Fit Direct Effect & Path B Model (Path C' & Path B: Exposures + Biomarkers)
# =========================================================

.libPaths(c(Sys.getenv("R_LIBS_USER"), .libPaths()))
suppressPackageStartupMessages({
  library(dplyr)
  library(broom)     
  library(survival)  
})

# 1. Define Paths
base_dir         <- "../outputs"
base_dir_1         <- "../outputs/summary"

refit_data_path  <- file.path(base_dir, "ukb_refit_20_imputed.rds")
stable_vars_path <- file.path(base_dir_1, "model1_stable_variables.csv")

# 2. Load Data
message("Loading refit set and Elastic Net stable variables...")
df_refit    <- readRDS(refit_data_path)
stable_vars <- read.csv(stable_vars_path, stringsAsFactors = FALSE)

# Format the binary outcome
df_refit$y <- ifelse(trimws(as.character(df_refit$outcome)) == "No", 0L, 1L)

# 3. DYNAMICALLY Build Feature Lists (No Hardcoding)
confounders <- c("age_at_recruitment", "sex", "eth_bg")

stable_exposures  <- unique(stable_vars$base_var[stable_vars$var_type == "exposure"])
stable_biomarkers <- unique(stable_vars$base_var[stable_vars$var_type == "biomarker"])
stable_all        <- unique(stable_vars$base_var)

message("Dynamically loaded ", length(stable_exposures), " unique Elastic Net exposures.")
message("Dynamically loaded ", length(stable_biomarkers), " unique Elastic Net biomarkers.")

# 4. Construct Formulas Mathematically
# Path C Model (Total Effect):
formula_total_path_c <- as.formula(
  paste("y ~", paste(c(confounders, stable_exposures), collapse = " + "))
)

# Path C' (Direct Effect) & Path B Model:
formula_direct_and_path_b <- as.formula(
  paste("y ~", paste(c(confounders, stable_all), collapse = " + "))
)

# 5. Fit the Logistic Regression Models
message("Fitting Total Effect Model (Path C: Exposures Only)...")
model_total_path_c <- glm(formula_total_path_c, data = df_refit, family = "binomial")

message("Fitting Direct Effect & Path B Model (Path C' & Path B: Exposures + Biomarkers)...")
model_direct_and_path_b <- glm(formula_direct_and_path_b, data = df_refit, family = "binomial")

# 6. Extract Odds Ratios cleanly using broom::tidy
results_total_path_c <- tidy(model_total_path_c, exponentiate = TRUE, conf.int = TRUE) %>%
  mutate(Model = "Total_Effect_Path_C")

results_direct_and_path_b <- tidy(model_direct_and_path_b, exponentiate = TRUE, conf.int = TRUE) %>%
  mutate(Model = "Direct_Effect_and_Path_B")

message("\n--- Top Results for Total Effect Model ---")
print(head(results_total_path_c %>% arrange(p.value), 10))

# 7. Save Outputs
write.csv(results_total_path_c, 
          file.path(base_dir_1, "model1_refit_ORs_total_effect_pathC.csv"), 
          row.names = FALSE)

write.csv(results_direct_and_path_b, 
          file.path(base_dir_1, "model1_refit_ORs_direct_and_pathB.csv"), 
          row.names = FALSE)

message("\n=== Refit Stage Complete ===")
message("Odds Ratios saved successfully. Ready for Script 29.")