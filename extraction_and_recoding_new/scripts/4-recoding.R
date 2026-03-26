library(dplyr)

df    <- readRDS("outputs/ukb_recoded_changed.rds")
annot <- readRDS("outputs/annot.rds")

annot_small <- annot %>% select(Coding, CodingName)


# ── ethnic background | Code 1001 ─────────────────────────────────────────────
cols_1001_base <- annot_small %>%
  filter(Coding == 1001) %>%
  pull(CodingName) %>%
  unique()

cols_1001 <- unique(unlist(lapply(cols_1001_base, function(b) {
  grep(paste0("^", b, "\\."), names(df), value = TRUE)
})))

for (col in cols_1001) {
  x <- as.character(df[[col]])
  df[[col]] <- ifelse(x == "Do not know", "Do not know",
                      ifelse(x == "Prefer not to answer", "Prefer not to answer",
                             ifelse(x %in% c("White", "British", "Irish",
                                             "Any other white background"), "White",
                                    ifelse(x %in% c("Mixed", "White and Black Caribbean",
                                                    "White and Black African", "White and Asian",
                                                    "Any other mixed background"), "Mixed",
                                           ifelse(x %in% c("Asian or Asian British", "Indian", "Pakistani",
                                                           "Bangladeshi",
                                                           "Any other Asian background"), "South Asian",
                                                  ifelse(x %in% c("Black or Black British", "Caribbean", "African",
                                                                  "Any other Black background"), "Black",
                                                         ifelse(x %in% c("Other ethnic group", "Other"), "Other",
                                                                x)))))))
}


# ── src_l10_first | Code 2171 ─────────────────────────────────────────────────
cols_2171_base <- annot_small %>%
  filter(Coding == 2171) %>%
  pull(CodingName) %>%
  unique()

cols_2171 <- unique(unlist(lapply(cols_2171_base, function(b) {
  grep(paste0("^", b, "\\."), names(df), value = TRUE)
})))

for (col in cols_2171) {
  x <- as.character(df[[col]])
  df[[col]] <- ifelse(
    x %in% c("Death register only", "Death register and other source(s)"),
    "Death register and other source(s)",
    ifelse(
      x %in% c("Primary care only", "Primary care and other source(s)"),
      "Primary care and other source(s)",
      ifelse(
        x %in% c("Hospital admissions data only",
                 "Hospital admissions data and other source(s)"),
        "Hospital admissions data and other source(s)",
        ifelse(
          x %in% c("Self-report only", "Self-report and other source(s)"),
          "Self-report and other source(s)",
          x
        )
      )
    )
  )
}


# ── job_walk_stand_yn | Code 100301 ───────────────────────────────────────────
cols_100301_base <- annot_small %>%
  filter(Coding == 100301) %>%
  pull(CodingName) %>%
  unique()

cols_100301 <- unique(unlist(lapply(cols_100301_base, function(b) {
  grep(paste0("^", b, "\\."), names(df), value = TRUE)
})))

for (col in cols_100301) {
  x <- as.character(df[[col]])
  df[[col]] <- ifelse(x == "Do not know", "Do not know",
                      ifelse(x == "Prefer not to answer", "Prefer not to answer",
                             ifelse(x == "Never/rarely", "Never/rarely",
                                    ifelse(x == "Sometimes", "Sometimes",
                                           ifelse(x %in% c("Usually", "Always"), "Usually/Always",
                                                  x)))))
}


# ── risky_driving_speeding | Code 100334 ──────────────────────────────────────
cols_100334_base <- annot_small %>%
  filter(Coding == 100334) %>%
  pull(CodingName) %>%
  unique()

cols_100334 <- unique(unlist(lapply(cols_100334_base, function(b) {
  grep(paste0("^", b, "\\."), names(df), value = TRUE)
})))

for (col in cols_100334) {
  x <- as.character(df[[col]])
  df[[col]] <- ifelse(x == "Never/rarely", "Low",
                      ifelse(x == "Sometimes", "Moderate",
                             ifelse(x %in% c("Often", "Most of the time"), "High",
                                    ifelse(x == "Do not drive on the motorway", "Never",
                                           x))))
}


# ── smoking_current_status | Code 100347 ──────────────────────────────────────
cols_100347_base <- annot_small %>%
  filter(Coding == 100347) %>%
  pull(CodingName) %>%
  unique()

cols_100347 <- unique(unlist(lapply(cols_100347_base, function(b) {
  grep(paste0("^", b, "\\."), names(df), value = TRUE)
})))

for (col in cols_100347) {
  x <- as.character(df[[col]])
  df[[col]] <- ifelse(
    x %in% c("Yes, on most or all days", "Only occasionally"), "Yes",
    x
  )
}


# ── smoking_past_status | Code 100348 ─────────────────────────────────────────
cols_100348_base <- annot_small %>%
  filter(Coding == 100348) %>%
  pull(CodingName) %>%
  unique()

cols_100348 <- unique(unlist(lapply(cols_100348_base, function(b) {
  grep(paste0("^", b, "\\."), names(df), value = TRUE)
})))

for (col in cols_100348) {
  x <- as.character(df[[col]])
  df[[col]] <- ifelse(
    x %in% c("Smoked on most or all days", "Smoked occasionally"), "Current",
    ifelse(x == "Just tried once or twice", "Former",
           ifelse(x == "I have never smoked",      "Never",
                  x))
  )
}


# ── alcohol_frequency | Code 100402 ───────────────────────────────────────────
cols_100402_base <- annot_small %>%
  filter(Coding == 100402) %>%
  pull(CodingName) %>%
  unique()

cols_100402 <- unique(unlist(lapply(cols_100402_base, function(b) {
  grep(paste0("^", b, "\\."), names(df), value = TRUE)
})))

for (col in cols_100402) {
  x <- as.character(df[[col]])
  df[[col]] <- ifelse(
    x %in% c("Daily or almost daily", "Three or four times a week"), "Heavy",
    ifelse(x == "Once or twice a week", "Moderate",
           ifelse(x %in% c("Special occasions only", "One to three times a month"), "Light",
                  x))
  )
}


# ── social_support_confide | Code 100501 ──────────────────────────────────────
cols_100501_base <- annot_small %>%
  filter(Coding == 100501) %>%
  pull(CodingName) %>%
  unique()

cols_100501 <- unique(unlist(lapply(cols_100501_base, function(b) {
  grep(paste0("^", b, "\\."), names(df), value = TRUE)
})))

for (col in cols_100501) {
  x <- as.character(df[[col]])
  df[[col]] <- ifelse(x == "Never or almost never", "No",
                      ifelse(x %in% c("Once every few months", "About once a month",
                                      "About once a week", "2-4 times a week",
                                      "Almost daily"), "Yes",
                             x))
}


# ── hx_major_surgery_yn | dx_cancer_doc_yn | Code 100603 ─────────────────────
cols_100603_base <- annot_small %>%
  filter(Coding == 100603) %>%
  pull(CodingName) %>%
  unique()

cols_100603 <- unique(unlist(lapply(cols_100603_base, function(b) {
  grep(paste0("^", b, "\\."), names(df), value = TRUE)
})))

for (col in cols_100603) {
  x <- as.character(df[[col]])
  df[[col]] <- ifelse(
    x == "Yes - you will be asked about this later by an interviewer", "Yes",
    x
  )
}


# ── dx_cvd_doc_yn | Code 100605 ───────────────────────────────────────────────
cols_100605_base <- annot_small %>%
  filter(Coding == 100605) %>%
  pull(CodingName) %>%
  unique()

cols_100605 <- unique(unlist(lapply(cols_100605_base, function(b) {
  grep(paste0("^", b, "\\."), names(df), value = TRUE)
})))

for (col in cols_100605) {
  x <- as.character(df[[col]])
  df[[col]] <- ifelse(
    x %in% c("Heart attack", "Angina", "Stroke"), "CVD Event",
    ifelse(x == "High blood pressure", "High BP",
           x)
  )
}


# ── med_chol_bp_dm_yn | Code 100625 ───────────────────────────────────────────
cols_100625_base <- annot_small %>%
  filter(Coding == 100625) %>%
  pull(CodingName) %>%
  unique()

cols_100625 <- unique(unlist(lapply(cols_100625_base, function(b) {
  grep(paste0("^", b, "\\."), names(df), value = TRUE)
})))

for (col in cols_100625) {
  x <- as.character(df[[col]])
  df[[col]] <- ifelse(x == "Cholesterol lowering medication", "Lipid Lowering Meds",
                      ifelse(x == "Insulin", "Other",
                             x))
}


# ── med_chol_bp_dm_or_horm_yn | Code 100626 ───────────────────────────────────
cols_100626_base <- annot_small %>%
  filter(Coding == 100626) %>%
  pull(CodingName) %>%
  unique()

cols_100626 <- unique(unlist(lapply(cols_100626_base, function(b) {
  grep(paste0("^", b, "\\."), names(df), value = TRUE)
})))

for (col in cols_100626) {
  x <- as.character(df[[col]])
  df[[col]] <- ifelse(x == "Cholesterol lowering medication", "Lipid Lowering Meds",
                      ifelse(x %in% c("Hormone replacement therapy",
                                      "Oral contraceptive pill or minipill"), "Other",
                             x))
}


# ── med_symptom_relief_yn | Code 100628 ───────────────────────────────────────
cols_100628_base <- annot_small %>%
  filter(Coding == 100628) %>%
  pull(CodingName) %>%
  unique()

cols_100628 <- unique(unlist(lapply(cols_100628_base, function(b) {
  grep(paste0("^", b, "\\."), names(df), value = TRUE)
})))

for (col in cols_100628) {
  x <- as.character(df[[col]])
  df[[col]] <- ifelse(
    x %in% c("Aspirin", "Ibuprofen (e.g. Nurofen)", "Paracetamol"), "Pain Meds",
    ifelse(
      x %in% c("Ranitidine (e.g. Zantac)", "Omeprazole (e.g. Zanprol)"), "Acid-Lowering Meds",
      ifelse(x == "Laxatives (e.g. Dulcolax, Senokot)", "Laxatives",
             x)
    )
  )
}


# ── med_pain_cons_hrt | Code 100688 ───────────────────────────────────────────
cols_100688_base <- annot_small %>%
  filter(Coding == 100688) %>%
  pull(CodingName) %>%
  unique()

cols_100688 <- unique(unlist(lapply(cols_100688_base, function(b) {
  grep(paste0("^", b, "\\."), names(df), value = TRUE)
})))

for (col in cols_100688) {
  x <- as.character(df[[col]])
  df[[col]] <- ifelse(
    x %in% c("Aspirin", "Ibuprofen (e.g. Nurofen)", "Paracetamol", "Codeine"), "Pain Meds",
    ifelse(x == "Ranitidine (e.g. Zantac)", "Acid-Lowering Meds",
           x)
  )
}


# ── BPD_MD_status | Code 100695 ───────────────────────────────────────────────
cols_100695_base <- annot_small %>%
  filter(Coding == 100695) %>%
  pull(CodingName) %>%
  unique()

cols_100695 <- unique(unlist(lapply(cols_100695_base, function(b) {
  grep(paste0("^", b, "\\."), names(df), value = TRUE)
})))

for (col in cols_100695) {
  x <- as.character(df[[col]])
  df[[col]] <- ifelse(x == "No Bipolar or Depression", "No",
                      ifelse(x %in% c("Bipolar I Disorder",
                                      "Bipolar II Disorder",
                                      "Probable Recurrent major depression (severe)",
                                      "Probable Recurrent major depression (moderate)",
                                      "Single Probable major depression episode"), "Yes",
                             x))
}


saveRDS(df, file = "outputs/ukb_recoded_by_script.rds")