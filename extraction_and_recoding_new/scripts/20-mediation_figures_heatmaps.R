# mediation_figures_heatmap.R
# Heatmaps only. DAGs are generated separately in mediation_dag_figures.R

library(dplyr)
library(tibble)
library(ggplot2)
library(cowplot)

# ── Data ──────────────────────────────────────────────────────────────────────
base_dir <- "../outputs"
df <- read.csv(file.path(base_dir, "model1_mediation_indirect_effects_FINAL_6.csv"))

plot_labels  <- read.csv(file.path(base_dir, "plot_labels_domain.csv"), stringsAsFactors = FALSE)
label_lookup <- setNames(plot_labels$plot_label, plot_labels$variable)

# ── Domain map ────────────────────────────────────────────────────────────────
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

unmapped <- df_plot %>% filter(is.na(domain)) %>% distinct(exposure, base_var)
if (nrow(unmapped) > 0) {
  cat("\nUnmapped exposures (excluded from figures):\n"); print(unmapped)
}

df_plot_mapped <- df_plot %>% filter(!is.na(domain))

# ── Axis ordering ─────────────────────────────────────────────────────────────
exposure_order <- df_plot_mapped %>%
  group_by(exp_lab) %>%
  summarise(total_abs = sum(abs(indirect_effect_logodds), na.rm = TRUE),
            .groups = "drop") %>%
  arrange(desc(total_abs)) %>%
  pull(exp_lab)

mediator_order <- df_plot_mapped %>%
  group_by(med_lab) %>%
  summarise(total_abs = sum(abs(indirect_effect_logodds), na.rm = TRUE),
            .groups = "drop") %>%
  arrange(desc(total_abs)) %>%
  pull(med_lab)

# ── Shared theme ──────────────────────────────────────────────────────────────
heatmap_theme <- theme_minimal(base_size = 11) +
  theme(
    axis.text.x    = element_text(angle = 45, hjust = 1, size = 160,
                                  colour = "black"),
    axis.text.y    = element_text(size = 160, colour = "black", hjust = 1,
                                  margin = margin(r = 20)),
    axis.title.x   = element_text(size = 180, face = "bold",
                                  margin = margin(t = 90)),
    axis.title.y   = element_text(size = 180, face = "bold",
                                  margin = margin(r = 110)),
    plot.title     = element_text(size = 190, face = "bold", hjust = 0.5,
                                  margin = margin(t = 45, b = 40)),
    plot.subtitle  = element_text(size = 140, hjust = 0.5, colour = "grey40",
                                  margin = margin(b = 30)),
    legend.position  = "left",
    legend.text      = element_text(size = 55),
    legend.title     = element_text(size = 58, face = "bold"),
    legend.key.size  = unit(3, "cm"),
    panel.grid       = element_blank(),
    plot.margin      = margin(170, 400, 600, 600),
    panel.border     = element_rect(colour = "black", fill = NA, linewidth = 1.2)
  )

# ── Total effects heatmap ─────────────────────────────────────────────────────
total_heat_data <- df_plot_mapped %>%
  select(exp_lab, total_effect_logodds, total_effect_pvalue,
         boot_ci_lower, boot_ci_upper) %>%
  distinct() %>%
  filter(!is.na(total_effect_logodds)) %>%
  mutate(
    exp_lab   = factor(exp_lab, levels = rev(exposure_order)),
    sig_total = !is.na(boot_ci_lower) & !is.na(boot_ci_upper) &
      !(boot_ci_lower <= 0 & boot_ci_upper >= 0)
  )

p_total <- ggplot(total_heat_data,
                  aes(x = "Total Effect", y = exp_lab,
                      fill = total_effect_logodds)) +
  
  geom_tile(color = NA, width = 0.92, height = 0.92) +
  
  geom_tile(data = filter(total_heat_data, sig_total),
            aes(x = "Total Effect", y = exp_lab),
            fill = NA, color = "black", linewidth = 1.5,
            width = 0.92, height = 0.92) +
  
  geom_text(aes(label = paste0(sprintf("%.2f", exp(total_effect_logodds)),
                               "\n(", sprintf("%.2f", exp(boot_ci_lower)),
                               "-", sprintf("%.2f", exp(boot_ci_upper)), ")")),
            color = "black", size = 35, fontface = "bold",
            lineheight = 0.85) +
  
  scale_fill_gradient2(
    low = "#C00000", mid = "white", high = "#2E75B6", midpoint = 0,
    name  = "Total effect\n(log-odds)",
    guide = guide_colorbar(
      barwidth    = 18,
      barheight   = 80,
      title.theme = element_text(size = 120, face = "bold"),
      label.theme = element_text(size = 100)
    )
  ) +
  
  scale_y_discrete(expand = expansion(add = 0.5)) +
  scale_x_discrete(expand = expansion(add = 0.5)) +
  coord_fixed(ratio = 1) +
  
  labs(
    title    = "Total Effects: Stable Exposures",
    subtitle = "Black border = bootstrap 95% CI excludes zero   |   Colour = direction and magnitude (log-odds)",
    x        = NULL,
    y        = "Exposure"
  ) +
  
  heatmap_theme +
  theme(
    axis.text.x      = element_blank(),
    axis.ticks.x     = element_blank(),
    panel.background = element_rect(fill = NA, colour = NA),
    panel.border     = element_rect(fill = NA, colour = NA),
    plot.title       = element_text(size = 190, face = "bold", hjust = 0.5,
                                    margin = margin(t = 80, b = 50)),
    plot.margin      = margin(170, 400, 300, 900)
  )

# ── Indirect effects heatmap ──────────────────────────────────────────────────
heatmap_data <- df_plot_mapped %>%
  mutate(
    exp_lab = factor(exp_lab, levels = exposure_order),
    med_lab = factor(med_lab, levels = rev(mediator_order))
  )

p_heatmap_full <- ggplot(heatmap_data,
                         aes(x = exp_lab, y = med_lab,
                             fill = indirect_effect_logodds)) +
  
  geom_tile(color = NA, linewidth = 0, width = 1, height = 1) +
  
  geom_tile(data = heatmap_data[heatmap_data$is_sig == TRUE & !is.na(heatmap_data$is_sig), ],
            aes(x = exp_lab, y = med_lab),
            fill = NA, color = "black", linewidth = 1.5,
            width = 1, height = 1,
            inherit.aes = FALSE) +
  
  geom_text(data = heatmap_data[heatmap_data$is_sig == TRUE & !is.na(heatmap_data$is_sig), ],
            aes(x = exp_lab, y = med_lab,
                label = ifelse(!is.na(boot_ci_lower) & !is.na(boot_ci_upper),
                               paste0(round(exp(indirect_effect_logodds), 2),
                                      "\n(", round(exp(boot_ci_lower), 2),
                                      ", ", round(exp(boot_ci_upper), 2), ")"),
                               round(exp(indirect_effect_logodds), 4))),
            color = "black", size = 45, fontface = "bold",
            lineheight = 0.85) +
  
  scale_fill_gradient2(
    low = "#C00000", mid = "white", high = "#2E75B6", midpoint = 0,
    name  = "Indirect effect\n(log-odds)",
    guide = guide_colorbar(barwidth = 10, barheight = 50,
                           title.theme = element_text(size = 58),
                           label.theme = element_text(size = 55))
  ) +
  
  scale_x_discrete(expand = expansion(add = 0.6)) +
  scale_y_discrete(expand = expansion(add = 0.6)) +
  coord_cartesian(clip = "off") +
  
  labs(
    title    = "Indirect Effects: Stable Exposures and Biomarkers",
    subtitle = "Black border = bootstrap 95% CI excludes zero   |   Colour = direction and magnitude (log-odds)",
    x        = "Exposure",
    y        = "Biomarker Mediator"
  ) +
  
  heatmap_theme

p_heatmap_legend <- cowplot::get_legend(p_heatmap_full)
p_heatmap <- p_heatmap_full + theme(
  legend.position = "none",
  plot.margin     = margin(170, 400, 600, 600)
)

# ── Output ────────────────────────────────────────────────────────────────────
out_pdf <- file.path(base_dir, "mediation_fig_heatmaps.pdf")
message("Writing PDF: ", out_pdf)

pdf(out_pdf, width = 285, height = 160, onefile = TRUE)

tryCatch({
  message("  Page 1: Total effects heatmap")
  print(p_total)
  
  message("  Page 2: Indirect effects heatmap")
  print(p_heatmap)
}, error = function(e) {
  message("ERROR during plotting: ", e$message)
})

dev.off()
message("=== DONE. Saved to: ", out_pdf, " ===")