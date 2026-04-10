import numpy as np
import pandas as pd
import pyreadr
import xgboost as xgb
import shap
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.backends.backend_pdf import PdfPages
from matplotlib.patches import Patch
import os, sys, datetime, optuna
optuna.logging.set_verbosity(optuna.logging.WARNING)
from sklearn.model_selection import train_test_split, StratifiedKFold
from sklearn.metrics import (
    accuracy_score, f1_score, roc_auc_score, roc_curve,
    precision_recall_curve, classification_report,
    confusion_matrix, ConfusionMatrixDisplay, average_precision_score
)
# ─── 0. CONFIG ────────────────────────────────────────────────────────────────
RESULTS_DIR = "../outputs/summary"
os.makedirs(RESULTS_DIR, exist_ok=True)
N_TRIALS = 50
CV_FOLDS = 5
TOP_N    = 20   # number of SHAP features to keep
class Logger:
    def __init__(self):
        self.terminal = sys.stdout
        self.log = []
    def write(self, message):
        self.terminal.write(message)
        self.log.append(message)
    def flush(self):
        self.terminal.flush()
    def get_log(self):
        return "".join(self.log)
logger = Logger()
sys.stdout = logger
START_TIME = datetime.datetime.now()
print(f"{'='*60}")
print(f"  XGBoost CVD Analysis")
print(f"  Started: {START_TIME.strftime('%Y-%m-%d %H:%M:%S')}")
print(f"{'='*60}\n")
# ─── 1. LOAD DATA ────────────────────────────────────────────────────────────
print(">>> Loading data...")
result = pyreadr.read_r("../outputs/ukb_final_imputed.rds")
df = result[None]
print(f"    Shape: {df.shape}")
# ─── 2. BINARIZE OUTCOME ─────────────────────────────────────────────────────
df["outcome_binary"] = np.where(
    df["outcome"].astype(str).str.strip() == "No", 0, 1
)
n_cases    = int(df["outcome_binary"].sum())
n_controls = int((df["outcome_binary"] == 0).sum())
prevalence = df["outcome_binary"].mean()
print(f"    Cases: {n_cases} | Controls: {n_controls} | "
      f"Prevalence: {prevalence:.2%}\n")
# ─── 3. DROP LEAKAGE / REDUNDANT COLUMNS ────────────────────────────────────
always_drop = [
    "outcome", "outcome_binary",
    "dis_cvd_doc_yn",             # IS the CVD outcome → leakage
    "dis_age_mi",                 # MI is a CVD event  → leakage
    "date_of_death",              # post-outcome date  → leakage
    "dis_date_of_cancer",         # post-outcome date  → leakage
    "attending_assessment_date",  # administrative
    "dob",
]
always_drop = [c for c in always_drop if c in df.columns]
X = df.drop(columns=always_drop)
y = df["outcome_binary"]
# Encode categoricals
cat_cols = X.select_dtypes(include=["object", "category"]).columns.tolist()
if cat_cols:
    print(f">>> Encoding {len(cat_cols)} categorical columns")
    X[cat_cols] = X[cat_cols].astype("category").apply(lambda col: col.cat.codes)
    X[cat_cols] = X[cat_cols].replace(-1, np.nan)
N_FEATURES_TOTAL = X.shape[1]
print(f"    Feature matrix: {X.shape[0]} rows x {N_FEATURES_TOTAL} features\n")
# ─── 4. TRAIN / TEST SPLIT ───────────────────────────────────────────────────
X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.2, random_state=42, stratify=y
)
print(f">>> Train: {X_train.shape[0]} | Test: {X_test.shape[0]}\n")
# ─── 5. YOUDEN'S J THRESHOLD ─────────────────────────────────────────────────
def find_best_threshold(y_true, y_prob):
    """Youden's J = sensitivity + specificity - 1."""
    fpr, tpr, thresholds = roc_curve(y_true, y_prob)
    j_scores = tpr - fpr
    best_idx = np.argmax(j_scores)
    return float(thresholds[best_idx]), float(j_scores[best_idx])
# ─── 6. HYPERPARAMETER TUNING — runs ONCE on all features ────────────────────
def tune_hyperparameters(X_tr, y_tr):
    neg, pos = (y_tr == 0).sum(), (y_tr == 1).sum()
    spw = neg / pos
    kf  = StratifiedKFold(n_splits=CV_FOLDS, shuffle=True, random_state=42)
    def objective(trial):
        params = dict(
            n_estimators          = 500,
            max_depth             = trial.suggest_int  ("max_depth",        3, 12),
            learning_rate         = trial.suggest_float("learning_rate",    0.01, 0.3,  log=True),
            subsample             = trial.suggest_float("subsample",        0.5, 1.0),
            colsample_bytree      = trial.suggest_float("colsample_bytree", 0.5, 1.0),
            min_child_weight      = trial.suggest_int  ("min_child_weight", 1, 20),
            gamma                 = trial.suggest_float("gamma",            0.0, 5.0),
            reg_alpha             = trial.suggest_float("reg_alpha",        1e-4, 10.0, log=True),
            reg_lambda            = trial.suggest_float("reg_lambda",       1e-4, 10.0, log=True),
            scale_pos_weight      = spw,
            eval_metric           = "aucpr",
            early_stopping_rounds = 30,
            random_state          = 42,
            verbosity             = 0,
        )
        fold_scores = []
        for tr_idx, val_idx in kf.split(X_tr, y_tr):
            Xf_tr, Xf_val = X_tr.iloc[tr_idx],  X_tr.iloc[val_idx]
            yf_tr, yf_val = y_tr.iloc[tr_idx],  y_tr.iloc[val_idx]
            m = xgb.XGBClassifier(**params)
            m.fit(Xf_tr, yf_tr, eval_set=[(Xf_val, yf_val)], verbose=False)
            fold_scores.append(
                average_precision_score(yf_val, m.predict_proba(Xf_val)[:, 1])
            )
        return np.mean(fold_scores)
    print(f">>> Hyperparameter tuning on ALL {N_FEATURES_TOTAL} features")
    print(f"    {N_TRIALS} trials × {CV_FOLDS}-fold CV | metric = AUC-PR")
    study = optuna.create_study(direction="maximize",
                                sampler=optuna.samplers.TPESampler(seed=42))
    study.optimize(objective, n_trials=N_TRIALS, show_progress_bar=False)
    print(f"    Best CV AUC-PR : {study.best_value:.4f}")
    print(f"    Best params    : {study.best_params}\n")
    return study.best_params, study
best_params, cv_study = tune_hyperparameters(X_train, y_train)
# ─── 7. TRAIN & EVALUATE HELPER ──────────────────────────────────────────────
def train_model(X_tr, X_te, y_tr, y_te, label, params):
    """Train on X_tr, evaluate on X_te using pre-tuned params."""
    neg, pos = (y_tr == 0).sum(), (y_tr == 1).sum()
    spw = neg / pos
    model = xgb.XGBClassifier(
        n_estimators          = 500,
        **params,
        scale_pos_weight      = spw,
        eval_metric           = "aucpr",
        early_stopping_rounds = 30,
        random_state          = 42,
        verbosity             = 0,
    )
    model.fit(X_tr, y_tr, eval_set=[(X_te, y_te)], verbose=False)
    y_prob         = model.predict_proba(X_te)[:, 1]
    y_pred_default = model.predict(X_te)
    auc            = roc_auc_score(y_te, y_prob)
    f1_default     = f1_score(y_te, y_pred_default)
    best_thresh, _ = find_best_threshold(y_te, y_prob)
    y_pred_opt     = (y_prob >= best_thresh).astype(int)
    f1_opt         = f1_score(y_te, y_pred_opt)
    acc            = accuracy_score(y_te, y_pred_opt)
    report         = classification_report(
        y_te, y_pred_opt, target_names=["No", "Diagnosed"]
    )
    print(f">>> [{label}]")
    print(f"    Features={X_tr.shape[1]} | scale_pos_weight={spw:.2f}")
    print(f"    AUC={auc:.4f} | F1@0.5={f1_default:.4f} | "
          f"F1@Youden({best_thresh:.3f})={f1_opt:.4f}")
    print(f"\n    Classification Report:\n{report}")
    return {
        "label":          label,
        "AUC":            auc,
        "F1_default":     f1_default,
        "F1_optimal":     f1_opt,
        "Accuracy":       acc,
        "threshold":      best_thresh,
        "report":         report,
        "model":          model,
        "y_prob":         y_prob,
        "y_pred":         y_pred_opt,
        "features":       list(X_tr.columns),
        "best_iteration": model.best_iteration,
    }
# ─── 7b. INCREMENTAL SHAP AUC HELPER ─────────────────────────────────────────
def incremental_shap_auc(shap_ranked_features, X_tr, y_tr, X_te, y_te, params):
    """
    Add features one-by-one in SHAP rank order (most important first).
    Trains XGBoost at each step and records AUC-ROC on the test set.
    Returns a list of AUC values (length = len(shap_ranked_features)).
    """
    neg, pos = (y_tr == 0).sum(), (y_tr == 1).sum()
    spw = neg / pos
    aucs = []
    n_total = len(shap_ranked_features)
    for n in range(1, n_total + 1):
        feats = shap_ranked_features[:n]
        model = xgb.XGBClassifier(
            n_estimators          = 500,
            **params,
            scale_pos_weight      = spw,
            eval_metric           = "aucpr",
            early_stopping_rounds = 30,
            random_state          = 42,
            verbosity             = 0,
        )
        model.fit(
            X_tr[feats], y_tr,
            eval_set=[(X_te[feats], y_te)],
            verbose=False,
        )
        auc = roc_auc_score(y_te, model.predict_proba(X_te[feats])[:, 1])
        aucs.append(auc)
        if n % 5 == 0 or n == n_total:
            print(f"  Step {n:3d}/{n_total}: {shap_ranked_features[n-1]:<35}  AUC={auc:.4f}")
    return aucs

# ─── 8. MODEL A — ALL FEATURES (trained once) ────────────────────────────────
results_A = train_model(
    X_train, X_test, y_train, y_test,
    label=f"Model A — all {N_FEATURES_TOTAL} features",
    params=best_params,
)
# ─── 9. SHAP — computed from Model A ─────────────────────────────────────────
print(f"\n>>> Computing SHAP values from Model A...")
explainer   = shap.TreeExplainer(results_A["model"])
shap_values = explainer.shap_values(X_train)
shap_importance = pd.DataFrame({
    "Feature":    X_train.columns,
    "SHAP_value": np.abs(shap_values).mean(axis=0),
}).sort_values("SHAP_value", ascending=False).reset_index(drop=True)
shap_importance["Rank"] = shap_importance.index + 1
shap_importance["Cumulative_pct"] = (
    shap_importance["SHAP_value"].cumsum()
    / shap_importance["SHAP_value"].sum() * 100
)
selected_features = shap_importance.head(TOP_N)["Feature"].tolist()
shap_ranked_all   = shap_importance["Feature"].tolist()   # ALL features ranked
print(f"    Top {TOP_N} features cover "
      f"{shap_importance.iloc[TOP_N-1]['Cumulative_pct']:.1f}% of SHAP importance")
print(f"\n    Top {TOP_N} features:")
print(shap_importance[["Rank","Feature","SHAP_value","Cumulative_pct"]]
      .head(TOP_N).to_string(index=False))
# ─── 9b. INCREMENTAL AUC — one feature added per step ────────────────────────
print(f"\n>>> Incremental AUC: adding each SHAP feature one by one "
      f"({len(shap_ranked_all)} steps)...")
incr_aucs = incremental_shap_auc(
    shap_ranked_all, X_train, y_train, X_test, y_test, best_params
)
peak_n   = int(np.argmax(incr_aucs)) + 1
peak_auc = float(np.max(incr_aucs))
print(f"    Peak AUC = {peak_auc:.4f} at top-{peak_n} features")
# ── Save incremental AUC figure ──────────────────────────────────────────────
steps      = list(range(1, len(shap_ranked_all) + 1))
n_features = len(shap_ranked_all)

# x-axis: show at most 25 feature-name labels to avoid overlap
tick_step = max(1, n_features // 25)
tick_pos  = list(range(1, n_features + 1, tick_step))
tick_labs = [shap_ranked_all[i - 1] for i in tick_pos]

fig_incr, ax_incr = plt.subplots(figsize=(14, 5))
ax_incr.fill_between(steps, incr_aucs, alpha=0.12, color="#2196F3")
ax_incr.plot(steps, incr_aucs, color="#2196F3", lw=2, marker="o",
             markersize=3, zorder=3)

# Mark selected TOP_N
ax_incr.axvline(TOP_N,  color="#FF5722", lw=1.8, linestyle="--",
                label=f"Model B cut-off (top {TOP_N})")
# Mark peak
ax_incr.axvline(peak_n, color="#4CAF50", lw=1.5, linestyle=":",
                label=f"Peak AUC = {peak_auc:.4f} (top {peak_n})")
ax_incr.scatter([peak_n], [peak_auc], color="#4CAF50", s=60, zorder=5)

ax_incr.set_xticks(tick_pos)
ax_incr.set_xticklabels(tick_labs, rotation=45, ha="right", fontsize=7)
ax_incr.set_xlabel("Features added (SHAP importance order — most important first)",
                   fontsize=11)
ax_incr.set_ylabel("AUC-ROC", fontsize=11)
ax_incr.set_title(
    "Incremental SHAP Feature Selection — AUC-ROC vs Features Added",
    fontsize=12, fontweight="bold"
)
ax_incr.set_xlim(1, n_features)
ax_incr.set_ylim(max(0, min(incr_aucs) - 0.02),
                 min(1.0, peak_auc + 0.03))
ax_incr.legend(fontsize=10)
ax_incr.grid(True, alpha=0.3)
fig_incr.tight_layout()
fig_incr.savefig(os.path.join(RESULTS_DIR, "shap_incremental_auc.png"), dpi=150)
plt.close(fig_incr)
print(f"    Saved: shap_incremental_auc.png")

# ─── 10. MODEL B — SHAP-SELECTED FEATURES (same tuned params, retrained) ─────
# Note: we RETRAIN on the reduced feature set — a model trained on all features
# cannot directly predict on a subset. Same hyperparameters, new fit.
print(f"\n>>> Retraining on top {TOP_N} SHAP features "
      f"(same hyperparameters, new fit)...")
results_B = train_model(
    X_train[selected_features], X_test[selected_features],
    y_train, y_test,
    label=f"Model B — top {TOP_N} SHAP features",
    params=best_params,
)
# ─── 11. COMPARISON TABLE ────────────────────────────────────────────────────
comparison = pd.DataFrame([
    {
        "Model":            r["label"],
        "N Features":       len(r["features"]),
        "AUC":              round(r["AUC"], 4),
        "F1 (thr=0.5)":     round(r["F1_default"], 4),
        "F1 (Youden's J)":  round(r["F1_optimal"], 4),
        "Threshold":        round(r["threshold"], 3),
        "Accuracy":         round(r["Accuracy"], 4),
        "Best Iteration":   r["best_iteration"],
    }
    for r in [results_A, results_B]
])
print(f"\n{'='*60}\nMODEL COMPARISON\n{'='*60}")
print(comparison.to_string(index=False))
delta_auc = results_B["AUC"] - results_A["AUC"]
print(f"\n    AUC difference (B - A): {delta_auc:+.4f}")
print(f"    Feature reduction:      "
      f"{N_FEATURES_TOTAL} → {TOP_N} "
      f"({100*(1-TOP_N/N_FEATURES_TOTAL):.1f}% fewer features)")
comparison.to_csv(os.path.join(RESULTS_DIR, "metrics_comparison.csv"), index=False)
# ─── 12. SAVE SELECTED FEATURES ──────────────────────────────────────────────
features_path = os.path.join(RESULTS_DIR, "selected_features.txt")
with open(features_path, "w") as f:
    f.write(f"SHAP-Selected Features — Top {TOP_N} from Model A\n")
    f.write(f"Generated: {START_TIME.strftime('%Y-%m-%d %H:%M:%S')}\n")
    f.write("=" * 60 + "\n\n")
    for i, feat in enumerate(selected_features, 1):
        row = shap_importance[shap_importance["Feature"] == feat].iloc[0]
        f.write(f"{i:>3}. {feat:<45}  "
                f"SHAP={row['SHAP_value']:.6f}  "
                f"Cum%={row['Cumulative_pct']:.1f}%\n")
shap_importance.to_csv(os.path.join(RESULTS_DIR, "shap_importance.csv"), index=False)
print(f"\n    Saved: {features_path}")
END_TIME = datetime.datetime.now()
print(f"\n{'='*60}")
print(f"  Finished: {END_TIME.strftime('%Y-%m-%d %H:%M:%S')}")
print(f"  Duration: {str(END_TIME - START_TIME).split('.')[0]}")
print(f"{'='*60}")
# ─── 13. FIGURES ─────────────────────────────────────────────────────────────
print("\n>>> Generating figures...")
colors = ["steelblue", "darkorange"]
# Fig 1: ROC + bar comparison
fig1, axes = plt.subplots(1, 2, figsize=(16, 6))
fig1.suptitle("Model A (all features) vs Model B (SHAP-selected)",
              fontsize=14, fontweight="bold")
for r, color in zip([results_A, results_B], colors):
    fpr, tpr, _ = roc_curve(y_test, r["y_prob"])
    axes[0].plot(fpr, tpr, color=color, lw=2,
                 label=f"{r['label']}\n(AUC={r['AUC']:.3f})")
axes[0].plot([0,1],[0,1],"k--",lw=1,label="Random (AUC=0.5)")
axes[0].set(title="ROC Curves", xlabel="FPR", ylabel="TPR")
axes[0].legend(fontsize=8, loc="lower right")
bar_data = pd.DataFrame({
    "AUC":           [r["AUC"]        for r in [results_A, results_B]],
    "F1 (thr=0.5)":  [r["F1_default"] for r in [results_A, results_B]],
    "F1 (Youden's)": [r["F1_optimal"] for r in [results_A, results_B]],
    "Accuracy":      [r["Accuracy"]   for r in [results_A, results_B]],
}, index=[f"Model A\n({N_FEATURES_TOTAL} feat.)", f"Model B\n({TOP_N} feat.)"])
bar_data.plot(kind="bar", ax=axes[1], rot=0, ylim=(0, 1.15),
              color=["steelblue","darkorange","tomato","seagreen"], width=0.7)
axes[1].set_title("Metrics Comparison")
axes[1].legend(loc="upper right", fontsize=8)
axes[1].axhline(0.5, color="grey", linestyle="--", lw=0.8, alpha=0.5)
for container in axes[1].containers:
    axes[1].bar_label(container, fmt="%.3f", padding=2, fontsize=7)
fig1.tight_layout()
fig1.savefig(os.path.join(RESULTS_DIR, "model_comparison.png"), dpi=150)
plt.close(fig1)
# Fig 2: Confusion matrices
fig2, axes2 = plt.subplots(1, 2, figsize=(12, 5))
fig2.suptitle("Confusion Matrices (Youden's J threshold)",
              fontsize=14, fontweight="bold")
for ax, r, color in zip(axes2, [results_A, results_B], colors):
    cm   = confusion_matrix(y_test, r["y_pred"])
    disp = ConfusionMatrixDisplay(cm, display_labels=["No", "Diagnosed"])
    disp.plot(ax=ax, colorbar=False, cmap="Blues")
    tn, fp, fn, tp = cm.ravel()
    ax.set_title(
        f"{r['label']}\n"
        f"threshold={r['threshold']:.3f} | "
        f"Sens={tp/(tp+fn):.3f} | Spec={tn/(tn+fp):.3f}",
        fontsize=8
    )
fig2.tight_layout()
fig2.savefig(os.path.join(RESULTS_DIR, "confusion_matrices.png"), dpi=150)
plt.close(fig2)
# Fig 3: Precision-Recall
fig3, ax3 = plt.subplots(figsize=(8, 6))
for r, color in zip([results_A, results_B], colors):
    prec, rec, _ = precision_recall_curve(y_test, r["y_prob"])
    ax3.plot(rec, prec, color=color, lw=2,
             label=f"{r['label']} (F1={r['F1_optimal']:.3f})")
ax3.axhline(prevalence, color="grey", linestyle="--", lw=1,
            label=f"No-skill baseline ({prevalence:.1%})")
ax3.set(title="Precision-Recall Curves", xlabel="Recall", ylabel="Precision")
ax3.legend(fontsize=8)
fig3.tight_layout()
fig3.savefig(os.path.join(RESULTS_DIR, "precision_recall.png"), dpi=150)
plt.close(fig3)
# Fig 4: SHAP beeswarm
shap.summary_plot(shap_values, X_train, max_display=20, show=False)
fig4 = plt.gcf()
fig4.tight_layout()
fig4.savefig(os.path.join(RESULTS_DIR, "shap_beeswarm.png"), dpi=150)
plt.close(fig4)
# Fig 5: SHAP bar importance
fig5, ax5 = plt.subplots(figsize=(10, 8))
top_plot = shap_importance.head(TOP_N).sort_values("SHAP_value")
bar_cols  = ["tomato" if f in selected_features else "steelblue"
             for f in top_plot["Feature"]]
ax5.barh(top_plot["Feature"], top_plot["SHAP_value"], color=bar_cols)
ax5.set_xlabel("Mean |SHAP value|")
ax5.set_title(f"Top {TOP_N} Features by SHAP Importance (from Model A)",
              fontweight="bold")
ax5.legend(handles=[
    Patch(color="tomato",    label=f"Used in Model B (top {TOP_N})"),
    Patch(color="steelblue", label="Not in Model B"),
], fontsize=9)
fig5.tight_layout()
fig5.savefig(os.path.join(RESULTS_DIR, "shap_importance.png"), dpi=150)
plt.close(fig5)
# Fig 5b: SHAP incrementation / cumulative importance plot
plot_all = shap_importance.copy()   # all features, ranked
n_all    = len(plot_all)
x_pos    = np.arange(n_all)
fig_inc, ax_inc = plt.subplots(figsize=(14, 5))
# ── bars: individual SHAP contribution of each ranked feature ──
bar_colors = ["tomato" if i < TOP_N else "steelblue" for i in range(n_all)]
ax_inc.bar(x_pos, plot_all["SHAP_value"], color=bar_colors,
           width=1.0, align="center", alpha=0.85, label="Individual |SHAP|")
# ── line: cumulative importance % (right-hand y-axis) ──
ax2_inc = ax_inc.twinx()
ax2_inc.plot(x_pos, plot_all["Cumulative_pct"], color="black",
             lw=2, label="Cumulative importance (%)")
ax2_inc.set_ylabel("Cumulative SHAP importance (%)", fontsize=10)
ax2_inc.set_ylim(0, 105)
ax2_inc.axhline(80, color="grey", lw=0.8, linestyle=":", alpha=0.7)
ax2_inc.axhline(95, color="grey", lw=0.8, linestyle=":", alpha=0.7)
ax2_inc.text(n_all * 0.98, 80.5, "80%", fontsize=7, color="grey", ha="right")
ax2_inc.text(n_all * 0.98, 95.5, "95%", fontsize=7, color="grey", ha="right")
# ── vertical cut-off line at TOP_N ──
ax_inc.axvline(TOP_N - 0.5, color="black", lw=1.5, linestyle="--")
cum_at_topn = plot_all.iloc[TOP_N - 1]["Cumulative_pct"]
ax_inc.text(TOP_N, ax_inc.get_ylim()[1] * 0.95,
            f"Top {TOP_N}\n({cum_at_topn:.1f}%)",
            fontsize=8, ha="left", va="top",
            bbox=dict(boxstyle="round,pad=0.3", fc="white", ec="black", lw=0.8))
ax_inc.set_xlabel("Feature rank (by mean |SHAP value|)", fontsize=10)
ax_inc.set_ylabel("Mean |SHAP value|", fontsize=10)
ax_inc.set_title(
    f"SHAP Incrementation Plot — cumulative importance across all {n_all} features\n"
    f"(red = selected top {TOP_N}, blue = excluded)",
    fontsize=12, fontweight="bold"
)
ax_inc.set_xlim(-0.5, n_all - 0.5)
ax_inc.set_xticks([])   # too many features to label; remove clutter
# combined legend
handles_inc = [
    Patch(color="tomato",    label=f"Top {TOP_N} (selected)"),
    Patch(color="steelblue", label="Excluded"),
    plt.Line2D([0], [0], color="black", lw=2, label="Cumulative importance (%)"),
    plt.Line2D([0], [0], color="black", lw=1.5, linestyle="--", label=f"TOP_N cut-off"),
]
ax_inc.legend(handles=handles_inc, fontsize=8, loc="center right")
fig_inc.tight_layout()
fig_inc.savefig(os.path.join(RESULTS_DIR, "shap_incrementation.png"), dpi=150)
plt.close(fig_inc)
# Fig 6: CV optimisation history
trials     = [t for t in cv_study.trials if t.value is not None]
scores     = np.array([t.value for t in trials])
trial_nums = [t.number for t in trials]
running_best = [scores[:i+1].max() for i in range(len(scores))]
score_norm   = (scores - scores.min()) / (scores.max() - scores.min() + 1e-9)
fig6, ax6 = plt.subplots(figsize=(10, 4))
sc = ax6.scatter(trial_nums, scores, c=score_norm,
                 cmap=plt.cm.RdYlGn, s=35, alpha=0.8, zorder=3)
ax6.plot(trial_nums, running_best, color="steelblue", lw=2, label="Running best")
ax6.axhline(scores.max(), color="tomato", lw=1, linestyle="--",
            label=f"Best = {scores.max():.4f}")
plt.colorbar(sc, ax=ax6, label="AUC-PR (normalised)")
ax6.set(xlabel="Trial", ylabel="CV AUC-PR",
        title="Hyperparameter Optimisation History")
ax6.legend(fontsize=9)
fig6.tight_layout()
fig6.savefig(os.path.join(RESULTS_DIR, "cv_history.png"), dpi=150)
plt.close(fig6)
print("    All figures saved.")
# ─── 14. PDF REPORT ──────────────────────────────────────────────────────────
print("\n>>> Generating PDF report...")
def add_text_page(pdf, title, body_lines, fontsize=9):
    fig = plt.figure(figsize=(11, 8.5))
    fig.patch.set_facecolor("white")
    ax = fig.add_axes([0.05, 0.05, 0.9, 0.9])
    ax.axis("off")
    ax.set_title(title, fontsize=13, fontweight="bold", pad=12)
    ax.text(0, 1, "\n".join(str(l) for l in body_lines),
            transform=ax.transAxes, fontsize=fontsize,
            family="monospace", verticalalignment="top")
    pdf.savefig(fig)
    plt.close(fig)
def add_image_page(pdf, img_path, title):
    fig = plt.figure(figsize=(11, 8.5))
    img = plt.imread(img_path)
    ax  = fig.add_axes([0.05, 0.05, 0.90, 0.85])
    ax.imshow(img)
    ax.axis("off")
    ax.set_title(title, fontsize=13, fontweight="bold", pad=10)
    pdf.savefig(fig)
    plt.close(fig)
pdf_path = os.path.join(RESULTS_DIR, "report_xgboost.pdf")
with PdfPages(pdf_path) as pdf:
    # Cover
    fig_cov = plt.figure(figsize=(11, 8.5))
    fig_cov.patch.set_facecolor("#1a1a2e")
    ax_c = fig_cov.add_axes([0, 0, 1, 1])
    ax_c.axis("off")
    ax_c.text(0.5, 0.65, "XGBoost CVD Analysis",
              color="white", fontsize=26, fontweight="bold",
              ha="center", va="center", transform=ax_c.transAxes)
    ax_c.text(0.5, 0.53,
              "Train once on all features → SHAP selection → Retrain",
              color="#a0a0c0", fontsize=13,
              ha="center", va="center", transform=ax_c.transAxes)
    ax_c.text(0.5, 0.40,
              f"Generated: {START_TIME.strftime('%Y-%m-%d %H:%M:%S')}\n"
              f"Duration:  {str(END_TIME - START_TIME).split('.')[0]}",
              color="#808090", fontsize=11, ha="center", va="center",
              transform=ax_c.transAxes, family="monospace")
    pdf.savefig(fig_cov)
    plt.close(fig_cov)
    # 1. Dataset summary
    cat_lines = [f"  - {c}" for c in cat_cols] if cat_cols else ["  None"]
    add_text_page(pdf, "1. Dataset Summary", [
        f"Rows:              {df.shape[0]}",
        f"Cases (1):         {n_cases}",
        f"Controls (0):      {n_controls}",
        f"Prevalence:        {prevalence:.2%}",
        f"Train / Test:      {X_train.shape[0]} / {X_test.shape[0]}",
        f"Total features:    {N_FEATURES_TOTAL}",
        f"SHAP top-N:        {TOP_N}",
        f"Threshold method:  Youden's J",
        "",
        "Workflow:",
        "  1. Tune hyperparameters once (Optuna, all features)",
        "  2. Train Model A on ALL features",
        "  3. Compute SHAP values from Model A",
        f" 4. Select top {TOP_N} features by SHAP importance",
        "  5. Retrain Model B on SHAP features (same hyperparameters)",
        "",
        "Dropped columns (leakage/redundant):",
        *[f"  - {c}" for c in always_drop],
        "",
        "Encoded categorical columns:",
        *cat_lines,
    ])
    # 2. Hyperparameter tuning
    cv_rows  = sorted(cv_study.trials, key=lambda t: t.value or 0, reverse=True)[:10]
    cv_lines = [
        f"Tuned on: ALL {N_FEATURES_TOTAL} features (used for both models)",
        f"Optimizer: Optuna TPE | Trials: {N_TRIALS} | CV folds: {CV_FOLDS}",
        f"Metric:    AUC-PR",
        f"Best CV AUC-PR: {cv_study.best_value:.4f}",
        "", "── Top 10 trials ──",
    ]
    for rank, t in enumerate(cv_rows, 1):
        cv_lines.append(f"{rank:>2}. AUC-PR={t.value:.4f}  {t.params}")
    cv_lines += ["", "── Best Parameters (applied to BOTH models) ──"]
    for k, v in best_params.items():
        cv_lines.append(f"  {k:<25} = {v}")
    add_text_page(pdf, "2. Hyperparameter Tuning (Optuna)", cv_lines)
    add_image_page(pdf, os.path.join(RESULTS_DIR, "cv_history.png"),
                   "2b. Optimisation History")
    # 3. Model comparison
    add_text_page(pdf, "3. Model Comparison", [
        comparison.to_string(index=False),
        "",
        f"AUC difference (B - A):   {delta_auc:+.4f}",
        f"Feature reduction:        "
        f"{N_FEATURES_TOTAL} → {TOP_N} "
        f"({100*(1-TOP_N/N_FEATURES_TOTAL):.1f}% fewer features)",
        "",
        f"Model A — best iteration:  {results_A['best_iteration']}",
        f"Model A — Youden thresh:   {results_A['threshold']:.3f}",
        "",
        f"Model B — best iteration:  {results_B['best_iteration']}",
        f"Model B — Youden thresh:   {results_B['threshold']:.3f}",
        "",
        "─── Model A Classification Report ───",
        results_A["report"],
        "",
        "─── Model B Classification Report ───",
        results_B["report"],
    ])
    add_image_page(pdf, os.path.join(RESULTS_DIR, "model_comparison.png"),
                   "4. ROC Curves & Metrics")
    add_image_page(pdf, os.path.join(RESULTS_DIR, "confusion_matrices.png"),
                   "5. Confusion Matrices (Youden's J)")
    add_image_page(pdf, os.path.join(RESULTS_DIR, "precision_recall.png"),
                   "6. Precision-Recall Curves")
    add_image_page(pdf, os.path.join(RESULTS_DIR, "shap_beeswarm.png"),
                   "7. SHAP Beeswarm (Model A)")
    add_image_page(pdf, os.path.join(RESULTS_DIR, "shap_importance.png"),
                   f"8. Top {TOP_N} SHAP Features — red = used in Model B")
    add_image_page(pdf, os.path.join(RESULTS_DIR, "shap_incrementation.png"),
                   f"8b. SHAP Incrementation — cumulative importance across all {N_FEATURES_TOTAL} features")
    add_image_page(pdf, os.path.join(RESULTS_DIR, "shap_incremental_auc.png"),
                   f"8c. Incremental AUC — AUC-ROC as each SHAP feature is added")
    # Selected features
    lines = [
        f"Top {TOP_N} SHAP Features (from Model A) → used to train Model B",
        "=" * 58, "",
    ]
    for i, feat in enumerate(selected_features, 1):
        row = shap_importance[shap_importance["Feature"] == feat].iloc[0]
        lines.append(f"{i:>3}. {feat:<45}  "
                     f"SHAP={row['SHAP_value']:.6f}  "
                     f"Cum%={row['Cumulative_pct']:.1f}%")
    add_text_page(pdf, "9. SHAP-Selected Features", lines, fontsize=8)
    # Full log
    log_lines   = logger.get_log().split("\n")
    chunk_size  = 65
    n_log_pages = (len(log_lines) // chunk_size) + 1
    for i in range(n_log_pages):
        add_text_page(pdf,
                      f"10. Full Run Log (part {i+1}/{n_log_pages})",
                      log_lines[i*chunk_size:(i+1)*chunk_size],
                      fontsize=7)
    d = pdf.infodict()
    d["Title"]        = "XGBoost CVD Analysis Report"
    d["CreationDate"] = START_TIME
print(f"    Saved: {pdf_path}")
print(f"\n>>> All outputs in: {RESULTS_DIR}/")
print("\nFiles created:")
for fname in sorted(os.listdir(RESULTS_DIR)):
    size = os.path.getsize(os.path.join(RESULTS_DIR, fname))
    print(f"    {fname:<40}  {size/1024:.1f} KB")
