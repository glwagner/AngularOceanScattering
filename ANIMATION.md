# Animation of the original 48-hour run

The Julia renderer in `src/animate.jl` visualizes the existing `production-48h` dataset. It does not rerun the model. The original run has suspect interior mixing; see `RUNS.md`. Conservation checks alone do not establish physical validity.

Run with the repository's Julia environment:

```sh
julia --project=. src/animate.jl RUN_DIR OUTPUT_DIR
```

The MP4 uses 289 frames at 24 fps, spanning 0–48 hours at ten-minute intervals. The PNG is the final 48-hour frame. Each has four panels: temperature anomaly and vertical velocity over the full 10.24 km transect, and a 1.28 km detail window from x = 4.48 to 5.76 km.

Temperature anomaly is relative to the along-transect mean at each depth and time. Vertical velocity is interpolated from vertical faces to centers and displayed in mm/s. Each field uses fixed symmetric color limits equal to the 99.5th percentile of absolute values over displayed frames. Larger values saturate. Cell values are shown without graphical smoothing. The dashed line marks the prescribed initial 30 m mixed-layer depth; it is not the evolving mixed-layer depth. The vertical scale is exaggerated.

Files are written to `/shared/greg_aeolus_earth/AngularOceanScattering/runs/production-48h/animation/` on gcp-slurm. Large media are kept outside git. The renderer also writes `animation-info.txt` with the numerical color limits and source path.
