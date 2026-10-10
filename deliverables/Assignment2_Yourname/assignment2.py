"""Deep Learning - Assignment 2 (Fashion-MNIST CNN + Residual CNN), PyTorch.

Run:  python assignment2.py            (full run: 3 seeds x 2 models)
      python assignment2.py --epochs 2 --seeds 1   (quick smoke test)
Outputs (in ./results): history.json, plots (*.png), summary.json
"""
import argparse, json, os, time
import numpy as np
import torch, torch.nn as nn, torch.nn.functional as F
from torchvision.datasets import FashionMNIST
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt

CLASSES = ["T-shirt/top", "Trouser", "Pullover", "Dress", "Coat",
           "Sandal", "Shirt", "Sneaker", "Bag", "Ankle boot"]

# ----------------------------------------------------------------- data ----
def load_data(root="./data"):
    tr = FashionMNIST(root=root, train=True, download=True)
    te = FashionMNIST(root=root, train=False, download=True)
    # normalise to [0,1]; add channel dim -> (N,1,28,28). Integer labels are
    # kept (CrossEntropyLoss applies the one-hot encoding implicitly).
    xtr = (tr.data.to(torch.float32) / 255.0).unsqueeze(1)
    xte = (te.data.to(torch.float32) / 255.0).unsqueeze(1)
    print("Shape of training images:", tuple(xtr.shape), "labels:", tuple(tr.targets.shape))
    print("Shape of testing images:", tuple(xte.shape), "labels:", tuple(te.targets.shape))
    return xtr, tr.targets, xte, te.targets

# --------------------------------------------------------------- models ----
class ConvStage(nn.Module):
    """conv-BN-ReLU-conv-BN (+ optional skip) -> ReLU -> 2x2 max-pool."""
    def __init__(self, cin, cout, residual):
        super().__init__()
        self.residual = residual
        self.conv1 = nn.Conv2d(cin, cout, 3, padding=1, bias=False)
        self.bn1 = nn.BatchNorm2d(cout)
        self.conv2 = nn.Conv2d(cout, cout, 3, padding=1, bias=False)
        self.bn2 = nn.BatchNorm2d(cout)
        self.pad_ch = cout - cin          # channels to zero-pad on the shortcut

    def forward(self, x):
        out = F.relu(self.bn1(self.conv1(x)))
        out = self.bn2(self.conv2(out))
        if self.residual:
            # Parameter-free shortcut: the input has fewer channels than the
            # output, so zero-pad the channel dimension to match (as the
            # assignment suggests). Spatial size is preserved by padding=1.
            shortcut = F.pad(x, (0, 0, 0, 0, 0, self.pad_ch))
            out = out + shortcut
        return F.max_pool2d(F.relu(out), 2)

class FashionCNN(nn.Module):
    """3 conv stages (32/64/128 ch) + 2 FC layers. residual=False is Ex.1,
    residual=True is Ex.2 (only the forward pass differs; same parameters)."""
    def __init__(self, residual=False, num_classes=10):
        super().__init__()
        self.stage1 = ConvStage(1, 32, residual)     # 28x28 -> 14x14
        self.stage2 = ConvStage(32, 64, residual)    # 14x14 -> 7x7
        self.stage3 = ConvStage(64, 128, residual)   # 7x7  -> 3x3
        self.fc1 = nn.Linear(128 * 3 * 3, 256)
        self.drop = nn.Dropout(0.4)
        self.fc2 = nn.Linear(256, num_classes)

    def forward(self, x):
        x = self.stage3(self.stage2(self.stage1(x)))
        x = self.drop(F.relu(self.fc1(x.flatten(1))))
        return self.fc2(x)

# ------------------------------------------------------------- training ----
@torch.no_grad()
def evaluate(model, x, y, bs=1000):
    model.eval(); loss = 0.0; correct = 0; preds = []
    for i in range(0, len(x), bs):
        o = model(x[i:i+bs]); loss += F.cross_entropy(o, y[i:i+bs], reduction="sum").item()
        p = o.argmax(1); correct += (p == y[i:i+bs]).sum().item(); preds.append(p)
    return loss / len(x), correct / len(x), torch.cat(preds)

def grad_norms(model):
    """Mean |grad| of each stage's first conv (vanishing-gradient diagnostic)."""
    return [m.conv1.weight.grad.abs().mean().item()
            for m in (model.stage1, model.stage2, model.stage3)]

def train(residual, seed, xtr, ytr, xte, yte, epochs, bs=128, lr=1e-3):
    torch.manual_seed(seed); np.random.seed(seed)
    model = FashionCNN(residual)
    opt = torch.optim.Adam(model.parameters(), lr=lr)
    sched = torch.optim.lr_scheduler.CosineAnnealingLR(opt, epochs)
    hist = dict(train_loss=[], train_acc=[], test_loss=[], test_acc=[], grad=[], time=[])
    n = len(xtr)
    for ep in range(epochs):
        t0 = time.time(); model.train(); perm = torch.randperm(n)
        tl = tc = 0.0; g = np.zeros(3); nb = 0
        for i in range(0, n, bs):
            idx = perm[i:i+bs]; xb, yb = xtr[idx], ytr[idx]
            opt.zero_grad(); out = model(xb); loss = F.cross_entropy(out, yb)
            loss.backward(); g += grad_norms(model); nb += 1; opt.step()
            tl += loss.item() * len(idx); tc += (out.argmax(1) == yb).sum().item()
        sched.step()
        vl, va, _ = evaluate(model, xte, yte)
        hist["train_loss"].append(tl / n); hist["train_acc"].append(tc / n)
        hist["test_loss"].append(vl); hist["test_acc"].append(va)
        hist["grad"].append((g / nb).tolist()); hist["time"].append(time.time() - t0)
        print(f"[{'ResNet-CNN' if residual else 'Plain CNN '} seed {seed}] ep {ep+1:2d}/{epochs} "
              f"train loss {tl/n:.4f} acc {tc/n:.4f} | test loss {vl:.4f} acc {va:.4f} "
              f"({hist['time'][-1]:.0f}s)", flush=True)
    return model, hist

# ---------------------------------------------------------------- plots ----
def confusion(preds, y):
    cm = np.zeros((10, 10), int)
    for t, p in zip(y.numpy(), preds.numpy()): cm[t, p] += 1
    return cm

def plot_confusion(cm, title, path):
    fig, ax = plt.subplots(figsize=(7.5, 6.5)); ax.imshow(cm, cmap="Blues")
    ax.set_xticks(range(10)); ax.set_yticks(range(10))
    ax.set_xticklabels(CLASSES, rotation=60, ha="right"); ax.set_yticklabels(CLASSES)
    for i in range(10):
        for j in range(10):
            ax.text(j, i, cm[i, j], ha="center", va="center", fontsize=7,
                    color="white" if cm[i, j] > cm.max() / 2 else "black")
    ax.set_xlabel("Predicted"); ax.set_ylabel("True"); ax.set_title(title)
    fig.tight_layout(); fig.savefig(path, dpi=150); plt.close(fig)

def plot_curves(h, title, path):
    e = range(1, len(h["train_loss"]) + 1)
    fig, ax = plt.subplots(1, 2, figsize=(10, 3.8))
    ax[0].plot(e, h["train_loss"], label="train"); ax[0].plot(e, h["test_loss"], label="test")
    ax[0].set_title(title + " - loss"); ax[0].set_xlabel("epoch"); ax[0].legend(); ax[0].grid(alpha=.3)
    ax[1].plot(e, h["train_acc"], label="train"); ax[1].plot(e, h["test_acc"], label="test")
    ax[1].set_title(title + " - accuracy"); ax[1].set_xlabel("epoch"); ax[1].legend(); ax[1].grid(alpha=.3)
    fig.tight_layout(); fig.savefig(path, dpi=150); plt.close(fig)

def plot_compare(hp, hr, path):
    e = range(1, len(hp["test_acc"]) + 1)
    fig, ax = plt.subplots(1, 3, figsize=(14, 3.8))
    for k, (key, t) in enumerate([("train_loss", "Train loss"), ("test_loss", "Test loss"), ("test_acc", "Test accuracy")]):
        ax[k].plot(e, hp[key], label="Plain CNN (Ex.1)"); ax[k].plot(e, hr[key], label="Residual CNN (Ex.2)")
        ax[k].set_title(t); ax[k].set_xlabel("epoch"); ax[k].grid(alpha=.3); ax[k].legend()
    fig.tight_layout(); fig.savefig(path, dpi=150); plt.close(fig)

def plot_grads(hp, hr, path):
    fig, ax = plt.subplots(1, 3, figsize=(14, 3.6))
    gp, gr = np.array(hp["grad"]), np.array(hr["grad"])
    for s in range(3):
        ax[s].semilogy(gp[:, s], label="Plain"); ax[s].semilogy(gr[:, s], label="Residual")
        ax[s].set_title(f"Mean |grad|, stage {s+1} conv1"); ax[s].set_xlabel("epoch")
        ax[s].grid(alpha=.3, which="both"); ax[s].legend()
    fig.tight_layout(); fig.savefig(path, dpi=150); plt.close(fig)

def plot_samples(x, y, path):
    fig, ax = plt.subplots(2, 5, figsize=(9, 4))
    for k, a in enumerate(ax.ravel()):
        i = int((y == k).nonzero()[0]); a.imshow(x[i, 0], cmap="gray"); a.set_title(CLASSES[k], fontsize=9); a.axis("off")
    fig.tight_layout(); fig.savefig(path, dpi=150); plt.close(fig)

# ----------------------------------------------------------------- main ----
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--epochs", type=int, default=15); ap.add_argument("--seeds", type=int, default=3)
    ap.add_argument("--out", default="results"); a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True); torch.set_num_threads(os.cpu_count())
    xtr, ytr, xte, yte = load_data()
    plot_samples(xtr, ytr, f"{a.out}/samples.png")
    params = {r: sum(p.numel() for p in FashionCNN(r).parameters()) for r in (False, True)}
    print("Parameters:", params)
    runs = {"plain": [], "residual": []}; models = {}
    for seed in range(a.seeds):
        for res in (False, True):
            name = "residual" if res else "plain"
            m, h = train(res, seed, xtr, ytr, xte, yte, a.epochs)
            runs[name].append(h)
            if seed == 0: models[name] = m
    json.dump(runs, open(f"{a.out}/history.json", "w"))
    summary = {"params": {"plain": params[False], "residual": params[True]}, "epochs": a.epochs}
    for name in runs:
        fin = [h["test_acc"][-1] for h in runs[name]]; best = [max(h["test_acc"]) for h in runs[name]]
        fl = [h["test_loss"][-1] for h in runs[name]]; ta = [h["train_acc"][-1] for h in runs[name]]
        summary[name] = dict(final_test_acc_mean=float(np.mean(fin)), final_test_acc_std=float(np.std(fin)),
                             best_test_acc_mean=float(np.mean(best)), final_test_loss_mean=float(np.mean(fl)),
                             final_train_acc_mean=float(np.mean(ta)), final_test_acc_per_seed=fin,
                             sec_per_epoch=float(np.mean([np.mean(h["time"]) for h in runs[name]])))
        _, _, p = evaluate(models[name], xte, yte); cm = confusion(p, yte)
        pc = cm.diagonal() / cm.sum(1); summary[name]["per_class_acc_seed0"] = dict(zip(CLASSES, map(float, pc)))
        plot_confusion(cm, f"Confusion matrix - {name} (seed 0)", f"{a.out}/confusion_{name}.png")
        plot_curves(runs[name][0], "Plain CNN" if name == "plain" else "Residual CNN", f"{a.out}/curves_{name}.png")
    plot_compare(runs["plain"][0], runs["residual"][0], f"{a.out}/compare.png")
    plot_grads(runs["plain"][0], runs["residual"][0], f"{a.out}/gradients.png")
    json.dump(summary, open(f"{a.out}/summary.json", "w"), indent=2)
    print(json.dumps(summary, indent=2))

if __name__ == "__main__":
    main()
