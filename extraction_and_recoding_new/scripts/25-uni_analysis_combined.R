suppressPackageStartupMessages({
  library(dplyr)
})

# ============================================================
# UNIVARIATE ADJUSTED ANALYSIS
# Outcome: df$outcome is assumed already appropriately coded upstream
# One adjusted logistic regression per predictor
# Continuous + categorical results combined into one summary table
# Confounders are used only for adjustment and are NOT tested as predictors
# Existing reference groups are preserved for factor variables
# ============================================================

df <- readRDS("../outputs/ukb_final_imputed.rds")

# -----------------------------
# 1) Create binary outcome
# -----------------------------
df$y <- ifelse(trimws(toupper(df$outcome)) == "NO", 0L, 1L)

# -----------------------------
# 2) Define confounders
# -----------------------------
confounder_vars <- c("age_at_recruitment", "sex", "eth_bg")
confounder_vars <- intersect(confounder_vars, names(df))

# -----------------------------
# 3) Exclude variables not to test
# -----------------------------
exclude_vars <- c(
  "eid",
  "outcome",
  "y",
  "dob",
  "attending_assessment_date",
  "date_of_death",
  "dis_date_of_cancer"
)
exclude_vars <- intersect(exclude_vars, names(df))

# Do not test confounders as predictors
predictors <- setdiff(names(df), c(exclude_vars, confounder_vars))

# -----------------------------
# 4) Helper functions
# -----------------------------
is_categorical <- function(x) {
  (is.factor(x) || is.character(x)) &&
    !(inherits(x, "Date") || inherits(x, "POSIXt"))
}

clean_cat <- function(v) {
  x <- trimws(as.character(v))
  x[x == ""] <- NA
  x[x %in% c("Do not know", "Prefer not to answer")] <- NA
  
  # Preserve existing factor levels/reference if already factor
  if (is.factor(v)) {
    factor(x, levels = levels(v))
  } else {
    factor(x)
  }
}

make_empty_result <- function(varname,
                              variable_type = NA_character_,
                              level = NA_character_,
                              level_order = NA_integer_,
                              ref_level = NA_character_,
                              N = NA_real_) {
  data.frame(
    variable = varname,
    variable_type = variable_type,
    level = level,
    level_order = level_order,
    ref_level = ref_level,
    OR = NA_real_,
    LCL = NA_real_,
    UCL = NA_real_,
    p = NA_real_,
    N = N,
    stringsAsFactors = FALSE
  )
}

# Clean categorical variables only
cat_vars <- predictors[sapply(df[predictors], is_categorical)]
if (length(cat_vars) > 0) {
  df <- df %>%
    mutate(across(all_of(cat_vars), clean_cat))
}

# -----------------------------
# 5) Desired output order only
#    This does NOT change model reference levels
# -----------------------------
level_orders <- list(
  hh_income_pre_tax = c(
    "Less than 18,000", "18,000 to 30,999", "31,000 to 51,999",
    "52,000 to 100,000", "Greater than 100,000"
  ),
  qualifications = c("School", "University", "Other", "None"),
  current_employ_status = c("Employed", "Retired", "Other not in paid work", "Unable to work"),
  mh_loneliness = c("No", "Yes", "Other"),
  mh_social_support_confide = c("No", "Yes", "Other"),
  bmi = c("Healthy weight", "Underweight", "Overweight", "Obese"),
  body_fat_pct = c("Normal weight", "Underweight", "Overweight", "Obesity"),
  sleep_insomnia = c("Never/rarely", "Sometimes", "Usually", "Other"),
  risky_driving_speeding = c("Never", "Low", "Moderate", "High"),
  diet_tea = c("None", "Low", "Medium", "High"),
  diet_coffee = c("None", "Moderate", "Heavy"),
  MET_summed = c("Low", "Moderate", "High"),
  alcohol_status_with_freq = c(
    "Never", "Former", "Current (Light)", "Current (Moderate)",
    "Current (Heavy)", "Current (Other)"
  ),
  sleep_duration = c("Normal", "Not normal"),
  diet_water = c("Low", "Normal", "Not normal"),
  sedentary_total_hours = c("Low", "Moderate", "High"),
  smoking_status = c("Never", "Former", "Current")
)

get_level_order <- function(varname, level_value, observed_levels) {
  if (is.na(level_value)) return(NA_integer_)
  
  if (varname %in% names(level_orders)) {
    wanted <- level_orders[[varname]]
    final_order <- c(
      wanted[wanted %in% observed_levels],
      setdiff(observed_levels, wanted)
    )
    return(match(level_value, final_order))
  }
  
  match(level_value, observed_levels)
}

# -----------------------------
# 6) Unified model function
# -----------------------------
uni_glm_adjusted <- function(varname, data, confounder_vars, min_n = 50, min_level_n = 10) {
  
  x0 <- data[[varname]]
  var_type <- if (is.numeric(x0)) {
    "continuous"
  } else if (is_categorical(x0)) {
    "categorical"
  } else {
    "other"
  }
  
  if (var_type == "other") {
    return(make_empty_result(varname = varname))
  }
  
  needed_vars <- unique(c("y", varname, confounder_vars))
  needed_vars <- intersect(needed_vars, names(data))
  d <- data[, needed_vars, drop = FALSE]
  
  # -------------------------
  # Continuous predictor
  # -------------------------
  if (var_type == "continuous") {
    d <- d[complete.cases(d), , drop = FALSE]
    N <- nrow(d)
    
    if (N < min_n) {
      return(make_empty_result(
        varname = varname,
        variable_type = "continuous",
        level = "Per 1 SD increase",
        level_order = 1L,
        N = N
      ))
    }
    
    d$x <- as.numeric(scale(d[[varname]]))
    
    if (length(unique(d$x)) < 2) {
      return(make_empty_result(
        varname = varname,
        variable_type = "continuous",
        level = "Per 1 SD increase",
        level_order = 1L,
        N = N
      ))
    }
    
    adjust_vars <- setdiff(confounder_vars, varname)
    rhs <- c("x", adjust_vars)
    form <- as.formula(paste("y ~", paste(rhs, collapse = " + ")))
    
    fit <- tryCatch(
      suppressWarnings(glm(form, data = d, family = binomial())),
      error = function(e) NULL
    )
    
    if (is.null(fit) || !isTRUE(fit$converged)) {
      return(make_empty_result(
        varname = varname,
        variable_type = "continuous",
        level = "Per 1 SD increase",
        level_order = 1L,
        N = N
      ))
    }
    
    ct <- summary(fit)$coefficients
    
    if (!("x" %in% rownames(ct))) {
      return(make_empty_result(
        varname = varname,
        variable_type = "continuous",
        level = "Per 1 SD increase",
        level_order = 1L,
        N = N
      ))
    }
    
    beta <- ct["x", "Estimate"]
    se   <- ct["x", "Std. Error"]
    pval <- ct["x", "Pr(>|z|)"]
    
    if (!all(is.finite(c(beta, se)))) {
      return(make_empty_result(
        varname = varname,
        variable_type = "continuous",
        level = "Per 1 SD increase",
        level_order = 1L,
        N = N
      ))
    }
    
    return(data.frame(
      variable = varname,
      variable_type = "continuous",
      level = "Per 1 SD increase",
      level_order = 1L,
      ref_level = NA_character_,
      OR = exp(beta),
      LCL = exp(beta - 1.96 * se),
      UCL = exp(beta + 1.96 * se),
      p = pval,
      N = N,
      stringsAsFactors = FALSE
    ))
  }
  
  # -------------------------
  # Categorical predictor
  # -------------------------
  if (var_type == "categorical") {
    d <- d[complete.cases(d), , drop = FALSE]
    N <- nrow(d)
    
    if (N < min_n) {
      return(make_empty_result(
        varname = varname,
        variable_type = "categorical",
        N = N
      ))
    }
    
    # Preserve existing factor order/reference if already factor
    if (is.factor(d[[varname]])) {
      d$x <- droplevels(d[[varname]])
    } else {
      d$x <- factor(d[[varname]])
    }
    
    if (nlevels(d$x) < 2) {
      return(make_empty_result(
        varname = varname,
        variable_type = "categorical",
        ref_level = levels(d$x)[1],
        N = N
      ))
    }
    
    ref <- levels(d$x)[1]

    # -------------------------
    # Categorical predictor
    # -------------------------
    if (var_type == "categorical") {
      d <- d[complete.cases(d), , drop = FALSE]
      N <- nrow(d)
      
      if (N < min_n) {
        return(make_empty_result(
          varname = varname,
          variable_type = "categorical",
          N = N
        ))
      }
      
      # Preserve existing factor order/reference if already factor
      if (is.factor(d[[varname]])) {
        d$x <- droplevels(d[[varname]])
      } else {
        d$x <- factor(d[[varname]])
      }
      
      if (nlevels(d$x) < 2) {
        return(make_empty_result(
          varname = varname,
          variable_type = "categorical",
          ref_level = levels(d$x)[1],
          N = N
        ))
      }
      
      ref <- levels(d$x)[1]
      observed_levels <- levels(d$x)
      
      # Level counts
      lvl_counts <- table(d$x)
      
      # Outcome table by level
      tab_xy <- table(d$x, d$y)
      
      # Mark unstable levels:
      # - fewer than min_level_n observations
      # - any zero cell in the 2xK table
      unstable_levels <- names(lvl_counts)[
        lvl_counts < min_level_n |
          apply(tab_xy, 1, function(z) any(z == 0))
      ]
      
      adjust_vars <- confounder_vars
      rhs <- c("x", adjust_vars)
      form <- as.formula(paste("y ~", paste(rhs, collapse = " + ")))
      
      fit <- tryCatch(
        suppressWarnings(glm(form, data = d, family = binomial())),
        error = function(e) NULL
      )
      
      if (is.null(fit) || !isTRUE(fit$converged)) {
        return(make_empty_result(
          varname = varname,
          variable_type = "categorical",
          ref_level = ref,
          N = N
        ))
      }
      
      ct <- summary(fit)$coefficients
      terms <- rownames(ct)
      terms <- terms[grepl("^x", terms)]
      
      if (length(terms) == 0) {
        return(make_empty_result(
          varname = varname,
          variable_type = "categorical",
          ref_level = ref,
          N = N
        ))
      }
      
      out <- do.call(rbind, lapply(terms, function(tn) {
        beta <- ct[tn, "Estimate"]
        se   <- ct[tn, "Std. Error"]
        pval <- ct[tn, "Pr(>|z|)"]
        lev_chr <- sub("^x", "", tn)
        
        is_unstable <- lev_chr %in% unstable_levels
        
        if (is_unstable || !all(is.finite(c(beta, se)))) {
          return(data.frame(
            variable = varname,
            variable_type = "categorical",
            level = lev_chr,
            level_order = get_level_order(varname, lev_chr, observed_levels),
            ref_level = ref,
            OR = NA_real_,
            LCL = NA_real_,
            UCL = NA_real_,
            p = NA_real_,
            N = N,
            stringsAsFactors = FALSE
          ))
        }
        
        data.frame(
          variable = varname,
          variable_type = "categorical",
          level = lev_chr,
          level_order = get_level_order(varname, lev_chr, observed_levels),
          ref_level = ref,
          OR = exp(beta),
          LCL = exp(beta - 1.96 * se),
          UCL = exp(beta + 1.96 * se),
          p = pval,
          N = N,
          stringsAsFactors = FALSE
        )
      }))
      
      return(out)
    }
    
    # Check for empty outcome cells within levels
    tab_xy <- table(d$x, d$y)
    if (any(tab_xy == 0)) {
      return(make_empty_result(
        varname = varname,
        variable_type = "categorical",
        ref_level = ref,
        N = N
      ))
    }
    
    adjust_vars <- confounder_vars
    rhs <- c("x", adjust_vars)
    form <- as.formula(paste("y ~", paste(rhs, collapse = " + ")))
    
    fit <- tryCatch(
      suppressWarnings(glm(form, data = d, family = binomial())),
      error = function(e) NULL
    )
    
    if (is.null(fit) || !isTRUE(fit$converged)) {
      return(make_empty_result(
        varname = varname,
        variable_type = "categorical",
        ref_level = ref,
        N = N
      ))
    }
    
    ct <- summary(fit)$coefficients
    terms <- rownames(ct)
    terms <- terms[grepl("^x", terms)]
    
    if (length(terms) == 0) {
      return(make_empty_result(
        varname = varname,
        variable_type = "categorical",
        ref_level = ref,
        N = N
      ))
    }
    
    observed_levels <- levels(d$x)
    
    out <- do.call(rbind, lapply(terms, function(tn) {
      beta <- ct[tn, "Estimate"]
      se   <- ct[tn, "Std. Error"]
      pval <- ct[tn, "Pr(>|z|)"]
      lev_chr <- sub("^x", "", tn)
      
      if (!all(is.finite(c(beta, se)))) {
        return(data.frame(
          variable = varname,
          variable_type = "categorical",
          level = lev_chr,
          level_order = get_level_order(varname, lev_chr, observed_levels),
          ref_level = ref,
          OR = NA_real_,
          LCL = NA_real_,
          UCL = NA_real_,
          p = NA_real_,
          N = N,
          stringsAsFactors = FALSE
        ))
      }
      
      data.frame(
        variable = varname,
        variable_type = "categorical",
        level = lev_chr,
        level_order = get_level_order(varname, lev_chr, observed_levels),
        ref_level = ref,
        OR = exp(beta),
        LCL = exp(beta - 1.96 * se),
        UCL = exp(beta + 1.96 * se),
        p = pval,
        N = N,
        stringsAsFactors = FALSE
      )
    }))
    
    return(out)
  }
}

# -----------------------------
# 7) Run models for all predictors
# -----------------------------
res_list <- lapply(
  predictors,
  uni_glm_adjusted,
  data = df,
  confounder_vars = confounder_vars,
  min_n = 50,
  min_level_n = 10
)

results_tbl <- bind_rows(res_list) %>%
  mutate(
    N_total = nrow(df),
    N_missing = N_total - N,
    pct_missing = 100 * N_missing / N_total,
    FDR = p.adjust(p, method = "BH")
  )

# -----------------------------
# 8) Order results
# -----------------------------
results_tbl <- results_tbl %>%
  arrange(variable_type, variable, level_order)

print(head(results_tbl, 30))

# -----------------------------
# 9) Export full results
# -----------------------------
output_dir <- "../outputs/summary"
dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)

write.csv(
  results_tbl,
  file.path(output_dir, "uni_analysis_combined.csv"),
  row.names = FALSE
)

# -----------------------------
# 10) Publication-ready table
# -----------------------------
publication_table <- results_tbl %>%
  arrange(variable_type, variable, level_order) %>%
  mutate(
    OR  = round(OR, 3),
    LCL = round(LCL, 3),
    UCL = round(UCL, 3),
    p_fmt   = ifelse(is.na(p), NA, format(signif(p, 3), scientific = FALSE)),
    FDR_fmt = ifelse(is.na(FDR), NA, format(signif(FDR, 3), scientific = FALSE)),
    `OR (95% CI)` = ifelse(
      is.na(OR),
      NA,
      paste0(OR, " (", LCL, "-", UCL, ")")
    ),
    `% Missing` = round(pct_missing, 1)
  ) %>%
  select(
    variable_type, variable, level, ref_level, `OR (95% CI)`,
    p_fmt, FDR_fmt, N, `% Missing`
  ) %>%
  rename(
    `Variable Type` = variable_type,
    Variable = variable,
    Level = level,
    `Reference Level` = ref_level,
    `P-value` = p_fmt,
    FDR = FDR_fmt
  )

write.csv(
  publication_table,
  file.path(output_dir, "uni_analysis_combined_table.csv"),
  row.names = FALSE
)