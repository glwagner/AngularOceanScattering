# AngularOceanScattering

Three-dimensional Oceananigans large-eddy simulations of a surface-forced ocean boundary layer, providing velocity and temperature fields for acoustic angular-scattering experiments. This repository generates flow data; it does not contain an acoustic solver.

## Current run: 4 m horizontal × 2 m vertical

`production-4m2m` completed **48 simulated hours** on one H100 in **4 h 32 min**. The domain is **20.48 km × 3.60 km × 160 m**, with **5120 × 900 × 80 cells** (368.64 million). Both horizontal directions are periodic; the vertical direction is bounded.

[**Watch/download the full-domain animation**](https://github.com/glwagner/AngularOceanScattering/releases/download/preview-4m2m-48h/xy-overview.mp4) · [Final full-domain frame](https://github.com/glwagner/AngularOceanScattering/releases/download/preview-4m2m-48h/xy-overview-final.png) · [Movies and diagnostics](https://github.com/glwagner/AngularOceanScattering/releases/tag/preview-4m2m-48h)

![Full-domain horizontal slices at 48 hours](https://github.com/glwagner/AngularOceanScattering/releases/download/preview-4m2m-48h/xy-overview-final.png)

The movie shows horizontal slices of vertical velocity and temperature anomalies near the surface and around 40 m depth over the entire domain. See [ANIMATION.md](ANIMATION.md) for depths, display averaging, and rendering commands. Release assets require repository access while this repository is private.

### Physical setup

| Quantity | Value |
|---|---|
| Model | 3D Boussinesq `NonhydrostaticModel`, RK3 |
| Grid | Uniform Δx = Δy = 4 m, Δz = 2 m |
| Forcing | Wind stress 0.05 N/m² toward +x; surface heat loss 50 W/m² |
| Rotation | f = 10⁻⁴ s⁻¹ |
| Initial stratification | 30 m mixed layer at 15 °C; N² = 10⁻⁵ s⁻² below |
| Initial perturbation | 10⁻³ K Gaussian temperature noise in top 30 m, seed 20261106 |
| Equation of state | Linear, α = 2 × 10⁻⁴ K⁻¹; no salinity dynamics |
| Closure / advection | Anisotropic Minimum Dissipation / WENO5 |
| Boundaries | Rigid lid; impermeable, free-slip, insulating bottom; no sponge |
| Time stepping | Advective CFL 0.4, diffusive CFL 0.5, Δt ≤ 20 s |
| Precision | Float64 simulation, Float32 field output |

### Validation and limitations

Heat and momentum budgets, CFL, final time, and finite-field checks passed. **The interior-stratification screening check failed:** mean N² between 100 and 140 m depth reached 87.3% of its initial value, below the 90% threshold. Loss is concentrated near the bottom and just below the mixed layer. [RUNS.md](RUNS.md) records the measurements and depth dependence.

There is no bottom wave absorber. Internal-wave reflection with associated numerical or subgrid mixing is a plausible explanation, not an established mechanism. A deeper domain with a bottom sponge is a proposed follow-up, not part of this completed run. Conservation alone does not validate the deep flow.

This is LES, not DNS: metre and sub-metre microstructure is unresolved, and acoustic applications must check the relevant resolved spatial scales. The rigid lid excludes surface waves and Langmuir forcing. The original 10 m proof of concept is documented separately in [docs/coarse-10m.md](docs/coarse-10m.md).

## Reproducing the fine run

Use the pinned Julia environment (`Project.toml`, `Manifest.toml`). The executable retains the original coarse defaults, so **pass the fine-run overrides explicitly**:

```bash
sbatch --time=12:00:00 --output=production-4m2m.log slurm/run.sbatch production-4m2m \
  Nx=5120 Ny=900 Nz=80 Lx=20480 Ly=3600 Lz=160 \
  cfl=0.4 max_dt=20 stop_hours=48 \
  full_field_minutes=360 checkpoint_minutes=180
```

The Slurm launcher is configured for `gcp-slurm` and its `gpuprod` partition; adapt paths and resource directives on other clusters. Commit changes first: the launcher rejects a dirty checkout. Reusing a run name resumes its latest checkpoint; use a fresh name for a new experiment. The production simulation used commit `a0cc4334fa2c12934e65afacf585c014be682c08`.

The largest tested configuration within the chosen GPU memory margin used 66,450 MiB early in the run; this is not a continuously sampled peak. See [RUNS.md](RUNS.md) for capacity probes and runtime details.

## Data and snapshot export

Data stays outside git. Full 3D fields were saved every 6 hours (9 snapshots), horizontal slices every 10 minutes (289 frames), and profiles and vertical sections every 5 minutes. The full run directory is about 104 GB including its restart checkpoint. Movies and small diagnostics are on the release page; bulk simulation output is not a release asset.

A self-contained **48-hour snapshot is 5,916,787,716 bytes (5.92 GB)**. It contains Float32 `u`, `v`, `w`, and `T`, original staggering, coordinate arrays, units, configuration, provenance, and validation caveats. It can be read with JLD2 alone, without Oceananigans types:

```julia
using JLD2
jldopen("snapshot-48h.jld2") do f
    T = f["fields/T/data"]       # index order x, y, z
    z = f["grid/z_center"]
end
```

`u`, `v`, and `T` have size 5120 × 900 × 80; `w` has 81 vertical faces. Export with:

```bash
julia --project=. src/export_snapshot.jl RUN_DIR snapshot-48h.jld2 172800
```

The exporter refuses overwrite and verifies every exported field against the source. Snapshot SHA-256: `df7dc030b6a5efd85f6095dde6c5602787e843f73a710046ab483ce5ec806d1f`.

Dropbox delivery is being prepared; no verified shared download link is available here yet.

## Scientific context

Colosi & Duda (2026), *Acoustic angular scattering by macro- and micro-scale turbulent vortices and sound speed heterogeneities*, JASA, DOI [10.1121/10.0046444](https://doi.org/10.1121/10.0046444).
