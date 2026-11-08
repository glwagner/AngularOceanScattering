# AngularOceanScattering

Oceananigans large-eddy simulation of a surface-forced ocean boundary layer, built to supply resolved
velocity and temperature fields along ~10 km paths for acoustic Monte Carlo experiments on angular scattering
by vortices and sound-speed heterogeneity (context: Colosi & Duda 2026, JASA, DOI 10.1121/10.0046444).

**This repo produces the dataset only: there is no acoustic solver here.**

## Scope and limits: read this first

This is a coarse **proof of concept** at 10 m spacing in all directions.

- The initial 30 m mixed layer spans **only 3 grid cells**. The surface layer, shear and entrainment are barely
  resolved and depend on the closure and advection scheme. The vertical grid has deliberately not been refined.
- It does **not** resolve the metre and sub-metre microstructure discussed in the paper, and it **cannot reproduce
  absolute scattering amplitudes**. The velocity and sound-speed spectra are truncated near 2-6Δ (20-60 m) by the grid
  and numerical dissipation.
- With Ly = 640 m and Lz = 160 m, the domain is narrow and shallow compared with Lx. It contains no submesoscale
  dynamics, and x is periodic: a 10 km path fits inside the 10.24 km domain and does not repeat eddies. Repetition begins only for paths longer than Lx.
- A rigid lid is used, so there are no surface waves and no Langmuir turbulence.
- There is no sponge layer: internal waves reflect from the free-slip, insulating bottom at 160 m.

Estimated forcing scales: u* = 7.0e-3 m/s and w* = (B₀h)^(1/3) = 9.0e-3 m/s at h = 30 m, so an eddy turnover
h/w* takes about 1 h and shear and convection are comparable. These are scale estimates, not results.

## Specification

| Quantity | Value |
|---|---|
| Model | `NonhydrostaticModel`, 3D, Boussinesq; RK3 |
| Domain | Lx × Ly × Lz = 10240 × 640 × 160 m |
| Grid | 1024 × 64 × 16, uniform Δ = 10 m (1.05M cells) |
| Topology | periodic x, periodic y, bounded z (w = 0 at the lid and bottom) |
| Coriolis | f-plane, f = 1e-4 s⁻¹ |
| Equation of state | linear, α = 2e-4 K⁻¹, g = 9.81 m/s²; no salinity dynamics |
| Initial T | 15 °C for z > −30 m; below it, dT/dz = N²/(αg) = 5.10e-3 K/m (N² = 1e-5 s⁻²) |
| Initial velocity | zero |
| Seed | Gaussian T noise, σ = 1e-3 K, top 30 m, fixed RNG seed |
| Surface | stress τx = 0.05 N/m² toward +x; heat loss 50 W/m²; ρ₀ = 1025 kg/m³, cp = 3990 J/kg/K |
| Bottom | free slip, insulating |
| Closure and advection | `AnisotropicMinimumDissipation`, WENO order 5 |
| Time step | `TimeStepWizard`, advective CFL 0.8, diffusive CFL 0.5, `max_Δt` = 150 s |
| Duration | 48 simulated hours |

### Flux signs

Oceananigans boundary fluxes are positive upward:

- Momentum: Jᵘ = −τx/ρ₀ = −4.878e-5 m²/s² (downward flux of +x momentum, which accelerates the ocean toward +x).
- Heat: Jᵀ = +Q/(ρ₀cp) = +1.2226e-5 K m/s (upward flux, which cools the ocean).

### Time step cap

`max_Δt` = 150 s keeps NΔt ≈ 0.47. The velocities are weak (order 0.01-0.05 m/s), so the 10 m advective limit can exceed
this, and the cap may hold CFL below 0.8. `steps.csv` records whether it binds, and the run report states the outcome.

## Output

Written as Float32 (`budget.jld2` as Float64) to `/shared/greg_aeolus_earth/AngularOceanScattering/runs/<RUN>/`.
Simulation data is not kept in git.

| File | Cadence | Contents | Estimated size for 48 h |
|---|---|---|---|
| `fields.jld2` | 60 min | u, v, w, T, 3D | ~0.8 GB |
| `xz_transect.jld2` | 5 min | u, v, w, T at y index 1 | ~0.15 GB |
| `profiles.jld2` | 5 min | horizontal means of U, V, W, T, second moments, νₑ, κₑ | ~10 MB |
| `budget.jld2` | 5 min | volume-mean T, u, v, KE | ~1 MB |
| `checkpoint_iteration*.jld2` | 60 min, newest only | restart state | ~0.1-0.3 GB |
| `steps.csv`, `config.toml`, `provenance.txt`, `run_summary.txt` | | step log, resolved config, git revision and hardware, timing | small |

Sizes are arithmetic estimates from the grid. Budget about 2 GB.
Resolved TKE is computed in `src/analyze.jl` as ½(⟨u²⟩−U² + ⟨v²⟩−V² + ⟨w²⟩).

## Running

Julia environment: `Project.toml` and `Manifest.toml`. The job instantiates it on the GPU node because precompile
caches are CPU-specific. Commit first: the job refuses to start with uncommitted changes, so that the recorded
revision describes the code that ran.

```bash
# Production: gpuprod holds the H100s
sbatch --time=H:MM:SS --output=/shared/greg_aeolus_earth/AngularOceanScattering/runs/NAME.log slurm/run.sbatch NAME

# Any parameter can be overridden
sbatch --time=0:30:00 --output=LOG slurm/run.sbatch pilot stop_hours=2

# Validate against the run's config.toml; loads neither CUDA nor Oceananigans
sbatch --time=0:30:00 --output=LOG slurm/analyze.sbatch NAME            # numbers only
sbatch --time=0:40:00 --output=LOG slurm/analyze.sbatch NAME --figure   # plus figure
```

**Restart.** Rerunning with the same `RUN_NAME` resumes from the newest checkpoint, and requeue after preemption does
this automatically. Output saved after that checkpoint is removed first so it is not written twice. A resume with
different physical parameters is refused; only `stop_hours` may change.

## Validation (`src/analyze.jl`)

The domain has flux-only boundaries, so domain means have exact solutions. These are tested over the whole series:

- Heat: ΔT̄(t) = −Jᵀ t / Lz
- Momentum, a rotating forced slab: U(t) = A sin(ft), V(t) = A (cos(ft) − 1), with A = τx/(ρ₀ Lz f) = 3.05e-3 m/s

The script also checks final time, finite fields and maximum advective CFL, and reports mixed-layer depth and resolved TKE.

## Results

See `RUNS.md` for job IDs, measured throughput and validation of each run.
