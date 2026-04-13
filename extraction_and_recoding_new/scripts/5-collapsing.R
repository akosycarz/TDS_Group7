
rm(list = ls())

# load data
mydata <- readRDS("../outputs/ukb_recoded_by_script.rds")


#### 1. Collapse sys_bp
cols <- c("sys_bp_automated.0.0", "sys_bp_automated.0.1",
          "sys_bp_manual.0.0",    "sys_bp_manual.0.1")
mydata[cols] <- lapply(mydata[cols], function(x) as.numeric(as.character(x)))

# collapse to one variable: sys_bp
auto_cols   <- c("sys_bp_automated.0.0", "sys_bp_automated.0.1")
manual_cols <- c("sys_bp_manual.0.0",    "sys_bp_manual.0.1")
all_cols    <- c(auto_cols, manual_cols)

# ensure numeric
mydata[all_cols] <- lapply(mydata[all_cols], function(x) as.numeric(as.character(x)))

# row means
auto_mean   <- rowMeans(mydata[auto_cols],   na.rm = TRUE)
manual_mean <- rowMeans(mydata[manual_cols], na.rm = TRUE)

# rowMeans returns NaN if all values in the row are NA, so convert those to NA
auto_mean[is.nan(auto_mean)]     <- NA_real_
manual_mean[is.nan(manual_mean)] <- NA_real_

# prefer automated
mydata$sys_bp <- ifelse(is.na(auto_mean), manual_mean, auto_mean)

mydata[all_cols] <- NULL


#### 2. Collapse dia_bp
auto_cols   <- c("dia_bp_automated.0.0", "dia_bp_automated.0.1")
manual_cols <- c("dia_bp_manual.0.0",    "dia_bp_manual.0.1")
all_cols    <- c(auto_cols, manual_cols)

# ensure numeric
mydata[all_cols] <- lapply(mydata[all_cols], function(x) as.numeric(as.character(x)))

# row means
auto_mean   <- rowMeans(mydata[auto_cols],   na.rm = TRUE)
manual_mean <- rowMeans(mydata[manual_cols], na.rm = TRUE)
auto_mean[is.nan(auto_mean)]     <- NA_real_
manual_mean[is.nan(manual_mean)] <- NA_real_

# prefer automated
mydata$dia_bp <- ifelse(is.na(auto_mean), manual_mean, auto_mean)
mydata[all_cols] <- NULL



#### 3. Collapse fvc
cols <- c("fvc.0.0", "fvc.0.1", "fvc.0.2")
mydata[cols] <- lapply(mydata[cols], function(x) as.numeric(as.character(x)))
mydata[cols] <- lapply(mydata[cols], function(x) { x[x < 0] <- NA_real_; x })
mydata$fvc <- do.call(pmax, c(mydata[cols], na.rm = TRUE))
mydata$fvc[is.infinite(mydata$fvc)] <- NA_real_
mydata[cols] <- NULL



#### 5. Collapse fev1
cols <- c("fev1.0.0", "fev1.0.1", "fev1.0.2")
mydata[cols] <- lapply(mydata[cols], function(x) as.numeric(as.character(x)))
mydata[cols] <- lapply(mydata[cols], function(x) { x[x < 0] <- NA_real_; x })
mydata$fev1 <- do.call(pmax, c(mydata[cols], na.rm = TRUE))
mydata$fev1[is.infinite(mydata$fev1)] <- NA_real_
mydata[cols] <- NULL

#### 6. Collapse qualifications
q_cols <- paste0("qualifications.0.", 0:5)

rank_map <- c(
  "College or University degree" = 7,
  "NVQ or HND or HNC or equivalent" = 6,
  "A levels/AS levels or equivalent" = 5,
  "O levels/GCSEs or equivalent" = 4,
  "CSEs or equivalent" = 3,
  "Other professional qualifications (e.g., nursing, teaching)" = 2,
  "None of the above" = 1,
  "Prefer not to answer" = 0
)

mydata$qualifications <- apply(mydata[, q_cols, drop = FALSE], 1, function(x) {
  x <- trimws(as.character(x))
  x <- x[!is.na(x) & x != ""]
  if (length(x) == 0) return(NA_character_)
  
  r <- rank_map[x]
  r[is.na(r)] <- -Inf              # unknown strings treated as lowest
  x[which.max(r)]                  # highest-ranked value (ties -> first)
})
mydata[q_cols] <- NULL


#### 7. Collapse current_employ_status
emp_cols <- paste0("current_employ_status.0.", 0:6)

# priority order (top = highest)
rank_map_emp <- c(
  "Unable to work because of sickness or disability" = 7,
  "Retired" = 6,
  "In paid employment or self-employed" = 5,
  "Full or part-time student" = 4,
  "Unemployed" = 3,
  "Looking after home and/or family" = 2,
  "Doing unpaid or voluntary work" = 1,
  "Prefer not to answer" = -1,
  "None of the above" = 0
)

mydata$current_employ_status <- apply(mydata[, emp_cols, drop = FALSE], 1, function(x) {
  x <- trimws(as.character(x))
  x <- x[!is.na(x) & x != ""]
  if (length(x) == 0) return(NA_character_)
  
  r <- rank_map_emp[x]
  r[is.na(r)] <- -Inf          # unknown values treated as lowest
  x[which.max(r)]              # highest-ranked (ties -> first)
})

mydata[emp_cols] <- NULL

#### 7. Collapse dis_cvd_doc_yn
cvd_cols <- paste0("dis_cvd_doc_yn.0.", 0:3)

# priority order (top = highest)
rank_map_cvd <- c(
  "CVD Event" = 4,
  "High BP" = 3,
  "None of the above" = 2,
  "Prefer not to answer" = 1
)

mydata$dis_cvd_doc_yn <- apply(mydata[, cvd_cols, drop = FALSE], 1, function(x) {
  x <- trimws(as.character(x))
  x <- x[!is.na(x) & x != ""]
  if (length(x) == 0) return(NA_character_)
  
  r <- rank_map_cvd[x]
  r[is.na(r)] <- -Inf          # unknown values treated as lowest
  x[which.max(r)]              # highest-ranked (ties -> first)
})

mydata[cvd_cols] <- NULL



library(dplyr)
library(tibble)

mydata$id <- as.integer(rownames(mydata))

args <- commandArgs(trailingOnly = TRUE)
cvd_path <- args[1]

cvd <- readRDS(cvd_path)

cvd_clean <- cvd %>%
  mutate(
    eid  = as.character(eid),
    date = as.Date(date)
  ) %>%
  group_by(eid) %>%
  summarise(date = min(date, na.rm = TRUE), .groups = "drop")

# Ensure ID types match
mydata <- mydata %>%
  mutate(id = as.character(id))

# Merge (left join keeps all rows in mydata)
merged_data <- mydata %>%
  left_join(cvd_clean, by = c("id" = "eid")) %>%
  mutate(date = if_else(is.na(date), "No", as.character(date))) %>%
  rename(outcome = date) %>%
  select(-any_of(c("src_l10_first.0.0", "date_of_death.0.0.1"))) %>%
  column_to_rownames("id")   # <-- puts id back on the LHS

saveRDS(merged_data, file = "../outputs/ukb_collapsed.rds")