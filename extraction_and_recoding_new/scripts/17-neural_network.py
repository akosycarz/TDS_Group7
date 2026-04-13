import numpy as np
import pandas as pd
import pyreadr
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.backends.backend_pdf import PdfPages
import os, sys, datetime, warnings
warnings.filterwarnings("ignore")

import torch
import torch.nn as nn
from torch.utils.data import DataLoader, TensorDataset

from sklearn.model_selection import StratifiedKFold
from sklearn.preprocessing import StandardScaler
from sklearn.metrics import (
    roc_auc_score, roc_curve, f1_score, classification_report,
    confusion_matrix, ConfusionMatrixDisplay,
    precision_recall_curve, average_precision_score
)

# ─── 0. CONFIG ────────────────────────────────────────────────────────────────
RESULTS_DIR = "../outputs/NN_results"
os.makedirs(RESULTS_DIR, exist_ok=True)

BASE_PATH   = "../outputs"
TRAIN_FILE  = "ukb_selection_60_imputed.rds"
VAL_FILE    = "ukb_refit_20_imputed.rds"
TEST_FILE   = "ukb_test_20_imputed.rds"

BATCH_SIZE  = 2048
MAX_EPOCHS  = 100
PATIENCE    = 10
LR          = 1e-3
DROPOUT     = 0.3
HIDDEN_DIMS = [256, 128, 64]
SEED        = 42
CV_FOLDS    = 5

torch.manual_seed(SEED)
np.random.seed(SEED)
DEVICE = torch.device("cuda" if torch.cuda.is_available() else "cpu")

class Logger:
    def __init__(self):
        self.terminal = sys.stdout
        self.log      = []
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
print(f"  Neural Network CVD Analysis")
print(f"  Started: {START_TIME.strftime('%Y-%m-%d %H:%M:%S')}")
print(f"  Device:  {DEVICE}")
print(f"{'='*60}\n")

# ─── 1. LOAD DATA ─────────────────────────────────────────────────────────────
print(">>> Loading pre-split datasets...")

def load_rds(path):
    return pyreadr.read_r(path)[None]

df_train = load_rds(os.path.join(BASE_PATH, TRAIN_FILE))
df_val   = load_rds(os.path.join(BASE_PATH, VAL_FILE))
df_test  = load_rds(os.path.join(BASE_PATH, TEST_FILE))

print(f"    Train (selection 60%): {df_train.shape}")
print(f"    Val   (refit    20%): {df_val.shape}")
print(f"    Test  (test     20%): {df_test.shape}\n")

# ─── 2. BINARIZE OUTCOME ──────────────────────────────────────────────────────
def binarize(df):
    df = df.copy()
    df["outcome_binary"] = np.where(
        df["outcome"].astype(str).str.strip() == "No", 0, 1
    )
    return df

df_train = binarize(df_train)
df_val   = binarize(df_val)
df_test  = binarize(df_test)

# Report class balance from training set
n_cases    = int(df_train["outcome_binary"].sum())
n_controls = int((df_train["outcome_binary"] == 0).sum())
prevalence = df_train["outcome_binary"].mean()
print(f">>> Training set class balance:")
print(f"    Cases: {n_cases} | Controls: {n_controls} | "
      f"Prevalence: {prevalence:.2%}\n")

# ─── 3. DROP LEAKAGE / REDUNDANT COLUMNS ──────────────────────────────────────
always_drop = [
    "outcome", "outcome_binary",
    "dis_cvd_doc_yn",
    "dis_age_mi",
    "date_of_death",
    "dis_date_of_cancer",
    "attending_assessment_date",
    "dob",
]

def prepare_xy(df):
    drop = [c for c in always_drop if c in df.columns]
    X = df.drop(columns=drop)
    y = df["outcome_binary"].values
    cat_cols = X.select_dtypes(include=["object", "category"]).columns.tolist()
    if cat_cols:
        X[cat_cols] = X[cat_cols].astype("category").apply(lambda col: col.cat.codes)
        X[cat_cols] = X[cat_cols].replace(-1, np.nan)
    return X, y

X_train_df, y_train = prepare_xy(df_train)
X_val_df,   y_val   = prepare_xy(df_val)
X_test_df,  y_test  = prepare_xy(df_test)

# ─── 4. ALIGN FEATURES ACROSS SPLITS ─────────────────────────────────────────
# Train columns are the reference — drop any extra cols in val/test,
# fill any missing cols in val/test with 0
train_cols = X_train_df.columns.tolist()

def align_to_train(df, ref_cols):
    for c in ref_cols:
        if c not in df.columns:
            df[c] = 0.0
    return df[ref_cols]

X_val_df  = align_to_train(X_val_df,  train_cols)
X_test_df = align_to_train(X_test_df, train_cols)

feature_names = train_cols
print(f">>> Feature matrix: {len(feature_names)} features")
print(f"    Train rows: {len(y_train)} | Val rows: {len(y_val)} | "
      f"Test rows: {len(y_test)}\n")

# ─── 5. SCALE — fit on train only ─────────────────────────────────────────────
scaler  = StandardScaler()
X_train = np.nan_to_num(scaler.fit_transform(X_train_df.values.astype(np.float32)), nan=0.0)
X_val   = np.nan_to_num(scaler.transform(X_val_df.values.astype(np.float32)),       nan=0.0)
X_test  = np.nan_to_num(scaler.transform(X_test_df.values.astype(np.float32)),      nan=0.0)

# Keep raw train array for CV (CV re-fits its own scaler per fold)
X_train_raw = X_train_df.values.astype(np.float32)

# ─── 6. BUILD PYTORCH DATALOADERS ─────────────────────────────────────────────
def make_loader(X_arr, y_arr, shuffle=False):
    X_t = torch.tensor(X_arr, dtype=torch.float32)
    y_t = torch.tensor(y_arr, dtype=torch.float32)
    return DataLoader(TensorDataset(X_t, y_t),
                      batch_size=BATCH_SIZE, shuffle=shuffle)

train_loader = make_loader(X_train, y_train, shuffle=True)
val_loader   = make_loader(X_val,   y_val)
test_loader  = make_loader(X_test,  y_test)

# ─── 7. DEFINE MODEL ──────────────────────────────────────────────────────────
class MLP(nn.Module):
    def __init__(self, input_dim, hidden_dims, dropout):
        super().__init__()
        layers = []
        prev = input_dim
        for h in hidden_dims:
            layers += [
                nn.Linear(prev, h),
                nn.BatchNorm1d(h),
                nn.ReLU(),
                nn.Dropout(dropout),
            ]
            prev = h
        layers.append(nn.Linear(prev, 1))
        self.net = nn.Sequential(*layers)

    def forward(self, x):
        return self.net(x).squeeze(1)

model    = MLP(X_train.shape[1], HIDDEN_DIMS, DROPOUT).to(DEVICE)
n_params = sum(p.numel() for p in model.parameters() if p.requires_grad)
print(f">>> Model architecture:\n{model}\n")
print(f"    Trainable parameters: {n_params:,}\n")

# ─── 8. CLASS WEIGHT FOR IMBALANCE ────────────────────────────────────────────
pos_weight = torch.tensor([n_controls / n_cases], dtype=torch.float32).to(DEVICE)
criterion  = nn.BCEWithLogitsLoss(pos_weight=pos_weight)
optimizer  = torch.optim.Adam(model.parameters(), lr=LR)
scheduler  = torch.optim.lr_scheduler.ReduceLROnPlateau(
    optimizer, mode="min", factor=0.5, patience=5
)

# ─── 9. TRAINING LOOP (early stopping on refit/val set) ───────────────────────
print(">>> Training on selection (60%) | early stopping on refit (20%)...")
train_losses, val_losses = [], []
best_val_loss   = np.inf
patience_count  = 0
best_state_dict = None

for epoch in range(1, MAX_EPOCHS + 1):
    model.train()
    epoch_loss = 0.0
    for X_batch, y_batch in train_loader:
        X_batch, y_batch = X_batch.to(DEVICE), y_batch.to(DEVICE)
        optimizer.zero_grad()
        loss = criterion(model(X_batch), y_batch)
        loss.backward()
        optimizer.step()
        epoch_loss += loss.item() * len(y_batch)
    train_losses.append(epoch_loss / len(y_train))

    model.eval()
    val_loss = 0.0
    with torch.no_grad():
        for X_batch, y_batch in val_loader:
            X_batch, y_batch = X_batch.to(DEVICE), y_batch.to(DEVICE)
            val_loss += criterion(model(X_batch), y_batch).item() * len(y_batch)
    val_loss /= len(y_val)
    val_losses.append(val_loss)
    scheduler.step(val_loss)

    if epoch % 10 == 0:
        print(f"    Epoch {epoch:3d}/{MAX_EPOCHS} | "
              f"train loss: {train_losses[-1]:.4f} | "
              f"val loss: {val_loss:.4f}")

    if val_loss < best_val_loss:
        best_val_loss   = val_loss
        patience_count  = 0
        best_state_dict = {k: v.clone() for k, v in model.state_dict().items()}
    else:
        patience_count += 1
        if patience_count >= PATIENCE:
            print(f"\n    Early stopping at epoch {epoch} "
                  f"(no improvement for {PATIENCE} epochs)\n")
            break

model.load_state_dict(best_state_dict)
print(f"    Best val loss: {best_val_loss:.4f}\n")

# ─── 10. PREDICTIONS ON HELD-OUT TEST SET ─────────────────────────────────────
def get_probs(loader):
    model.eval()
    probs = []
    with torch.no_grad():
        for X_batch, _ in loader:
            logits = model(X_batch.to(DEVICE))
            probs.append(torch.sigmoid(logits).cpu().numpy())
    return np.concatenate(probs)

y_prob_val     = get_probs(val_loader)
y_prob_test    = get_probs(test_loader)
y_pred_default = (y_prob_test >= 0.5).astype(int)

# ─── 11. YOUDEN'S J THRESHOLD (calibrated on val, applied to test) ────────────
def find_best_threshold(y_true, y_prob):
    fpr, tpr, thresholds = roc_curve(y_true, y_prob)
    j_scores = tpr - fpr
    best_idx = np.argmax(j_scores)
    return float(thresholds[best_idx]), float(j_scores[best_idx])

# Calibrate threshold on VAL set
best_thresh, j_score_val = find_best_threshold(y_val, y_prob_val)
print(f">>> Threshold calibrated on refit (val) set: {best_thresh:.4f}")

# Evaluate on TEST set
auc        = roc_auc_score(y_test, y_prob_test)
ap_score   = average_precision_score(y_test, y_prob_test)
f1_default = f1_score(y_test, y_pred_default)
y_pred_opt = (y_prob_test >= best_thresh).astype(int)
f1_optimal = f1_score(y_test, y_pred_opt)
_, j_score = find_best_threshold(y_test, y_prob_test)

# Val set metrics for comparison
auc_val = roc_auc_score(y_val, y_prob_val)
ap_val  = average_precision_score(y_val, y_prob_val)

print(f"\n    ── Val set (refit 20%) ───────────────────")
print(f"    AUC-ROC:               {auc_val:.4f}")
print(f"    AUC-PR:                {ap_val:.4f}")
print(f"\n    ── Test set (test 20%) ───────────────────")
print(f"    AUC-ROC:               {auc:.4f}")
print(f"    AUC-PR:                {ap_score:.4f}")
print(f"    Youden's J threshold:  {best_thresh:.4f}  (from val set)")
print(f"    Youden's J score:      {j_score:.4f}")
print(f"    F1 @ threshold=0.5:    {f1_default:.4f}")
print(f"    F1 @ Youden's J:       {f1_optimal:.4f}")
report = classification_report(y_test, y_pred_opt,
                                target_names=["No CVD", "CVD"])
print(f"\n    ── Classification Report (threshold={best_thresh:.3f}) ──")
print(report)

# ─── 12. CROSS-VALIDATED AUC (within selection/train set only) ────────────────
print(">>> 5-fold cross-validated AUC on selection set...")

def run_cv_fold(X_tr, y_tr, X_va, y_va):
    sc   = StandardScaler()
    X_tr = np.nan_to_num(sc.fit_transform(X_tr), nan=0.0)
    X_va = np.nan_to_num(sc.transform(X_va),     nan=0.0)
    m    = MLP(X_tr.shape[1], HIDDEN_DIMS, DROPOUT).to(DEVICE)
    n_pos = int(y_tr.sum()); n_neg = len(y_tr) - n_pos
    pw    = torch.tensor([n_neg / max(n_pos, 1)], dtype=torch.float32).to(DEVICE)
    crit  = nn.BCEWithLogitsLoss(pos_weight=pw)
    opt   = torch.optim.Adam(m.parameters(), lr=LR)
    ldr   = make_loader(X_tr, y_tr, shuffle=True)
    m.train()
    for _ in range(30):
        for Xb, yb in ldr:
            opt.zero_grad()
            crit(m(Xb.to(DEVICE)), yb.to(DEVICE)).backward()
            opt.step()
    m.eval()
    Xv_t = torch.tensor(X_va, dtype=torch.float32).to(DEVICE)
    with torch.no_grad():
        p = torch.sigmoid(m(Xv_t)).cpu().numpy()
    return roc_auc_score(y_va, p)

skf     = StratifiedKFold(n_splits=CV_FOLDS, shuffle=True, random_state=SEED)
cv_aucs = []
for fold_i, (tr_idx, va_idx) in enumerate(skf.split(X_train_raw, y_train), 1):
    fold_auc = run_cv_fold(X_train_raw[tr_idx], y_train[tr_idx],
                           X_train_raw[va_idx], y_train[va_idx])
    cv_aucs.append(fold_auc)
    print(f"    Fold {fold_i}: AUC = {fold_auc:.4f}")

cv_aucs = np.array(cv_aucs)
print(f"    CV AUC: {cv_aucs.mean():.4f} ± {cv_aucs.std():.4f}\n")
END_TIME = datetime.datetime.now()

# ─── 13. FIGURES ──────────────────────────────────────────────────────────────
print(">>> Generating figures...")

# ── Training Curve ─────────────────────────────────────────────────────────────
fig_tc, ax_tc = plt.subplots(figsize=(9, 5))
epochs_ran = range(1, len(train_losses) + 1)
ax_tc.plot(epochs_ran, train_losses, label="Train loss (selection 60%)",
           color="steelblue", lw=2)
ax_tc.plot(epochs_ran, val_losses, label="Val loss (refit 20%)",
           color="darkorange", lw=2)
ax_tc.set(title="Training & Validation Loss", xlabel="Epoch", ylabel="BCE Loss")
ax_tc.legend()
fig_tc.tight_layout()
tc_path = os.path.join(RESULTS_DIR, "nn_training_curve.png")
fig_tc.savefig(tc_path, dpi=150); plt.close(fig_tc)

# ── ROC / PR / F1 (test set) ───────────────────────────────────────────────────
fig, axes = plt.subplots(1, 3, figsize=(18, 6))
fig.suptitle("Neural Network — CVD Prediction  (Test Set: 20%)",
             fontsize=13, fontweight="bold")

fpr, tpr, _ = roc_curve(y_test, y_prob_test)
axes[0].plot(fpr, tpr, color="steelblue", lw=2,
             label=f"NN test (AUC={auc:.3f})")
axes[0].plot([0, 1], [0, 1], "k--", lw=1, label="Random (AUC=0.5)")
axes[0].scatter(fpr[np.argmax(tpr - fpr)], tpr[np.argmax(tpr - fpr)],
                color="tomato", s=80, zorder=5,
                label=f"Youden's J (thr={best_thresh:.3f})")
axes[0].fill_between(fpr, tpr, alpha=0.1, color="steelblue")
axes[0].set(title="ROC Curve (Test Set)", xlabel="False Positive Rate",
            ylabel="True Positive Rate", xlim=[0, 1], ylim=[0, 1.02])
axes[0].legend(fontsize=8)
axes[0].text(0.6, 0.15,
             f"Test AUC = {auc:.4f}\nVal  AUC = {auc_val:.4f}\n"
             f"CV   AUC = {cv_aucs.mean():.4f} ± {cv_aucs.std():.4f}",
             transform=axes[0].transAxes, fontsize=9,
             bbox=dict(boxstyle="round", facecolor="lightyellow", alpha=0.8))

prec, rec, _ = precision_recall_curve(y_test, y_prob_test)
axes[1].plot(rec, prec, color="darkorange", lw=2,
             label=f"NN (AUC-PR={ap_score:.3f})")
axes[1].axhline(prevalence, color="grey", linestyle="--", lw=1,
                label=f"No-skill ({prevalence:.1%})")
axes[1].text(0.05, 0.95,
             f"F1 @ 0.5:      {f1_default:.4f}\nF1 @ Youden's: {f1_optimal:.4f}",
             transform=axes[1].transAxes, fontsize=9, verticalalignment="top",
             bbox=dict(boxstyle="round", facecolor="lightyellow", alpha=0.8))
axes[1].set(title="Precision-Recall Curve (Test Set)",
            xlabel="Recall", ylabel="Precision", xlim=[0, 1], ylim=[0, 1.02])
axes[1].legend(fontsize=8)

thresholds_range = np.linspace(0.01, 0.99, 200)
f1_scores_range  = [
    f1_score(y_test, (y_prob_test >= t).astype(int), zero_division=0)
    for t in thresholds_range
]
axes[2].plot(thresholds_range, f1_scores_range, color="seagreen", lw=2)
axes[2].axvline(best_thresh, color="tomato", linestyle="--", lw=1.5,
                label=f"Youden's J = {best_thresh:.3f} (from val)")
axes[2].axvline(0.5, color="grey", linestyle=":", lw=1, label="Default (0.5)")
axes[2].scatter([best_thresh], [f1_optimal], color="tomato", s=80, zorder=5,
                label=f"Best F1 = {f1_optimal:.3f}")
axes[2].set(title="F1 Score vs Threshold (Test Set)",
            xlabel="Threshold", ylabel="F1 Score", xlim=[0, 1], ylim=[0, 1])
axes[2].legend(fontsize=8)

plt.tight_layout()
fig_path = os.path.join(RESULTS_DIR, "nn_results.png")
fig.savefig(fig_path, dpi=150); plt.close(fig)

# ── Confusion Matrices ─────────────────────────────────────────────────────────
fig_cm, axes_cm = plt.subplots(1, 2, figsize=(12, 5))
fig_cm.suptitle("Confusion Matrices — Neural Network (Test Set)",
                fontsize=13, fontweight="bold")
for ax, (y_pred, title) in zip(axes_cm, [
    (y_pred_default, "Default threshold (0.5)"),
    (y_pred_opt,     f"Youden's J threshold ({best_thresh:.3f})"),
]):
    cm   = confusion_matrix(y_test, y_pred)
    disp = ConfusionMatrixDisplay(cm, display_labels=["No CVD", "CVD"])
    disp.plot(ax=ax, colorbar=False, cmap="Blues")
    tn, fp, fn, tp = cm.ravel()
    sens = tp / (tp + fn)
    spec = tn / (tn + fp)
    ax.set_title(
        f"{title}\nF1={f1_score(y_test, y_pred):.3f} | "
        f"Sens={sens:.3f} | Spec={spec:.3f}",
        fontsize=9
    )
fig_cm.tight_layout()
cm_path = os.path.join(RESULTS_DIR, "nn_confusion_matrices.png")
fig_cm.savefig(cm_path, dpi=150); plt.close(fig_cm)

# ── CV AUC bar chart (selection set only) ──────────────────────────────────────
fig_cv, ax_cv = plt.subplots(figsize=(7, 4))
bars = ax_cv.bar(range(1, CV_FOLDS + 1), cv_aucs,
                 color="steelblue", alpha=0.8, edgecolor="navy")
ax_cv.axhline(cv_aucs.mean(), color="tomato", linestyle="--", lw=2,
              label=f"Mean = {cv_aucs.mean():.4f}")
ax_cv.axhline(auc, color="seagreen", linestyle="-.", lw=2,
              label=f"Test AUC = {auc:.4f}")
ax_cv.axhline(0.5, color="grey", linestyle=":", lw=1, label="Random")
for bar, val in zip(bars, cv_aucs):
    ax_cv.text(bar.get_x() + bar.get_width() / 2, val + 0.002,
               f"{val:.4f}", ha="center", fontsize=9)
ax_cv.set(title=f"{CV_FOLDS}-Fold CV AUC (Selection set) vs Test AUC",
          xlabel="Fold", ylabel="AUC-ROC", ylim=[0.4, 1.0])
ax_cv.legend(fontsize=9)
fig_cv.tight_layout()
cv_path = os.path.join(RESULTS_DIR, "nn_cv_auc.png")
fig_cv.savefig(cv_path, dpi=150); plt.close(fig_cv)

print("    All figures saved.")

# ─── 14. SAVE METRICS ─────────────────────────────────────────────────────────
metrics_df = pd.DataFrame([{
    "Model":                  "MLP Neural Network",
    "Train set":              TRAIN_FILE,
    "Val set":                VAL_FILE,
    "Test set":               TEST_FILE,
    "Architecture":           str(HIDDEN_DIMS),
    "Dropout":                DROPOUT,
    "Batch size":             BATCH_SIZE,
    "Max epochs":             MAX_EPOCHS,
    "Early stop epoch":       len(train_losses),
    "Features":               X_train.shape[1],
    "Train rows":             len(y_train),
    "Val rows":               len(y_val),
    "Test rows":              len(y_test),
    "Val AUC-ROC":            round(float(auc_val), 4),
    "Val AUC-PR":             round(float(ap_val),  4),
    "Test AUC-ROC":           round(float(auc), 4),
    "Test AUC-PR":            round(float(ap_score), 4),
    "CV AUC mean":            round(float(cv_aucs.mean()), 4),
    "CV AUC std":             round(float(cv_aucs.std()), 4),
    "Threshold (from val)":   round(float(best_thresh), 4),
    "Youden's J (test)":      round(float(j_score), 4),
    "F1 test (thr=0.5)":      round(float(f1_default), 4),
    "F1 test (Youden's J)":   round(float(f1_optimal), 4),
}])
metrics_df.to_csv(os.path.join(RESULTS_DIR, "nn_metrics.csv"), index=False)
torch.save(best_state_dict, os.path.join(RESULTS_DIR, "nn_best_weights.pt"))

print(f"\n{'='*60}")
print(f"  FINAL RESULTS")
print(f"{'='*60}")
print(metrics_df.T.to_string(header=False))

# ─── 15. PDF REPORT ───────────────────────────────────────────────────────────
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
    pdf.savefig(fig); plt.close(fig)

def add_image_page(pdf, img_path, title):
    fig = plt.figure(figsize=(11, 8.5))
    img = plt.imread(img_path)
    ax  = fig.add_axes([0.05, 0.05, 0.90, 0.85])
    ax.imshow(img); ax.axis("off")
    ax.set_title(title, fontsize=13, fontweight="bold", pad=10)
    pdf.savefig(fig); plt.close(fig)

pdf_path = os.path.join(RESULTS_DIR, "report_neural_network.pdf")
with PdfPages(pdf_path) as pdf:

    # ── Cover ──────────────────────────────────────────────────────────────────
    fig_cov = plt.figure(figsize=(11, 8.5))
    fig_cov.patch.set_facecolor("#1a1a2e")
    ax_c = fig_cov.add_axes([0, 0, 1, 1])
    ax_c.axis("off")
    ax_c.text(0.5, 0.65, "Neural Network",
              color="white", fontsize=28, fontweight="bold",
              ha="center", va="center", transform=ax_c.transAxes)
    ax_c.text(0.5, 0.53,
              f"MLP  ·  Architecture: {HIDDEN_DIMS}  ·  Dropout: {DROPOUT}\n"
              f"Train: selection 60%  ·  Val: refit 20%  ·  Test: test 20%",
              color="#a0a0c0", fontsize=12,
              ha="center", va="center", transform=ax_c.transAxes)
    ax_c.text(0.5, 0.36,
              f"Test AUC = {auc:.4f}   |   F1 (Youden's) = {f1_optimal:.4f}\n"
              f"Val  AUC = {auc_val:.4f}   |   "
              f"CV AUC = {cv_aucs.mean():.4f} ± {cv_aucs.std():.4f}\n"
              f"Generated: {START_TIME.strftime('%Y-%m-%d %H:%M:%S')}",
              color="#808090", fontsize=11,
              ha="center", va="center", transform=ax_c.transAxes,
              family="monospace")
    pdf.savefig(fig_cov); plt.close(fig_cov)

    # ── 1. Summary ─────────────────────────────────────────────────────────────
    add_text_page(pdf, "1. Model Summary", [
        f"Model:                Multi-Layer Perceptron (MLP)",
        f"Hidden layers:        {HIDDEN_DIMS}",
        f"Dropout:              {DROPOUT}",
        f"Batch size:           {BATCH_SIZE}",
        f"Learning rate:        {LR}",
        f"Max epochs:           {MAX_EPOCHS}",
        f"Early stop patience:  {PATIENCE}",
        f"Stopped at epoch:     {len(train_losses)}",
        f"Device:               {DEVICE}",
        f"Trainable params:     {n_params:,}",
        f"Input features:       {X_train.shape[1]}",
        "",
        "── Data Splits ──────────────────────────────────────",
        f"  Train  (selection 60%): {len(y_train):>7,} rows  →  {TRAIN_FILE}",
        f"  Val    (refit    20%): {len(y_val):>7,} rows  →  {VAL_FILE}",
        f"  Test   (test     20%): {len(y_test):>7,} rows  →  {TEST_FILE}",
        f"  Class weight:          pos_weight = {n_controls/n_cases:.2f}",
        "",
        "── Metrics ──────────────────────────────────────────",
        f"  Val  AUC-ROC:          {auc_val:.4f}",
        f"  Val  AUC-PR:           {ap_val:.4f}",
        f"  Test AUC-ROC:          {auc:.4f}",
        f"  Test AUC-PR:           {ap_score:.4f}",
        f"  CV AUC ({CV_FOLDS}-fold, train): {cv_aucs.mean():.4f} ± {cv_aucs.std():.4f}",
        f"  CV folds:              {[round(a, 4) for a in cv_aucs]}",
        f"  Youden's J threshold:  {best_thresh:.4f}  (calibrated on val set)",
        f"  F1 @ threshold=0.5:    {f1_default:.4f}",
        f"  F1 @ Youden's J:       {f1_optimal:.4f}",
        "",
        "── Classification Report (Youden threshold, test set) ──",
        report,
    ])

    add_image_page(pdf, tc_path,  "2. Training & Validation Loss Curve")
    add_image_page(pdf, fig_path, "3. ROC Curve | Precision-Recall | F1 vs Threshold  (Test Set)")
    add_image_page(pdf, cm_path,  "4. Confusion Matrices (Test Set)")
    add_image_page(pdf, cv_path,  "5. Cross-Validated AUC (Selection Set) vs Test AUC")

    d = pdf.infodict()
    d["Title"]        = "Neural Network CVD Report"
    d["CreationDate"] = START_TIME

print(f"    Saved: {pdf_path}")
print(f"\n>>> All outputs in: {RESULTS_DIR}/")
print(f"  Duration: {str(END_TIME - START_TIME).split('.')[0]}")
print("\nFiles:")
for fname in sorted(os.listdir(RESULTS_DIR)):
    size = os.path.getsize(os.path.join(RESULTS_DIR, fname))
    print(f"    {fname:<45}  {size/1024:.1f} KB")

