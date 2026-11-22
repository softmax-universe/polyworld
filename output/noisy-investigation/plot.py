from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np

directory = Path(__file__).resolve().parent
samples = np.genfromtxt(directory / "samples.csv", delimiter=",", names=True)
slice_data = np.genfromtxt(directory / "slice.csv", delimiter=",", names=True)
size = int(np.sqrt(len(samples)))
seam_x = -0.25 * ((np.sqrt(3) - 1) / 2) / (1 + (np.sqrt(3) - 1) / 2)

plt.rcParams.update({"font.family": "DejaVu Sans", "font.size": 11})
fig, axes = plt.subplots(1, 3, figsize=(15, 5.8), gridspec_kw={"wspace": 0.3})
fig.patch.set_facecolor("#f6f7f9")
fig.suptitle("A broken permutation table creates seams near the origin", x=0.07,
             y=0.96, ha="left", fontsize=20, fontweight="bold", color="#162235")
fig.text(0.07, 0.89, "Actual library samples: seed 1988  |  frequency 1  |  one octave",
         color="#4b5563", fontsize=11)

for ax, column, title in zip(
    axes[:2], ["original", "corrected"],
    ["Current initialization", "Shuffle 256 entries, then duplicate"],
):
    ax.imshow(samples[column].reshape(size, size), origin="lower",
              extent=(-1.5, 1.5, -1.5, 1.5), cmap="gray", vmin=-1, vmax=1,
              interpolation="nearest")
    ax.scatter([0], [0], marker="+", s=70, color="#49e5ff", linewidth=1.5)
    ax.scatter([seam_x], [0.25], facecolors="none", edgecolors="#ffcb49",
               s=110, linewidth=1.7)
    ax.set(xlabel="x", ylabel="y", xticks=[-1, 0, 1], yticks=[-1, 0, 1])
    ax.set_title(title, loc="left", fontsize=12, fontweight="bold", pad=12)
    ax.spines[:].set_visible(False)

ax = axes[2]
offset = slice_data["x"] - seam_x
ax.plot(offset, slice_data["original"], color="#cb3748", linewidth=2.5,
        label="Current table")
ax.plot(offset, slice_data["corrected"], color="#007d80", linewidth=2.5,
        label="Corrected initialization")
ax.axvline(0, color="#8b93a0", linewidth=1, linestyle="--", zorder=0)
ax.set_title("Crossing the highlighted seam", loc="left", fontsize=12,
             fontweight="bold", pad=12)
ax.set(xlabel="x offset from seam (y = 0.25)", ylabel="noise value",
       xlim=(-0.01, 0.01), ylim=(-0.4, 0.7))
ax.set_xticks([-0.01, 0, 0.01], ["−0.01", "0", "+0.01"])
ax.grid(axis="y", color="#e3e6eb")
ax.spines[["top", "right"]].set_visible(False)
ax.legend(loc="lower right", frameon=False, fontsize=10)
ax.annotate("Jump ≈ 0.428", xy=(0, 0.37), xytext=(0.002, 0.34),
            color="#ad2939", fontsize=11,
            arrowprops={"arrowstyle": "->", "color": "#ad2939"})
ax.set_box_aspect(1)

fig.subplots_adjust(left=0.07, right=0.97, bottom=0.22, top=0.79)
fig.text(0.07, 0.12, "+ marks (0, 0); gold circles mark (−0.06698729, 0.25). Both maps use the same grayscale range [−1, 1].",
         color="#4b5563", fontsize=10)
fig.text(0.07, 0.07, "Across a 0.000002-unit step: current jump 0.428054; corrected change 0.0000051. Library source unchanged.",
         color="#162235", fontsize=11)
fig.savefig(directory / "noisy-origin-seam.png", dpi=160, facecolor=fig.get_facecolor())
print(directory / "noisy-origin-seam.png")
