# mediation_dag_figures.R
# DAG figures only. DAGs are generated separately in mediation_figures_heatmap.R

library(dplyr)
library(tibble)
library(igraph)

# ── Data ──────────────────────────────────────────────────────────────────────
base_dir <- "../outputs/summary"
df <- read.csv(file.path(base_dir, "model1_mediation_indirect_effects_FINAL_6.csv"))

plot_labels  <- read.csv(file.path(base_dir, "plot_labels_domain.csv"), stringsAsFactors = FALSE)
label_lookup <- setNames(plot_labels$plot_label, plot_labels$variable)

domain_map <- plot_labels %>%
  select(variable, domain) %>%
  filter(!is.na(domain))

# ── Label helpers ─────────────────────────────────────────────────────────────
known_vars        <- domain_map$variable
known_vars_sorted <- known_vars[order(nchar(known_vars), decreasing = TRUE)]

get_base_var_plot <- function(exposure_str) {
  for (v in known_vars_sorted) {
    if (startsWith(exposure_str, v)) return(v)
  }
  return(exposure_str)
}

clean_label_domain <- function(x) {
  base       <- get_base_var_plot(x)
  suffix     <- sub(paste0("^", base), "", x)
  suffix     <- gsub("_", " ", trimws(suffix, whitespace = "_"))
  base_clean <- if (!is.na(label_lookup[base])) label_lookup[base] else gsub("_", " ", base)
  if (nchar(suffix) > 0) paste0(base_clean, ": ", suffix) else base_clean
}

# ── Prepare plotting data ─────────────────────────────────────────────────────
df_plot <- df %>%
  mutate(
    base_var = sapply(exposure, get_base_var_plot),
    exp_lab  = sapply(exposure, clean_label_domain),
    med_lab  = ifelse(mediator %in% names(label_lookup),
                      label_lookup[mediator],
                      gsub("_", " ", mediator)),
    is_sig   = !is.na(boot_ci_lower) & !is.na(boot_ci_upper) &
      !(boot_ci_lower <= 0 & boot_ci_upper >= 0)
  ) %>%
  left_join(domain_map, by = c("base_var" = "variable"))

df_plot_mapped <- df_plot %>% filter(!is.na(domain))

unmapped <- df_plot %>% filter(is.na(domain)) %>% distinct(exposure, base_var)
if (nrow(unmapped) > 0) {
  cat("\nUnmapped exposures (excluded):\n"); print(unmapped)
}

# ── DAG function ──────────────────────────────────────────────────────────────
plot_final_labeled_dag <- function(data_subset, title_text) {
  if (nrow(data_subset) == 0) {
    message("No data for DAG: ", title_text); return(NULL)
  }
  
  edges_a <- data_subset %>%
    select(from = exp_lab, to = med_lab, weight = path_a_coef,
           is_sig_edge = is_sig)
  
  edges_b <- data_subset %>%
    select(from = med_lab, weight = path_b_coef, is_sig_edge = is_sig) %>%
    mutate(to = "CVD") %>%
    distinct()
  
  all_edges <- bind_rows(edges_a, edges_b)
  g         <- graph_from_data_frame(all_edges, directed = TRUE)
  v_names   <- V(g)$name
  
  layer <- rep(2, length(v_names))
  layer[v_names == "CVD"] <- 3
  exp_names <- unique(data_subset$exp_lab)
  layer[v_names %in% exp_names] <- 1
  
  coords <- matrix(0, nrow = length(v_names), ncol = 2)
  idx1   <- which(layer == 1)
  idx2   <- which(layer == 2)
  idx3   <- which(layer == 3)
  
  coords[idx1, 1] <- 0
  coords[idx1, 2] <- seq(0, 2000, length.out = max(length(idx1), 1))
  coords[idx2, 1] <- 400
  coords[idx2, 2] <- seq(400, 1600, length.out = max(length(idx2), 1))
  coords[idx3, 1] <- 800
  coords[idx3, 2] <- 1000
  
  max_weight <- max(abs(E(g)$weight), na.rm = TRUE)
  if (max_weight == 0 || !is.finite(max_weight)) max_weight <- 1
  
  edge_sig <- E(g)$is_sig_edge
  edge_wt  <- E(g)$weight
  
  edge_col <- ifelse(edge_wt >  0 &  edge_sig, "#0055FF55",
                     ifelse(edge_wt >  0 & !edge_sig, "#80808055",
                            ifelse(edge_wt <= 0 &  edge_sig, "#FF000055",
                                   "#80808055")))
  
  edge_lty <- ifelse(edge_wt <= 0 & !edge_sig, 2, 1)
  
  par(mar = c(5, 85, 5, 30), cex.main = 4)
  plot(g,
       layout          = coords,
       vertex.color    = c("#0055FF", "#00CC66", "#FF0000")[layer],
       vertex.size     = 0.8,
       vertex.label    = NA,
       edge.width      = 1.2 + 12 * (abs(edge_wt) / max_weight),
       edge.color      = edge_col,
       edge.lty        = edge_lty,
       edge.arrow.size = 0.02,
       rescale         = FALSE,
       xlim            = c(-250, 1000),
       ylim            = c(-100, 2100))
  
  text(x      = mean(range(coords[, 1])),
       y      = max(coords[, 2]) + 120,
       labels = title_text, cex = 6, font = 2)
  
  text(x = coords[idx1, 1] - 25, y = coords[idx1, 2],
       labels = v_names[idx1], adj = 1, cex = 3.2, font = 2, xpd = TRUE)
  
  text(x = coords[idx2, 1], y = coords[idx2, 2] + 30,
       labels = v_names[idx2], cex = 4.5, font = 2, pos = 3)
  
  text(x = coords[idx3, 1] + 35, y = coords[idx3, 2],
       labels = "CVD", cex = 9.0, font = 2, adj = 0)
  
  legend(
    x       = "bottomright",
    legend  = c("Positive", "Negative",
                "Weakly Positive", "Weakly Negative"),
    col     = c("#0055FF88", "#FF000088", "#80808088", "#80808088"),
    lty     = c(1, 1, 1, 2),
    lwd     = c(5, 5, 2, 2),
    bty     = "o", bg = "white", box.col = "grey40",
    cex     = 2.8, title = "Edge type", xpd = TRUE
  )
}

# ── Output ────────────────────────────────────────────────────────────────────
domains_ordered <- c(
  "Demographics & Socioeconomic",
  "Lifestyle",
  "Clinical",
  "Biomarkers",
  "Environment"
)

out_pdf <- file.path(base_dir, "mediation_fig_dags.pdf")
message("Writing PDF: ", out_pdf)

pdf(out_pdf, width = 60, height = 35, onefile = TRUE)

tryCatch({
  for (dom in domains_ordered) {
    message("  DAG: ", dom)
    domain_data <- df_plot_mapped %>% filter(domain == dom)
    if (nrow(domain_data) > 0)
      plot_final_labeled_dag(domain_data, paste0("Mediation Analysis: ", dom))
  }
  message("  DAG: All Domains")
  plot_final_labeled_dag(df_plot_mapped, "Mediation Analysis: All Domains")
}, error = function(e) {
  message("ERROR during plotting: ", e$message)
})

dev.off()
message("=== DONE. Saved to: ", out_pdf, " ===")