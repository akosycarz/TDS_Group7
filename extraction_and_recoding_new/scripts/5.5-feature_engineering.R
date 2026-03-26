suppressPackageStartupMessages({
  library(dplyr)
  library(stringr)
  library(readr)
})

rm(list = ls())

# ------------------------------------------------------------
# 0) Load input data
# ------------------------------------------------------------
df <- readRDS("outputs/ukb_collapsed.rds")

# ============================================================
# 1) TOTAL SEDENTARY HOURS
# ============================================================

sed_cols <- c("sedentary_tv.0.0", "sedentary_computer.0.0", "sedentary_driving.0.0")
sed_cols <- intersect(sed_cols, names(df))

if (length(sed_cols) > 0) {
  df$sedentary_total_hours <- apply(df[, sed_cols, drop = FALSE], 1, function(x) {
    
    x_chr <- trimws(as.character(x))
    
    # missing codes
    x_chr[x_chr %in% c("-999909999", "-9999099999")] <- NA_character_
    
    # If all missing -> NA
    if (all(is.na(x_chr) | x_chr == "")) return(NA_character_)
    
    # Keep explicit missingness ONLY if all non-missing are the same
    nonmiss <- x_chr[!is.na(x_chr) & x_chr != ""]
    if (length(nonmiss) > 0 && all(nonmiss == "Do not know")) return("Do not know")
    if (length(nonmiss) > 0 && all(nonmiss == "Prefer not to answer")) return("Prefer not to answer")
    
    # Convert "<1 hour/day" to 0.5 hours
    x_chr[x_chr == "Less than an hour a day"] <- "0.5"
    
    # Treat "Do not know" / "Prefer not" as missing for summation
    x_chr[x_chr %in% c("Do not know", "Prefer not to answer")] <- NA_character_
    
    # Convert to numeric
    x_num <- suppressWarnings(as.numeric(x_chr))
    x_num[!is.na(x_num) & x_num < 0] <- NA_real_
    
    if (all(is.na(x_num))) return(NA_character_)
    
    as.character(sum(x_num, na.rm = TRUE))
  })
  
  df$sedentary_total_hours <- as.character(df$sedentary_total_hours)
} else {
  df$sedentary_total_hours <- NA_character_
}

# ============================================================
# 2) DROP ORIGINAL COLUMNS (redundant after engineered vars)
# ============================================================

df <- df %>%
  select(-any_of(c(
    "MET_walking.0.0",
    "MET_moderate.0.0",
    "MET_vigorous.0.0",
    "sedentary_tv.0.0",
    "sedentary_computer.0.0",
    "sedentary_driving.0.0"
  )))

# ============================================================
# 3) SMOKING: clean status + pack years
# ============================================================

if (all(c("smoking_status.0.0", "smoking_pack_years.0.0") %in% names(df))) {
  
  df <- df %>%
    select(-any_of(c("smoking_current_status.0.0", "smoking_past_status.0.0","smoking_cigs_per_day.0.0"))) %>%
    mutate(
      smoking_status.0.0 = case_when(
        trimws(as.character(smoking_status.0.0)) %in% c("Prefer not to answer", "I don't know", "Don't know", "Do not know") ~ NA_character_,
        trimws(as.character(smoking_status.0.0)) == "Previous" ~ "Former",
        TRUE ~ trimws(as.character(smoking_status.0.0))
      ),
      smoking_pack_years.0.0 = suppressWarnings(as.numeric(as.character(smoking_pack_years.0.0))),
      smoking_pack_years.0.0 = if_else(is.na(smoking_status.0.0), NA_real_, smoking_pack_years.0.0),
      smoking_pack_years.0.0 = if_else(smoking_status.0.0 == "Never", 0, smoking_pack_years.0.0),
      smoking_status.0.0 = factor(smoking_status.0.0)
    )
  
} else {
  message("Smoking columns not found; skipping smoking feature engineering.")
}

# ============================================================
# 4) DIET SCORE CONSTRUCTION (NO fluids domain)
# ============================================================

ukb_num_100373 <- function(x) {
  x_chr <- str_trim(as.character(x))
  x_chr[x_chr %in% c("Do not know", "Prefer not to answer", "Other (collapsed)", "Other")] <- NA_character_
  out <- suppressWarnings(parse_number(x_chr))
  out[out < 0] <- NA_real_
  out
}

freq6_to_score_processed_meat <- function(x) {
  xl <- str_trim(as.character(x))
  case_when(
    is.na(xl) ~ NA_real_,
    xl %in% c("Do not know", "Prefer not to answer") ~ NA_real_,
    xl == "Never" ~ 3,
    xl %in% c("Less than once a week", "Once a week") ~ 2,
    xl == "2-4 times a week" ~ 1,
    xl %in% c("5-6 times a week", "Once or more daily") ~ 0,
    TRUE ~ NA_real_
  )
}

freq6_to_score_cheese <- function(x) {
  xl <- str_trim(as.character(x))
  case_when(
    is.na(xl) ~ NA_real_,
    xl %in% c("Do not know", "Prefer not to answer") ~ NA_real_,
    xl %in% c("Never", "Less than once a week") ~ 2,
    xl %in% c("Once a week", "2-4 times a week") ~ 1,
    xl %in% c("5-6 times a week", "Once or more daily") ~ 0,
    TRUE ~ NA_real_
  )
}

freq6_to_portions <- function(x) {
  xl <- str_trim(as.character(x))
  case_when(
    is.na(xl) ~ NA_real_,
    xl %in% c("Do not know", "Prefer not to answer") ~ NA_real_,
    xl == "Never" ~ 0,
    xl == "Less than once a week" ~ 0.5,
    xl == "Once a week" ~ 1,
    xl == "2-4 times a week" ~ 3,
    xl == "5-6 times a week" ~ 5.5,
    xl == "Once or more daily" ~ 7,
    TRUE ~ NA_real_
  )
}

freq6_to_oily_bin <- function(x) {
  xl <- str_trim(as.character(x))
  case_when(
    is.na(xl) ~ NA_real_,
    xl %in% c("Do not know", "Prefer not to answer") ~ NA_real_,
    xl == "Once a week" ~ 1,
    xl %in% c("Never", "Less than once a week", "2-4 times a week",
              "5-6 times a week", "Once or more daily") ~ 0,
    TRUE ~ NA_real_
  )
}

freq6_to_non_oily_score <- function(x) {
  xl <- str_trim(as.character(x))
  case_when(
    is.na(xl) ~ NA_real_,
    xl %in% c("Do not know", "Prefer not to answer") ~ NA_real_,
    xl == "Never" ~ 0,
    xl == "Less than once a week" ~ 1,
    xl == "Once a week" ~ 2,
    xl == "2-4 times a week" ~ 3,
    xl == "5-6 times a week" ~ 4,
    xl == "Once or more daily" ~ 5,
    TRUE ~ NA_real_
  )
}

milk_type_to_score <- function(x) {
  xl <- str_trim(as.character(x))
  case_when(
    is.na(xl) ~ NA_real_,
    xl %in% c("Do not know", "Prefer not to answer") ~ NA_real_,
    xl == "Skimmed" ~ 3,
    xl %in% c("Semi-skimmed", "Soya") ~ 2,
    xl %in% c("Full cream", "Other type of milk") ~ 1,
    xl == "Never/rarely have milk" ~ 0,
    TRUE ~ NA_real_
  )
}

salt_to_score <- function(x) {
  xl <- str_trim(as.character(x))
  case_when(
    is.na(xl) ~ NA_real_,
    xl %in% c("Do not know", "Prefer not to answer") ~ NA_real_,
    xl == "Never/rarely" ~ 5,
    xl == "Sometimes" ~ 3,
    xl == "Usually" ~ 1,
    xl == "Always" ~ 0,
    TRUE ~ NA_real_
  )
}

bread_type_to_score <- function(x) {
  xl <- str_trim(as.character(x))
  case_when(
    is.na(xl) ~ NA_real_,
    xl %in% c("Do not know", "Prefer not to answer") ~ NA_real_,
    xl == "Wholemeal or wholegrain" ~ 2,
    xl == "Brown" ~ 1,
    xl == "White" ~ 0,
    xl == "Other type of bread" ~ 1,
    TRUE ~ NA_real_
  )
}

cereal_type_to_score <- function(x) {
  xl <- str_trim(as.character(x))
  case_when(
    is.na(xl) ~ NA_real_,
    xl %in% c("Do not know", "Prefer not to answer") ~ NA_real_,
    xl %in% c("Bran cereal (e.g. All Bran, Branflakes)",
              "Muesli",
              "Oat cereal (e.g. Ready Brek, porridge)") ~ 2,
    xl == "Biscuit cereal (e.g. Weetabix)" ~ 0,
    xl == "Other (e.g. Cornflakes, Frosties)" ~ 1,
    TRUE ~ NA_real_
  )
}

domain_complete_else_na <- function(score, ...) {
  inputs <- list(...)
  any_na <- Reduce(`|`, lapply(inputs, is.na))
  if_else(any_na, NA_real_, score)
}

score_input_vars <- c(
  "diet_cooked_vegetables.0.0",
  "diet_raw_vegetables.0.0",
  "diet_fruit_fresh.0.0",
  "diet_fruit_dried.0.0",
  "diet_oily_fish.0.0",
  "diet_non_oily_fish.0.0",
  "diet_processed_meat.0.0",
  "diet_beef.0.0",
  "diet_lamb.0.0",
  "diet_pork.0.0",
  "diet_salt.0.0",
  "diet_cheese.0.0",
  "diet_milk_type.0.0",
  "diet_bread_type.0.0",
  "diet_cereal_type.0.0",
  "diet_bread_intake.0.0",
  "diet_cereal_intake.0.0"
)

missing_diet_vars <- setdiff(score_input_vars, names(df))

if (length(missing_diet_vars) == 0) {
  
  diet_score_info <- df %>%
    select(all_of(score_input_vars)) %>%
    mutate(
      score_vegfruit = {
        cooked <- ukb_num_100373(`diet_cooked_vegetables.0.0`) / 3
        raw    <- ukb_num_100373(`diet_raw_vegetables.0.0`) / 3
        fresh  <- ukb_num_100373(`diet_fruit_fresh.0.0`)
        dried  <- pmin(ukb_num_100373(`diet_fruit_dried.0.0`), 1)
        domain_complete_else_na(pmin(cooked + raw + fresh + dried, 5), cooked, raw, fresh, dried)
      },
      score_fish = {
        oily <- freq6_to_oily_bin(`diet_oily_fish.0.0`)
        non  <- freq6_to_non_oily_score(`diet_non_oily_fish.0.0`)
        domain_complete_else_na(pmin(oily + non, 5), oily, non)
      },
      score_meat = {
        processed <- freq6_to_score_processed_meat(`diet_processed_meat.0.0`)
        beef <- freq6_to_portions(`diet_beef.0.0`)
        lamb <- freq6_to_portions(`diet_lamb.0.0`)
        pork <- freq6_to_portions(`diet_pork.0.0`)
        total <- beef + lamb + pork
        other <- case_when(
          is.na(total) ~ NA_real_,
          total < 4 ~ 2,
          total < 7 ~ 1,
          total >= 7 ~ 0
        )
        domain_complete_else_na(pmin(processed + other, 5), processed, beef, lamb, pork, other)
      },
      score_salt = salt_to_score(`diet_salt.0.0`),
      score_dairy = {
        cheese <- freq6_to_score_cheese(`diet_cheese.0.0`)
        milk   <- milk_type_to_score(`diet_milk_type.0.0`)
        domain_complete_else_na(pmin(cheese + milk, 5), cheese, milk)
      },
      score_grains = {
        bread_t  <- bread_type_to_score(`diet_bread_type.0.0`)
        cereal_t <- cereal_type_to_score(`diet_cereal_type.0.0`)
        quality  <- round(((bread_t + cereal_t) / 2) * 1.5)
        
        bread_d  <- ukb_num_100373(`diet_bread_intake.0.0`) / 7
        cereal_d <- ukb_num_100373(`diet_cereal_intake.0.0`) / 7
        total_d  <- bread_d + cereal_d
        
        qty <- case_when(
          is.na(total_d) ~ NA_real_,
          total_d == 0 ~ 0,
          total_d <= 1 ~ 1,
          total_d > 1 ~ 2
        )
        
        domain_complete_else_na(pmin(quality + qty, 5), bread_t, cereal_t, bread_d, cereal_d, qty)
      }
    ) %>%
    mutate(
      n_missing = rowSums(is.na(across(starts_with("score_")))),
      diet_score = if_else(
        n_missing > 3,
        NA_real_,
        rowMeans(across(starts_with("score_")), na.rm = TRUE)
      ),
      diet_score = round(diet_score)
    ) %>%
    select(all_of(score_input_vars), starts_with("score_"), diet_score)
  
  df <- df %>%
    select(-any_of(score_input_vars)) %>%
    mutate(diet_score = diet_score_info$diet_score)
  
} else {
  message("Diet columns missing; skipping diet score construction.")
  message("Missing columns: ", paste(missing_diet_vars, collapse = ", "))
  df$diet_score <- NA_real_
}

# ============================================================
# 5) ALCOHOL: Combine status + frequency
# ============================================================

if (all(c("alcohol_drinker_status.0.0", "alcohol_frequency.0.0") %in% names(df))) {
  
  status <- as.character(df[["alcohol_drinker_status.0.0"]])
  freq   <- as.character(df[["alcohol_frequency.0.0"]])
  
  df$alcohol_status_with_freq <- ifelse(
    status == "Current",
    paste0("Current (", freq, ")"),
    status
  )
  
  # removing previous alcohol columns
  df[c("alcohol_drinker_status.0.0", "alcohol_frequency.0.0")] <- NULL
  
  # recode combined alcohol variable
  x <- as.character(df$alcohol_status_with_freq)
  
  df$alcohol_status_with_freq <- dplyr::case_when(
    x %in% c("Current (Heavy)", "Current (Moderate)", "Current (Light)") ~ x,
    x == "Current (Never)" ~ NA_character_,
    x == "Current (Prefer not to answer)" ~ "Current (Other)",
    x == "Never" ~ "Never",
    x == "Previous" ~ "Former",
    x == "Prefer not to answer" ~ NA_character_,
    TRUE ~ NA_character_
  )
  
} else {
  message("Alcohol columns not found; skipping alcohol feature engineering.")
  df$alcohol_status_with_freq <- NA_character_
}

# ------------------------------------------------------------
# Save output
# ------------------------------------------------------------
saveRDS(df, file = "outputs/ukb_collapsed2.rds")