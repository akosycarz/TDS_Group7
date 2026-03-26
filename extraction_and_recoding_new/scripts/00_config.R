# ============================================================
# 00_config.R
# Central configuration file for the pipeline
# ============================================================

cfg <- list(
  
  # -------------------------
  # 1) DATA SOURCE CONTROL
  # -------------------------
  use_synthetic = FALSE,   # TRUE = run on synthetic data
  
  # -------------------------
  # 2) PATHS
  # -------------------------
  paths = list(
    input_rds  = "../ukb_sample_15k.rds",
    output_dir = "../outputs"
  ),
  
  # -------------------------
  # 3) THRESHOLDS
  # -------------------------
  thresholds = list(
    miss_var_pct = 25,
    miss_row_pct = 25
  )
)

# Automatically create output directory if not exists
dir.create(cfg$paths$output_dir,
           recursive = TRUE,
           showWarnings = FALSE)

message("✅ Config loaded successfully")