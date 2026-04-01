# TDS Group 7 — CVD Prediction 
## UK Biobank Analysis: Cardiovascular Disease Event Prediction

---

## Overview

This pipeline processes UK Biobank (UKB) data to investigate incident cardiovascular disease (CVD), covering the full workflow from data extraction, recoding, feature engineering, and preprocessing through imputation, variable selection, multi-model prediction (logistic regression, XGBoost, and neural networks), mediation analysis, and model evaluation.

---

## How to Run

Run the shell scripts below in order from the project root (extraction_and_recoding_new/).
Each .sh file submits the corresponding .R or .py script to the HPC scheduler.

## Input data paths
2-extract_selected.sh contains the path to the synthetic UK Biobank dataset used by its corresponding script.
5-collapsing.sh contains the path to the synthetic CVD events outcome dataset used by its corresponding script.

### Step-by-step execution order

| Step | Shell script | Underlying script |
|------|--------------|------------------|
| 1 | `2-extract_selected.sh` | `2-extract_selected.R` |
| 2 | `3-recode_changed.sh` | `3-recode_variables_change.R` |
| 3 | `4-recoding.sh` | `4-recoding.R` |
| 4 | `5-collapsing.sh` | `5-collapsing.R` |
| 5 | `5.5-feature_engineering.sh` | `5.5-feature_engineering.R` |
| 6 | `6-preprocessing.sh` | `6-preprocessing.R` |
| 7 | `6.5-releveling.sh` | `6.5-releveling.R` |
| 8 | `7-cleaning.sh` | `7-cleaning.R` |
| 9 | `7.5-plot_labels.sh` | `7.5-plot_labels.R` |
| 10 | `7.6-plot_functions.sh` | `7.6-plot_functions.R` |
| 11 | `8-imputation_full_dataset.sh` | `8-imputation_full_dataset.R` |
| 12 | `9-table1.sh` | `9-table1.R` |
| 13 | `10-imputation_split_dataset.sh` | `10-dataset_splitting.R` |
| 14 | `11a_selection_imputation.sh` | `11a_impute_selection.R` |
| 15 | `11b_refit_imputation.sh` | `11b_impute_refit.R` |
| 16 | `11c_test_imputation.sh` | `11c_impute_test.R` |
| 17 | `12-lasso_stability_selection_model1.sh` | `12-lasso_stability_selection_model1.R` |
| 18 | `13-elastic_stability_selection_model1.sh` | `13-elastic_net_stability_selection_model1.R` |
| 19 | `14-model1_refit_logistic.sh` | `14-model1_refit_logistic.R` |
| 20 | `15-python-boost.sh` | `15-python-boost.py` |
| 21 | `16-python_xgboost_602020.sh` | `16-python_xgboost_602020.py` |
| 22 | `17-neural_network.sh` | `17-neural_network.py` |
| 23 | `18-final_analysis_mediation.sh` | `18-final_analysis_mediation.R` |
| 24 | `19-mediation_dag_figures.sh` | `19-mediation_dag_figures.R` |
| 25 | `20-mediation_figures_heatmaps.sh` | `20-mediation_figures_heatmaps.R` |
| 26 | `21-lasso_forest.sh` | `21-lasso_forest.R` |
| 27 | `22-lasso_incremental.sh` | `22-lasso_incremental.R` |
| 28 | `23-elastic_net_forest.sh` | `23-elastic_net_forest.R` |
| 29 | `24-elastic_net_incremental.sh` | `24-elastic_net_incremental.R` |
| 30 | `25-uni_analysis_combined.sh` | `25-uni_analysis_combined.R` |
| 31 | `26-forest_plot_combined.sh` | `26-forest_plot_combined.R` |
| 32 | `27-comparison_ROC.sh` | `27-comparison_ROC.R` |
| 33 | `28-PCA.sh` | `28-PCA.R` |
| 34 | `29-xgboost-analysis.sh` | `29-xgboost-analysis.R` |

---

## Pipeline Summary

| Stage | Script | Input Files | Output Files |
|---|---|---|---|
| 1 | `2-extract_selected.R` | `selection.xlsx`<br>`Codings.csv`<br>`UKB raw file` | `annot.rds`<br>`ukb_extracted.rds`<br>`codes_<ID>.txt`<br>`codes_template_continuous.txt` |
| 2 | `3-recode_variables_change.R` | `annot.rds`<br>`ukb_extracted.rds`<br>`codes_<ID>.txt`<br>`codes_field*` | `ukb_recoded_changed.rds`<br>`parameters_changed.xlsx` |
| 3 | `4-recoding.R` | `ukb_recoded_changed.rds`<br>`annot.rds` | `ukb_recoded_by_script.rds` |
| 4 | `5-collapsing.R` | `ukb_recoded_changed.rds` | `ukb_collapsed.rds` |
| 5 | `5.5-feature_engineering.R` | `ukb_collapsed.rds` | `ukb_collapsed2.rds` |
| 6 | `6-preprocessing.R` | `ukb_collapsed2.rds` | `ukb_collapsed3.rds` |
| 7 | `6.5-releveling.R` | `ukb_collapsed3.rds` | `ukb_collapsed4.rds` |
| 8 | `7-cleaning.R` | `ukb_collapsed4.rds` | `NA_not_missing.rds`<br>`ukb_cleaned.rds` |
| 9 | `7.5-plot_labels.R` | `ukb_collapsed4.rds` | `plot_labels_domain.csv` |
| 10 | `7.6-plot_functions.R` | `plot_labels_domain.csv` | `None directly` |
| 11 | `8-imputation_full_dataset.R` | `ukb_cleaned.rds` | `ukb_final_imputed.rds` |
| 12 | `9-table1.R` | `ukb_cleaned.rds`<br>`ukb_final_imputed.rds` | `table1_before_imputation.png`<br>`table1_imputed.png` |
| 13 | `10-dataset_splitting.R` | `ukb_cleaned.rds` | `ukb_selection_60_raw.rds`<br>`ukb_refit_20_raw.rds`<br>`ukb_test_20_raw.rds` |
| 14 | `11a_impute_selection.R` | `ukb_selection_60_raw.rds` | `ukb_selection_60_imputed.rds`<br>`ukb_selection_60_impute_model.rds` |
| 15 | `11b_impute_refit.R` | `ukb_refit_20_raw.rds` | `ukb_refit_20_imputed.rds`<br>`ukb_refit_20_impute_model.rds` |
| 16 | `11c_impute_test.R` | `ukb_test_20_raw.rds`<br>`ukb_refit_20_impute_model.rds` | `ukb_test_20_imputed.rds` |
| 17 | `12-lasso_stability_selection_model1.R` | `ukb_selection_60_imputed.rds` | `model1_lasso_stability_object.rds`<br>`model1_lasso_stability_summary.csv`<br>`model1_lasso_stable_variables.csv`<br>`model1_lasso_all_selection_proportions.csv`<br>`model1_lasso_stable_exposures.csv`<br>`model1_lasso_calibration_plot.pdf`<br>`model1_lasso_selection_proportions.pdf` |
| 18 | `13-elastic_net_stability_selection_model1.R` | `ukb_selection_60_imputed.rds` | `model1_stability_object.rds`<br>`model1_stability_summary.csv`<br>`model1_stable_variables.csv`<br>`model1_all_selection_proportions.csv`<br>`model1_stable_exposures.csv`<br>`model1_calibration_plot.pdf`<br>`model1_selection_proportions.pdf` |
| 19 | `14-model1_refit_logistic.R` | `ukb_refit_20_imputed.rds`<br>`model1_stable_variables.csv` | `model1_refit_ORs_total_effect_pathC.csv`<br>`model1_refit_ORs_direct_and_pathB.csv` |
| 20 | `15-python-boost.py` | `ukb_final_imputed.rds` | `shap_incremental_auc.png`<br>`metrics_comparison.csv`<br>`selected_features.txt`<br>`shap_importance.csv`<br>`model_comparison.png`<br>`confusion_matrices.png`<br>`precision_recall.png`<br>`shap_beeswarm.png`<br>`shap_importance.png`<br>`shap_incrementation.png`<br>`cv_history.png`<br>`report_xgboost.pdf` |
| 21 | `16-python_xgboost_602020.py` | `model1_lasso_stability_summary.csv`<br>`model1_stability_summary.csv`<br>`ukb_selection_60_imputed.rds`<br>`ukb_refit_20_imputed.rds`<br>`ukb_test_20_imputed.rds` | `XGBoost_results/shap_incremental_auc.png`<br>`XGBoost_results/metrics_comparison.csv`<br>`XGBoost_results/selected_features.txt`<br>`XGBoost_results/shap_importance.csv`<br>`XGBoost_results/model_comparison.png`<br>`XGBoost_results/confusion_matrices.png`<br>`XGBoost_results/precision_recall.png`<br>`XGBoost_results/shap_beeswarm.png`<br>`XGBoost_results/shap_importance.png`<br>`XGBoost_results/shap_incrementation.png`<br>`XGBoost_results/cv_history.png`<br>`XGBoost_results/report_xgboost.pdf` |
| 22 | `17-neural_network.py` | `ukb_selection_60_imputed.rds`<br>`ukb_refit_20_imputed.rds`<br>`ukb_test_20_imputed.rds` | `NN_results/nn_training_curve.png`<br>`NN_results/nn_results.png`<br>`NN_results/nn_confusion_matrices.png`<br>`NN_results/nn_cv_auc.png`<br>`NN_results/nn_metrics.csv`<br>`NN_results/nn_best_weights.pt` |
| 23 | `18-final_analysis_mediation.R` | `ukb_refit_20_imputed.rds`<br>`model1_stable_variables.csv`<br>`model1_refit_ORs_total_effect_pathC.csv`<br>`model1_refit_ORs_direct_and_pathB.csv` | `model1_mediation_indirect_effects_FINAL_6.csv` |
| 24 | `19-mediation_dag_figures.R` | `model1_mediation_indirect_effects_FINAL_6.csv`<br>`plot_labels_domain.csv` | `mediation_fig_dags.pdf` |
| 25 | `20-mediation_figures_heatmaps.R` | `model1_mediation_indirect_effects_FINAL_6.csv`<br>`plot_labels_domain.csv` | `mediation_fig_heatmaps.pdf` |
| 26 | `21-lasso_forest.R` | `model1_lasso_stable_variables.csv`<br>`plot_labels_domain.csv`<br>`ukb_refit_20_imputed.rds` | `total_lasso_logistic_summary.csv`<br>`total_lasso_subsample_summary.csv`<br>`total_lasso_forest_all.pdf`<br>`direct_lasso_logistic_summary.csv`<br>`direct_lasso_subsample_summary.csv`<br>`direct_lasso_forest_exposure.pdf` |
| 27 | `22-lasso_incremental.R` | `model1_lasso_stable_variables.csv`<br>`plot_labels_domain.csv`<br>`ukb_refit_20_imputed.rds`<br>`ukb_test_20_imputed.rds` | `lasso_incremental_auc_summary_exposure.csv`<br>`lasso_incremental_auc_summary_all.csv`<br>`lasso_incremental_auc_exposure.png`<br>`lasso_incremental_auc_all.png` |
| 28 | `23-elastic_net_forest.R` | `model1_stable_variables.csv`<br>`plot_labels_domain.csv`<br>`ukb_refit_20_imputed.rds` | `total_elastic_net_logistic_summary.csv`<br>`total_elastic_net_subsample_summary.csv`<br>`total_elastic_net_forest_all.pdf`<br>`direct_elastic_net_logistic_summary.csv`<br>`direct_elastic_net_subsample_summary.csv`<br>`direct_elastic_net_forest_exposure.pdf` |
| 29 | `24-elastic_net_incremental.R` | `model1_stable_variables.csv`<br>`plot_labels_domain.csv`<br>`ukb_refit_20_imputed.rds`<br>`ukb_test_20_imputed.rds` | `elastic_net_incremental_auc_summary_exposure.csv`<br>`elastic_net_incremental_auc_summary_all.csv`<br>`elastic_net_incremental_auc_exposure.png`<br>`elastic_net_incremental_auc_all.png` |
| 30 | `25-uni_analysis_combined.R` | `ukb_final_imputed.rds` | `uni_analysis_combined.csv`<br>`uni_analysis_combined_table.csv` |
| 31 | `26-forest_plot_combined.R` | `uni_analysis_combined.csv`<br>`plot_labels_domain.csv` | `forest_<domain>.pdf` |
| 32 | `27-comparison_ROC.R` | `model1_lasso_stable_variables.csv`<br>`model1_stable_variables.csv`<br>`selected_features.txt`<br>`ukb_refit_20_imputed.rds`<br>`ukb_test_20_imputed.rds` | `model_comparison_auc_summary.csv`<br>`model_comparison_roc.png`<br>`model_comparison_roc_points.csv` |
| 33 | `28-PCA.R` | `ukb_selection_60_imputed.rds` | `PCA_results/pca_case_control.png`<br>`PCA_results/pca_sex.png`<br>`PCA_results/pca_age.png`<br>`PCA_results/pca_ethnicity.png`<br>`PCA_results/scree_plot.png`<br>`PCA_results/cumulative_variance.png`<br>`PCA_results/loadings_plot.png`<br>`PCA_results/pca_variance_explained.csv`<br>`PCA_results/pca_loadings_all.csv`<br>`PCA_results/pca_scores_first5PCs.csv` |
| 34 | `29-xgboost-analysis.R` | `model1_lasso_stability_summary.csv`<br>`model1_stability_summary.csv`<br>`XGBoost_results/shap_importance.csv`<br>`ukb_refit_20_imputed.rds`<br>`ukb_test_20_imputed.rds`<br>`7.6-plot_functions.R` | `xgboost_shap_refit_forest.pdf`<br>`xgboost_shap_subsample_summary.csv`<br>`xgboost_shap_incremental_auc_summary.csv`<br>`xgboost_shap_incremental_auc.png` |

---

## Pipeline Dependency Overview

```
Raw UKB .tab
   │
   ├── Data Extraction & Processing
   │     ├── 2-extract_selected.R
   │     ├── 3-recode_variables_change.R
   │     ├── 4-recoding.R
   │     ├── 5-collapsing.R
   │     ├── 5.5-feature_engineering.R
   │     ├── 6-preprocessing.R
   │     ├── 6.5-releveling.R
   │     └── 7-cleaning.R
   │           └── ukb_cleaned.rds
   │
   ├── Imputation
   │     └── 8-imputation_full_dataset.R
   │           └── ukb_final_imputed.rds
   │
   ├── Dataset Splitting
   │     └── 10-dataset_splitting.R
   │           ├── ukb_selection_60_raw.rds
   │           ├── ukb_refit_20_raw.rds
   │           └── ukb_test_20_raw.rds
   │
   ├── Split-specific Imputation
   │     ├── 11a_impute_selection.R  ──► ukb_selection_60_imputed.rds
   │     ├── 11b_impute_refit.R      ──► ukb_refit_20_imputed.rds
   │     └── 11c_impute_test.R       ──► ukb_test_20_imputed.rds
   │
   ├── Variable Selection
   │     ├── 12-lasso_stability_selection_model1.R
   │     └── 13-elastic_net_stability_selection_model1.R
   │
   ├── Predictive Modelling
   │     ├── 14-model1_refit_logistic.R
   │     ├── 16-python_xgboost_602020.py
   │     └── 17-neural_network.py
   │
   ├── Mediation Analysis
   │     └── 18-final_analysis_mediation.R
   │
   └── Visualisation & Evaluation
         ├── PCA (28-PCA.R)
         ├── Forest plots (21–24)
         ├── ROC comparison (27)
         └── Mediation figures (19–20)
                                                                      
```

---

## Pipeline Documentation

###  Variable Extraction (`2-extract_selected.R`)
Inputs: 
-`selection.xlsx`
-`Codings.csv`
-`tabular.tsv`(path specified in the corresponding .sh script)

Outputs:
- `annot.rds`
- `ukb_extracted.rd`
- `codes_<codeID>.txt`
- `codes_template_continuous.txt`

Reads `selection.xlsx`, extracts the selected fields and instances from `tabular.csv`, and saves:
- `outputs/ukb_extracted.rds` — extracted dataset
- `outputs/annot.rds` — annotation/metadata for each variable
- `parameters/codings/codes_<ID>.txt` — coding lookup tables

---

###  Recoding (`3-recode_variables_change.R`)
Inputs: 
- `annot.rds`
- `ukb_extracted.rds`
- `codes_<tmp_coding_id>.txt`
- `codes_field*`

Outputs:
- `parameters_changed.xlsx`
- `ukb_recoded_changed.rds`

Reads `outputs/ukb_extracted.rds` → saves `outputs/ukb_recoded_changed.rds`

Applies UKB coding files to recode values. Converts:
- Categorical variables to labelled factors
- Integer/continuous columns to numeric
- Date columns to `Date` type

---

###  Script-Level Recoding (`4-recoding.R`)
Inputs: 
- `ukb_recoded_changed.rds`
- `annot.rds`

Outputs:
- `ukb_recoded_by_script.rds`

Applies **custom collapsing** of specific UKB coding IDs (e.g. ethnicity grouping, smoking status, alcohol frequency, medication categories). 

---

###  Collapsing (`5-collapsing.R`)
Inputs: 
- `ukb_recoded_changed.rds`
- `cvd_events.rds` (path specified in the corresponding .sh script)

Outputs:
- `ukb_collapsed.rds`

Collapses multi-reading/multi-array variables into single summary columns:
- **Systolic & diastolic BP**: mean of automated readings, fallback to manual
- **FVC / FEV1**: best of three blows
- **Qualifications / Employment**: highest-priority category across array slots
- **CVD outcome**: merges in `cvd_events.rds` (date of first event or `"No"`)

---

### Feature Engineering (`5.5-feature_engineering.R`)
Inputs: 
- `ukb_collapsed.rds`

Outputs:
- `ukb_collapsed2.rds`

Creates derived composite variables:
| New Variable | Description |
|---|---|
| `sedentary_total_hours` | Sum of TV + computer + driving hours/day |
| `diet_score` | Composite 6-domain diet quality score (0–5 per domain) |
| `alcohol_status_with_freq` | Combined drinker status + frequency category |
| `smoking_status` / `smoking_pack_years` | Cleaned smoking variables |

---

###  Preprocessing (`6-preprocessing.R`)
Inputs: 
- `ukb_collapsed2.rds`

Outputs:
- `ukb_collapsed3.rds`

- Converts sentinel values (e.g. `-999909999`) to `NA`
- Range checks (e.g. `sys_bp > 250 → NA`)
- Sets negative biochemistry values to `NA`
- Bands continuous variables into categories (BMI, body fat %, sleep duration, water intake, etc.)
- Converts selected variables to numeric
- Converts remaining character columns to factors
- Maps `"Prefer not to answer"` / `"Do not know"` → `NA` or `"Other"` depending on variable

---

### Releveling (`6.5-releveling.R`)
Inputs: 
- `ukb_collapsed3.rds`

Outputs:
- `ukb_collapsed4.rds`

- Sets consistent reference levels for selected categorical variables
- Relevels factors before downstream modelling
- Uses predefined baseline categories for demographic, lifestyle, and health variables
- Reports missing variables or unavailable reference levels during processing

---

###  Cleaning & Exclusions (`7-cleaning.R`)
Inputs: 
- `ukb_collapsed4.rds`

Outputs:
- `NA_not_missing.rds`
- `ukb_cleaned.rds`

Applies three sequential exclusion criteria:

| Step | Criterion | Rationale |
|---|---|---|
| 1 | CVD event before assessment date | Prevalent disease at baseline |
| 2 | Pregnant at recruitment | Confounding |
| 3 | Cancer diagnosis within ±2 years of assessment | Competing risk / confounding |

Then applies **missingness filtering**:
- Drops variables with ≥ 35% missing (excluding clinical date/diagnostic variables)
- Drops participants with ≥ 15% missing (excluding the same clinical variables)
- Renames columns: strips `.0.0` suffix, replaces `.` with `_`

---

### Plot Label and Domain Mapping Table (`7.5-plot_labels.R`)
Inputs:
- `ukb_collapsed4.rds`

Outputs:
- `plot_labels_domain.csv`

Creates a lookup table for variable labels, domains, and domain colours used in downstream figures and tables. Reads the collapsed dataset to obtain variable names, standardises medication column names, assigns human-readable plot labels and domain groupings, adds predefined domain colours, checks for variables missing domain assignments, and exports the final mapping table as `plot_labels_domain.csv`.

---

### Shared Plot Functions (`7.6-plot_functions.R`)
Inputs:
- `plot_labels_domain.csv`

Outputs:
- None directly *(provides reusable plotting functions for other scripts)*

Defines shared domain mappings, colour palettes, variable label loading, and reusable plotting functions for downstream analyses. Provides a forest plot function for subsample stability results and an incremental AUC plot function, with labels loaded from `plot_labels_domain.csv` and formatting standardised across LASSO, elastic net, and XGBoost SHAP scripts.

---

###  Full Dataset Imputation (`8-imputation_full_dataset.R`)
Inputs: 
- `ukb_cleaned.rds`

Outputs:
- `ukb_final_imputed.rds`

Runs `miceRanger` (random-forest multiple imputation) on the full cleaned dataset.

- Directed imputation: exposures predicted only by other exposures; biomarkers by exposures + other biomarkers
- `m = 1` imputed dataset, `maxiter = 5`, `num.trees = 100`
- Excluded from imputation engine: demographics, dates, health states, outcome

---

### Table 1 (`9-table1.R`)
Inputs: 
- `ukb_cleaned.rds`
- `ukb_final_imputed.rds`

Outputs:
- `table1_before_imputation.png`
- `table1_imputed.png`

Variables shown: Sex, Age, Ethnicity, BMI category, Systolic BP, Diastolic BP

P-values: t-test (continuous), chi-squared / Fisher's exact (categorical)

---

### Dataset Splitting (`10-dataset_splitting.R`)
Inputs: 
- `ukb_cleaned.rds`

Outputs:
`ukb_selection_60_raw.rds`
`ukb_refit_20_raw.rds`
`ukb_test_20_raw.rds`

Stratified split by CVD event status:

| Split | Proportion | Purpose |
|---|---|---|
| Selection | 60% | Variable selection (LASSO / Elastic Net) |
| Refit | 20% | Fit final unpenalised logistic regression |
| Test | 20% | Held-out evaluation |

---

### Split-Specific Imputation (`11a/b/c`)
Inputs:
`ukb_selection_60_raw.rds`
`ukb_refit_20_raw.rds`
`ukb_test_20_raw.rds`

Outputs:
`ukb_selection_60_imputed.rds`
`ukb_refit_20_imputed.rds`
`ukb_test_20_imputed.rds`

Each split is imputed independently using the same predictor matrix logic as Stage 10:

| Script | Split | Action |
|---|---|---|
| `11a_impute_selection.R` | 60% selection | Fits + saves imputation model |
| `11b_impute_refit.R` | 20% refit | Fits + saves imputation model |
| `11c_impute_test.R` | 20% test | Applies **refit model** (no new fitting) |

---

### Variable Selection: LASSO (`12-lasso_stability_selection_model1.R`)
Inputs: 
-`ukb_selection_60_imputed.rds`

Outputs:
- `model1_lasso_stability_object.rds`
- `model1_lasso_stability_summary.csv`
- `model1_lasso_stable_variables.csv`
- `model1_lasso_all_selection_proportions.csv`
- `model1_lasso_stable_exposures.csv`
- `model1_lasso_calibration_plot.pdf`
- `model1_lasso_selection_proportions.pdf`

Stability selection using the `sharp` package with LASSO (`alpha = 1`):
- `K = 100` subsamples, `tau = 0.5`
- Confounders (age, sex, ethnicity) are **unpenalised**
- Calibration via `Argmax()` to select optimal `(lambda, pi)` pair

---

### Variable Selection: Elastic Net (`13-elastic_net_stability_selection_model1.R`)
Inputs: 
-`ukb_selection_60_imputed.rds`

Outputs:
- `model1_stability_object.rds`
- `model1_stability_summary.csv`
- `model1_stable_variables.csv`
- `model1_all_selection_proportions.csv`
- `model1_stable_exposures.csv`
- `model1_calibration_plot.pdf`
- `model1_selection_proportions.pdf`

Same stability selection framework but with **tuned alpha**:
- `alpha` optimised via `cv.glmnet` with 10-fold CV over `[0, 1]`
- Otherwise identical structure to LASSO script

---

### Logistic Regression Refit (`14-model1_refit_logistic.R`)
Inputs: 
-`ukb_refit_20_imputed.rds`
-`model1_stable_variables.csv`

Outputs:
- `model1_refit_ORs_total_effect_pathC.csv`
- `model1_refit_ORs_direct_and_pathB.csv`

Fits **unpenalised logistic regression** on the 20% refit set using variables selected in Stage 15/16:

| Model | Predictors |
|---|---|
| RQ1 (exposures only) | Confounders + stable exposures |
| Mediation Path B | Confounders + stable exposures + stable biomarkers |

---

### XGBoost For sensitivity analysis  (`15-python-boost.py`)
Inputs: 
-`ukb_final_imputed.rds`

Outputs:
- `shap_incremental_auc.png`
- `metrics_comparison.csv`
- `selected_features.txt`
- `shap_importance.csv`
- `model_comparison.png`
- `confusion_matrices.png`
- `precision_recall.png`
- `shap_beeswarm.png`
- `shap_importance.png`
- `shap_incrementation.png`
- `cv_history.png`
- `report_xgboost.pdf`

Gradient boosted tree model with:
- **Optuna** hyperparameter tuning (`N_TRIALS = 50`, 5-fold CV)
- **SHAP** feature importance (top 20 features)
- Youden's J threshold optimisation
- Full PDF report with ROC, PR curve, confusion matrices, SHAP plots

---

### XGBoost Main Analysis (`16-python_xgboost_602020.py`)
Inputs: 
-`model1_lasso_stability_summary.csv`
-`model1_stability_summary.csv`
-`ukb_selection_60_imputed.rds`
-`ukb_refit_20_imputed.rds`
-`ukb_test_20_imputed.rds`

Outputs:
- `XGBoost_results/shap_incremental_auc.png`
- `XGBoost_results/metrics_comparison.csv`
- `XGBoost_results/selected_features.txt`
- `XGBoost_results/shap_importance.csv`
- `XGBoost_results/model_comparison.png`
- `XGBoost_results/confusion_matrices.png`
- `XGBoost_results/precision_recall.png`
- `XGBoost_results/shap_beeswarm.png`
- `XGBoost_results/shap_importance.png`
- `XGBoost_results/shap_incrementation.png`
- `XGBoost_results/cv_history.png`
- `XGBoost_results/report_xgboost.pdf`

Gradient boosted tree model with:
- **Optuna** hyperparameter tuning (`N_TRIALS = 50`, 5-fold CV)
- **SHAP** feature importance (top 20 features)
- Youden's J threshold optimisation
- Full PDF report with ROC, PR curve, confusion matrices, SHAP plots

---

### Neural Network (`17-neural_network.py`)
Inputs: 
-`ukb_selection_60_imputed.rds`
-`ukb_refit_20_imputed.rds`
-`ukb_test_20_imputed.rds`

Outputs:
- `NN_results/nn_training_curve.png`
- `NN_results/nn_results.png`
- `NN_results/nn_confusion_matrices.png`
- `NN_results/nn_cv_auc.png`
- `NN_results/nn_metrics.csv`
- `NN_results/nn_best_weights.pt`

Feed-forward neural network (MLP) model with:
- Weighted loss to address class imbalance
- Early stopping using the refit set
- 5-fold CV AUC within the selection set
- Youden’s J threshold optimisation
- Full PDF report with training curves, ROC, PR curve, F1-threshold plot, and confusion matrices

---

### Mediation Analysis (`18-final_analysis_mediation.R`)
Inputs: 
-`ukb_refit_20_imputed.rds`
-`model1_stable_variables.csv`
-`model1_refit_ORs_total_effect_pathC.csv`
-`model1_refit_ORs_direct_and_pathB.csv`

Outputs
- `model1_mediation_indirect_effects_FINAL_6.csv`

High-dimensional mediation analysis linking stable external exposures, selected biomarkers, and CVD with:
- Step 2 stability selection for exposure → biomarker pathways using SHARP
- Alpha tuning via stability score optimisation 
- Path A estimation from linear models adjusted for confounders
- Path B, direct effect and total effect 
- Bootstrapped indirect effects (R = 1000) with 95% bootstrap confidence intervals
- Mediation pathway classification based on stability-selection status only: Partial Mediation (Primary), Full Mediation (Primary), Indirect Only (Path A)

---

### Mediation DAG Figures (`19-mediation_dag_figures.R`)
Inputs:
-`model1_mediation_indirect_effects_FINAL_6.csv`
-`plot_labels_domain.csv
`

Outputs:
-`mediation_fig_dags.pdf`

Generates labelled DAG-style visualisations for the mediation analysis, grouped by exposure domain.

---

### Mediation Heatmap Figures (`20-mediation_figures_heatmaps.R`)
Inputs:
-`model1_mediation_indirect_effects_FINAL_6.csv`
-`plot_labels_domain.csv`

Outputs:
-`mediation_fig_heatmaps.pdf`

Generates heatmap visualisations for the mediation analysis, summarising both total and indirect effects across exposures and biomarkers.

---

### Total + Direct LASSO Logistic Refit (`21-lasso_forest.R`)
Inputs:
- `model1_lasso_stable_variables.csv`
- `plot_labels_domain.csv`
- `ukb_refit_20_imputed.rds`

Outputs:
- `total_lasso_logistic_summary.csv`
- `total_lasso_subsample_summary.csv`
- `total_lasso_forest_all.pdf`
- `direct_lasso_logistic_summary.csv`
- `direct_lasso_subsample_summary.csv`
- `direct_lasso_forest_exposure.pdf`

Refits standard logistic regression models on the refit dataset using variables selected from LASSO stability selection, for both total and direct effect analyses. Performs repeated 50% subsampling to assess coefficient robustness, saves full-data odds ratios and subsampling summaries, and generates forest plots based on median and IQR estimates.

---

### LASSO Incremental AUC Plot (`22-lasso_incremental.R`)
Inputs:
- `model1_lasso_stable_variables.csv`
- `plot_labels_domain.csv`
- `ukb_refit_20_imputed.rds`
- `ukb_test_20_imputed.rds`

Outputs:
- `lasso_incremental_auc_summary_exposure.csv`
- `lasso_incremental_auc_summary_all.csv`
- `lasso_incremental_auc_exposure.png`
- `lasso_incremental_auc_all.png`

Evaluates incremental predictive performance of the LASSO-selected refit logistic model by adding stable variables cumulatively and calculating test-set AUC at each step. Generates separate summaries and plots for exposure-only models and for all stable variables combined, with exposures added first followed by biomarkers or other non-exposure variables.

---

### Total + Direct Elastic Net Logistic Refit (`23-elastic_net_forest.R`)
Inputs:
- `model1_stable_variables.csv`
- `plot_labels_domain.csv`
- `ukb_refit_20_imputed.rds`

Outputs:
- `total_elastic_net_logistic_summary.csv`
- `total_elastic_net_subsample_summary.csv`
- `total_elastic_net_forest_all.pdf`
- `direct_elastic_net_logistic_summary.csv`
- `direct_elastic_net_subsample_summary.csv`
- `direct_elastic_net_forest_exposure.pdf`

Refits standard logistic regression models on the refit dataset using variables selected from elastic net stability selection, for both total and direct effect analyses. Performs repeated 50% subsampling to assess coefficient robustness, saves full-data odds ratios and subsampling summaries, and generates forest plots based on median and IQR estimates.

---

### Elastic Net Incremental AUC Plot (`24-elastic_net_incremental.R`)
Inputs:
- `model1_stable_variables.csv`
- `plot_labels_domain.csv`
- `ukb_refit_20_imputed.rds`
- `ukb_test_20_imputed.rds`

Outputs:
- `elastic_net_incremental_auc_summary_exposure.csv`
- `elastic_net_incremental_auc_summary_all.csv`
- `elastic_net_incremental_auc_exposure.png`
- `elastic_net_incremental_auc_all.png`

Evaluates incremental predictive performance of the elastic net-selected refit logistic model by adding stable variables cumulatively and calculating test-set AUC at each step. Generates separate summaries and plots for exposure-only models and for all stable variables combined, with exposures added first followed by biomarkers or other non-exposure variables.

---

### Univariate Adjusted Analysis (`25-uni_analysis_combined.R`)
Inputs:
- `ukb_final_imputed.rds`

Outputs:
- `uni_analysis_combined.csv`
- `uni_analysis_combined_table.csv`

Runs adjusted univariate logistic regression for each predictor in the imputed dataset, with adjustment for age at recruitment, sex, and ethnic background. Combines continuous and categorical results into a single summary table, preserves existing factor reference groups, applies FDR correction, and exports both a full results file and a publication-ready summary table.

---

### Combined Forest Plots by Domain (`26-forest_plot_combined.R`)
Inputs:
- `uni_analysis_combined.csv`
- `plot_labels_domain.csv`

Outputs:
- `forest_<domain>.pdf` *(one PDF per domain)*

Generates combined forest plots for adjusted univariate analysis results, grouped by domain and saved as one PDF per domain. Each PDF preserves a three-panel layout with variable and level labels, forest plots with domain background colours, and odds ratio text, and splits long domains across pages while keeping all rows for each variable together.

---

### ROC Curve Comparison (`27-comparison_ROC.R`)
Inputs:
- `model1_lasso_stable_variables.csv`
- `model1_stable_variables.csv`
- `selected_features.txt`
- `ukb_refit_20_imputed.rds`
- `ukb_test_20_imputed.rds`

Outputs:
- `model_comparison_auc_summary.csv`
- `model_comparison_roc.png`
- `model_comparison_roc_points.csv`

Compares test-set ROC curves for four logistic regression models: a base model using adjustment variables only, a LASSO-selected model, an elastic net-selected model, and an XGBoost text-selected model. Fits each model on the refit dataset, evaluates performance on the test dataset, saves AUC summaries and ROC curve coordinates, and generates a combined ROC comparison plot.

---

### Full Exposure PCA Analysis (`28-PCA.R`)
Inputs:
- `ukb_selection_60_imputed.rds`

Outputs:
- `PCA_results/pca_case_control.png`
- `PCA_results/pca_sex.png`
- `PCA_results/pca_age.png`
- `PCA_results/pca_ethnicity.png`
- `PCA_results/scree_plot.png`
- `PCA_results/cumulative_variance.png`
- `PCA_results/loadings_plot.png`
- `PCA_results/pca_variance_explained.csv`
- `PCA_results/pca_loadings_all.csv`
- `PCA_results/pca_scores_first5PCs.csv`

Performs principal component analysis on all exposure variables in the imputed selection dataset after excluding the outcome, confounders, ID fields, and `_yn` variables. Converts categorical variables to dummy variables, removes constant columns, runs PCA using `prcomp`, and saves score plots, scree and cumulative variance plots, loading plots, and supporting output tables to `PCA_results`.

---

### XGBoost SHAP Subsample Stability Forest Plot (`29-xgboost-analysis.R`)
Inputs:
- `model1_lasso_stability_summary.csv`
- `model1_stability_summary.csv`
- `XGBoost_results/shap_importance.csv`
- `ukb_refit_20_imputed.rds`
- `ukb_test_20_imputed.rds`
- `7.6-plot_functions.R`

Outputs:
- `xgboost_shap_refit_forest.pdf`
- `xgboost_shap_subsample_summary.csv`
- `xgboost_shap_incremental_auc_summary.csv`
- `xgboost_shap_incremental_auc.png`

Builds a logistic refit model using top-ranked XGBoost SHAP features, where the number of selected features is set dynamically as the maximum number of stable variables identified by LASSO and elastic net stability selection. Repeats the refit over random 50% subsamples to summarise median odds ratios and IQRs for forest plotting, evaluates test-set AUC, and generates an incremental AUC analysis by adding SHAP-ranked features cumulatively.

---

## R Package Requirements

```r
# Data processing
library(data.table)
library(openxlsx)
library(dplyr)
library(tibble)
library(forcats)
library(stringr)
library(readr)

# Modelling
library(glmnet)
library(sharp)
library(miceRanger)
library(future)
library(broom)
library(survival)

# Reporting
library(table1)
library(labelled)
library(htmltools)
library(webshot2)  # or webshot + PhantomJS fallback
```

## Python Package Requirements

```bash
pip install numpy pandas pyreadr matplotlib scikit-learn xgboost shap optuna
```
---
