# TDS Group 7 — CVD Prediction Pipeline (up to imputation) 
## UK Biobank Analysis: Cardiovascular Disease Event Prediction

---

## Overview

This pipeline processes UK Biobank (UKB) data to predict incident cardiovascular disease (CVD) events. It covers the full analytical workflow: from raw data extraction through to variable selection, imputation.

---

## Project Structure

```
docs/
outputs/
parameters/
scripts/
├── 1-make_data_dict.R                 # Build data dictionary from raw UKB basket
├── 2-extract_selected.R               # Extract selected variables & instance
├── 3-recode_variables_change.R        # Recode categorical/continuous variables
├── 4-recoding.R                       # Script-level recoding by coding ID
├── 5-collapsing.R                     # Collapse multi-instance variables + merge CVD outcome
├── 5.5-feature_engineering.R          # Engineer derived features (diet score, sedentary hours, etc.)
├── 6-preprocessing.R                  # Cleaning, banding, type fixing, nonresponse handling
├── 6.5-releveling.R                   # Factor releveling before modelling
├── 7-cleaning.R                       # Exclusion criteria + missingness filtering → ukb_cleaned.rds
├── 8-imputation_full_dataset.R        # miceRanger imputation on full dataset
├── 9-table1.R                         # Generating table1 for exploratory analysis
├── 10-dataset_splitting.R             # Stratified 60/20/20 train/refit/test split
├── 11a_impute_selection.R             # Impute 60% selection split (fits model)
├── 11b_impute_refit.R                 # Impute 20% refit split (fits model)
└── 11c_impute_test.R                  # Apply refit model to 20% test split
---

## How to Run

### Step-by-step execution order (up to imputation)


| Step | Script |
|-----|------|
| 1 | `2-extract_selected.sh` |
| 2 | `3-recode_changed.sh` |
| 3 | `4-recoding.sh` |
| 4 | `5-collapsing.sh` |
| 5 | `5.5-feature_engineering.sh` |
| 6 | `6-preprocessing.sh` |
| 7 | `6.5-releveling.sh` |
| 8 | `7-cleaning.sh` |
| 9 | `8-imputation_full_dataset.sh` |
| 10 | `9-table1.R` |
| 11 | `10-imputation_split_dataset.sh` |
| 12 | `11a_selection_imputation.sh` |
| 13 | `11b_refit_imputation.sh` |
| 14 | `11c_test_imputation.sh` |


## Pipeline Stages

###  Variable Extraction (`2-extract_selected.R`)

Reads `selection.xlsx`, extracts the chosen fields and instances from the raw UKB file, and saves:
- `outputs/ukb_extracted.rds` — extracted dataset
- `outputs/annot.rds` — annotation/metadata for each variable
- `parameters/codings/codes_<ID>.txt` — coding lookup tables

---

###  Recoding (`3-recode_variables_change.R`)
Applies UKB coding files to recode values. Converts:
- Categorical variables to labelled factors
- Integer/continuous columns to numeric
- Date columns to `Date` type

Reads `outputs/ukb_extracted.rds` → saves `outputs/ukb_recoded_changed.rds`

---

###  Script-Level Recoding (`4-recoding.R`)
Applies **custom collapsing** of specific UKB coding IDs (e.g. ethnicity grouping, smoking status, alcohol frequency, medication categories). 
Saves `outputs/ukb_recoded_by_script.rds`.

---

###  Collapsing (`5-collapsing.R`)
Collapses multi-reading/multi-array variables into single summary columns:
- **Systolic & diastolic BP**: mean of automated readings, fallback to manual
- **FVC / FEV1**: best of three blows
- **Qualifications / Employment**: highest-priority category across array slots
- **CVD outcome**: merges in `cvd_events.rds` (date of first event or `"No"`)

Saves `outputs/ukb_collapsed.rds`

---

### Feature Engineering (`5.5-feature_engineering.R`)
Creates derived composite variables:
| New Variable | Description |
|---|---|
| `sedentary_total_hours` | Sum of TV + computer + driving hours/day |
| `diet_score` | Composite 6-domain diet quality score (0–5 per domain) |
| `alcohol_status_with_freq` | Combined drinker status + frequency category |
| `smoking_status` / `smoking_pack_years` | Cleaned smoking variables |

Saves `outputs/ukb_collapsed2.rds`

---

###  Preprocessing (`6-preprocessing.R`)
- Converts sentinel values (e.g. `-999909999`) to `NA`
- Range checks (e.g. `sys_bp > 250 → NA`)
- Sets negative biochemistry values to `NA`
- Bands continuous variables into categories (BMI, body fat %, sleep duration, water intake, etc.)
- Converts selected variables to numeric
- Converts remaining character columns to factors
- Maps `"Prefer not to answer"` / `"Do not know"` → `NA` or `"Other"` depending on variable

Saves `outputs/ukb_collapsed3.rds`

---

### Releveling (`6.5-releveling.R`)
- Loads `outputs/ukb_collapsed3.rds`
- Sets consistent reference levels for selected categorical variables
- Relevels factors before downstream modelling
- Uses predefined baseline categories for demographic, lifestyle, and health variables
- Reports missing variables or unavailable reference levels during processing

Saves `outputs/ukb_collapsed4.rds`

###  Cleaning & Exclusions (`7-cleaning.R`)
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

Saves `/outputs/ukb_cleaned.rds`

---

###  Full Dataset Imputation (`8-imputation_full_dataset.R`)
Runs `miceRanger` (random-forest multiple imputation) on the full cleaned dataset.

- Directed imputation: exposures predicted only by other exposures; biomarkers by exposures + other biomarkers
- `m = 1` imputed dataset, `maxiter = 5`, `num.trees = 100`
- Excluded from imputation engine: demographics, dates, health states, outcome

Saves `outputs/ukb_final_imputed.rds`

---

### Table 1 (`9-table1.R`)
Produces two descriptive tables stratified by CVD event status:
- **Before imputation**: from `ukb_cleaned.rds`
- **After imputation**: from `ukb_final_ruben_imputed_500k.rds`

Variables shown: Sex, Age, Ethnicity, BMI category, Systolic BP, Diastolic BP

P-values: t-test (continuous), chi-squared / Fisher's exact (categorical)

Outputs saved as:
- `outputs/table1_before_imputation.png`
- `outputs/table1_imputed.png`

---

### Dataset Splitting (`10-dataset_splitting.R`)
Stratified split by CVD event status:

| Split | Proportion | Purpose |
|---|---|---|
| Selection | 60% | Variable selection (LASSO / Elastic Net) |
| Refit | 20% | Fit final unpenalised logistic regression |
| Test | 20% | Held-out evaluation |

Saves: `ukb_selection_60_raw.rds`, `ukb_refit_20_raw.rds`, `ukb_test_20_raw.rds`

---

### Split-Specific Imputation (`11a/b/c`)
Each split is imputed independently using the same predictor matrix logic as Stage 10:

| Script | Split | Action |
|---|---|---|
| `11a_impute_selection.R` | 60% selection | Fits + saves imputation model |
| `11b_impute_refit.R` | 20% refit | Fits + saves imputation model |
| `11c_impute_test.R` | 20% test | Applies **refit model** (no new fitting) |

Saves: `ukb_selection_60_imputed.rds`, `ukb_refit_20_imputed.rds`, `ukb_test_20_imputed.rds`


## Key File Dependencies

```
Raw UKB .tab
    └── 1-make_data_dict.R  ──► selection.xlsx (manual editing required)
            └── 2-extract_selected.R  ──► ukb_extracted.rds
                    └── 3-recode_variables_change.R  ──► ukb_recoded_changed.rds
                            └── 4-recoding.R  ──► ukb_recoded_by_script.rds
                                    └── 5-collapsing.R  ──► ukb_collapsed.rds
                                            └── 5.5-feature_engineering.R  ──► ukb_collapsed2.rds
                                                    └── 6-preprocessing.R  ──► ukb_collapsed3.rds
                                                       └── 6.5-releveling.R  ──► ukb_collapsed4.rds
                                                            └── 7-cleaning.R  ──► ukb_cleaned.rds
                                                                    ├── 8-imputation_full_dataset.R  ──► ukb_final_imputed.rds
                                                                    ├── 9-table1.R  ──► table1_*.png
                                                                    └── 10-dataset_splitting.R
                                                                            ├── 11a  ──► ukb_selection_60_imputed.rds
                                                                            ├── 11b  ──► ukb_refit_20_imputed.rds
                                                                            ├── 11c  ──► ukb_test_20_imputed.rds
                                                                        
```

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

---
