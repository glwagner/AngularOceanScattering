# Horizontal-slice animation of the 4 m × 2 m run

The main movie is **`xy-overview.mp4`**, covering the full 20.48 × 3.60 km domain. Download it from the [release](https://github.com/glwagner/AngularOceanScattering/releases/tag/preview-4m2m-48h). It contains 289 frames at 24 fps, spanning 0–48 hours. `xy-overview-final.png` is the final frame.

Four panels show vertical velocity anomalies at z = −6 and −42 m (faces), and temperature anomalies at z = −5 and −41 m (centres). Each anomaly is relative to the instantaneous full-plane mean. The overview uses 4 × 4-cell block averages (16 m display spacing), with fixed colour limits from the 99.5th percentile of absolute anomalies across 25 sampled times. This averaging affects display only. There is no temporal interpolation. Black rectangles mark the optional close-up region.

`xy-detail.mp4` is an optional 1.536 km square close-up at native 4 m spacing. The full-domain movie is the primary presentation.

Render from the saved horizontal slices with Julia/CairoMakie:

```bash
sbatch --output=animate-xy.log slurm/animate_xy.sbatch RUN_DIR OUTPUT_DIR
```

The renderer is `src/animate_xy.jl`; the batch script uses existing compilation caches to avoid the shared-depot recompilation issue encountered during rendering. See [RUNS.md](RUNS.md) for validation caveats and exact output settings.

---

# Animation of the original 48-hour run

The Julia renderer in `src/animate.jl` visualizes the existing `production-48h` dataset. It does not rerun the model. The original run has suspect interior mixing; see `RUNS.md`. Conservation checks alone do not establish physical validity.

Run with the repository's Julia environment:

```sh
julia --project=. src/animate.jl RUN_DIR OUTPUT_DIR
```

The MP4 uses 289 frames at 24 fps, spanning 0–48 hours at ten-minute intervals. The PNG is the final 48-hour frame. Each has four panels: temperature anomaly and vertical velocity over the full 10.24 km transect, and a 1.28 km detail window from x = 4.48 to 5.76 km.

Temperature anomaly is relative to the along-transect mean at each depth and time. Vertical velocity is interpolated from vertical faces to centers and displayed in mm/s. Each field uses fixed symmetric color limits equal to the 99.5th percentile of absolute values over displayed frames. Larger values saturate. Cell values are shown without graphical smoothing. The dashed line marks the prescribed initial 30 m mixed-layer depth; it is not the evolving mixed-layer depth. The vertical scale is exaggerated.

Files are written to `$HOME/AngularOceanScattering-data/runs/production-48h/animation/`. Large media are kept outside git. The renderer also writes `animation-info.txt` with the numerical color limits and source path.
