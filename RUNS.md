# Run log

## production-48h: job 8854 (completed; budgets pass; interior mixing suspect)
> **WARNING: do not use this dataset as boundary-layer turbulence yet.** The run finished and passed its budget checks,
> but the figure and follow-up numbers show the stratified interior being stirred, which looks unphysical.
> The cause has not been diagnosed. See "Suspect interior mixing" below.


Coarse 10 m proof of concept; see the limits in `README.md`.

| | |
|---|---|
| Slurm job | 8854, COMPLETED, no requeues; validation job 8860, COMPLETED |
| Simulation revision | `798aab51728249e5197924f59b4476fc2594e1ab`, clean at launch |
| Validation revision | `a9c45da7823c9dffe2f8fe4b006be582569f49c2` (analysis and Slurm scripts changed; `simulation.jl` and `Manifest.toml` did not) |
| Hardware | NVIDIA H100 80GB HBM3, driver 550.90.12, node agcpv2dev-gpunodeset-0 |
| Software | Julia 1.12.6, Oceananigans 0.117.2, CUDA 6.4.2 |
| Data | `/shared/greg_aeolus_earth/AngularOceanScattering/runs/production-48h/` (790 MB, not in git); log `/shared/greg_aeolus_earth/AngularOceanScattering/runs/production-48h.log` |

### Timing

| Phase | Time | Note |
|---|---|---|
| Job total | 827 s (13:47) | |
| Everything outside `run!` | ~419 s | Dominated by waiting on a precompile lock (below); not a clean startup figure |
| `run!`, 48 simulated hours | 407.7 s | 2358 steps, 172.9 ms/step, includes output, checkpoints and first-step compilation |
| Step log, first to last logged row | 374.1 s | 2340 steps, 159.9 ms/step |

These rates include all output I/O to NFS. The cost of stepping alone was not measured separately.

**Setup, kept separate from integration:**

- Cold full-environment precompile: job 8847 took 24:30 on one CPU, including Makie, before failing on a script bug. It was never timed with 8 CPUs.
- Warm startup: jobs 8851 and 8852 took about 1:15 outside `run!` (2:10 total with 53.9 s in `run!`; 2:02 total with 44.8 s).
- 8854 was held up about 6 minutes: `strace` showed it retrying the CUDA precompile lockfile while the smoke analysis, 8853, was compiling the full environment in the same depot. 8853 was cancelled and its lockfiles removed. Analysis no longer precompiles the full environment.

### Numerical validation (`src/analyze.jl`, job 8860): all coded checks passed, but they do not detect the problem below

| Check | Result |
|---|---|
| Final time | 48.0000 h of 48 h; 577 budget records, time strictly increasing |
| Finite fields | 196 of 196 full-field snapshots finite |
| Heat budget | ΔT̄ = −1.32037e-2 K vs exact −1.32037e-2 K; max error over the series 4.3e-15 K |
| Mean momentum vs rotating slab | amplitude 3.0488e-3 m/s; max error over the series 1.4e-9 m/s (u), 1.3e-9 m/s (v) |
| Advective CFL | max 0.800, median 0.800 |
| Diffusive CFL | max 0.404, median 0.169 |
| Time step | median 81.6 s, range 5.5-150 s; 1% of logged rows at the largest Δt |
| Mixed-layer depth | 32.8 m to 45.4 m (0.02 K below top cell, interpolated) |
| Resolved TKE at 48 h | column mean 1.67e-5 m²/s²; top cell 7.09e-5 m²/s² |

**Limits of these checks:**

- CFL, Δt and the extrema come from `steps.csv`, sampled every 20 iterations (118 rows), so these are sampled maxima, not maxima over every step.
- The budgets test conservation and flux signs. They do not test turbulence quality, which at 3-5 cells per mixed layer depends on the closure and advection scheme.
- 0.02 K is about 4 m of the initial stratification, so the 32.8 m starting depth comes from that definition; the prescribed value is 30 m.
- The saved fields have not been assessed for acoustic use.

### Suspect interior mixing

Found from the figure (job 8861) and measured from the saved profiles and transects. The forcing should not stir water at 100 m:
with u* = 7e-3 m/s and N² = 1e-5 s⁻², the boundary layer is expected to stay within a few tens of metres.

| t (h) | N² at z = −100 to −140 m (s⁻²) | rms w at z ≈ −100 m (m/s) | rms w at z ≈ −20 m (m/s) |
|---|---|---|---|
| 0 | 1.00e-5 | 0 | 0 |
| 1 | 1.00e-5 | 4.5e-4 | 2.8e-3 |
| 2 | 9.85e-6 | 3.9e-3 | 2.6e-3 |
| 4 | 8.57e-6 | 4.6e-3 | 2.1e-3 |
| 12 | 6.12e-6 | 3.6e-3 | 1.8e-3 |
| 24 | 4.06e-6 | 2.9e-3 | 1.9e-3 |
| 48 | 2.34e-6 | 2.1e-3 | 2.6e-3 |

- Interior N² falls 77% in 48 h, and from about 2 h to 24 h w at −100 m exceeds w in the mixed layer.
- At 3 h the x-direction lag-1 autocorrelation of T′ and w is about 0.0-0.2 at z ≈ −125 m and z ≈ −25 m: grid-scale noise, not resolved eddies. By 48 h it rises to 0.5-0.9.
- So the 32.8 to 45.4 m mixed-layer deepening and the TKE values are not trustworthy as boundary-layer results. The saved heat and momentum budgets still close because they cannot detect interior mixing.

Not yet diagnosed. Untested candidates: the noise seed exciting grid-scale motion, time-stepping at CFL 0.8 with weak forcing (RK3 + WENO on a 10 m grid), and the closure. Bottom reflection and the lack of a sponge may let waves persist. A short sensitivity test on the H100 should separate these.

## smoke: jobs 8851 and 8852 (restart test)

Ran to 2.5 h with a checkpoint at 2 h, then resumed to 3.5 h (revision `798aab51728249e5197924f59b4476fc2594e1ab`).

- Resume removed exactly the output after iteration 179. Output times remain strictly increasing at 300 s spacing across the restart.
- Over 3.5 h: heat error 4e-15 K, momentum error 1e-10 m/s (checked with raw JLD2, because analysis job 8853 was cancelled).
- The restarted run was **not** compared bit for bit with an uninterrupted run.
- Production itself had no restart.

Job 8847 failed before stepping on a `JLD2Writer` keyword error, since fixed.

# 4 m / 2 m campaign

Δx = Δy = 4 m, Δz = 2 m, Lz = 160 m (Nz = 80); forcing, rotation, initial state and stratification unchanged.

## Diagnosis of the coarse interior mixing (job 8902)

| Case | Interior N² at end | Note |
|---|---|---|
| Coarse rest (10 m, no forcing or noise, 6 h) | 100% | exactly zero velocity |
| Coarse, CFL 0.2, Δt ≤ 10 s, 12 h | 59% | nearly identical to production (w correlation 1.000 at 6 h, 0.97 at 12 h): time step is not the cause there |
| Fine box, CFL 0.8, 12 h | 99.9% | ML 38.0 m, TKE 2.127e-5, w lag-1 0.85 at −100 m |
| Fine box, CFL 0.4, Δt ≤ 20 s, 12 h | 99.8% | ML 38.0 m, TKE 2.119e-5, w lag-1 0.85 |
| Fine box, CFL 0.2, Δt ≤ 5 s, 12 h | 99.8% | ML 38.0 m, TKE 2.104e-5, w lag-1 0.84 |
| Fine rest, 6 h | 100% | exactly zero velocity |

Fine box: 256 × 256 × 80, 1024 × 1024 × 160 m, AMD, WENO 5. In the coarse case AMD κₑ reaches about 0.03 m²/s at −120 m and its
flux (about 1e-4 K m/s) far exceeds the resolved flux, so the closure carries the interior mixing there. Why the coarse grid
excites it has not been established; closure comparisons (job 8917) are held and noncritical.
Fine-box rms w at −100 m is still about 2e-3 m/s; whether that is physical has not been determined.

Production uses CFL 0.4, `max_dt` 20 s, chosen as a margin: the 12 h box shows no Δt sensitivity between CFL 0.2 and 0.8.

## Capacity probes (real output and one checkpoint, H100 card total 81559 MiB, limit 85% = 69325 MiB)

| Grid | Cells | Lx × Ly (km) | nvidia-smi peak | Live / reserved | Host RSS | Checkpoint | Full save |
|---|---|---|---|---|---|---|---|
| 1024×256×80 | 21.0M | 4.10 × 1.02 | 4626 MiB (5%) | 3.40 / 3.88 GiB | 4.7 GiB | 2.5 GB | |
| 2048×256×80 | 41.9M | 8.19 × 1.02 | 8274 MiB (10%) | 6.78 / 7.44 GiB | 6.9 GiB | 4.9 GB | |
| **5120×900×80** | **368.6M** | **20.48 × 3.60** | **66450 MiB (81%)** | 58.70 / 64.25 GiB | 50.5 GiB | 42 GB | 3.6 GB (each, compressed, early laminar state) |
| 5120×960×80 | 393.2M | 20.48 × 3.84 | not run: predicted 70826 MiB, over limit | | | | |

Selected: 5120×900×80, the largest tested grid within the limit. Probes ran 30 steps, so these peaks do not cover a long run or a checkpoint from developed turbulence.

Stepping between saves: 0.79 s/step at 368.6M cells. A checkpoint plus full save took about 200 s.

### Storage budget, 48 h (uncompressed worst case), on /home (about 300 GB free)

| Item | Total |
|---|---|
| Full fields, 6-hourly, 9 × 5.9 GB | 53 GB |
| xy planes at 4 m and 40 m, u, w, T, 10 min | 32 GB |
| xz and yz sections, 5 min | 4.5 GB |
| Two checkpoints during cleanup, 2 × 66 GB | 132 GB |
| Peak | about 222 GB |

### Estimated time

About 16 500 steps (if the box's median Δt of 10.5 s holds) × 0.79 s = 3.6 h, 16 checkpoints × about 190 s = 0.85 h, plus other output: about 5 h. Limit 12 h.

## Production result (job 8939): completed, failed the interior-stratification check

Run `production-4m2m`, git a0cc433, 5120×900×80, 20.48 × 3.60 × 0.16 km, CFL 0.4, `max_dt` 20 s, no restarts.

**Validation job 8940 failed.** Interior N² (z = −100 to −140 m) fell to 87.3% of initial; the check requires at least 90%. The
threshold has not been changed. Treat the interior below the mixed layer as not validated, especially late in the run.

| Time | Interior N², % of initial | rms w at −100 m |
|---|---|---|
| 6 h | 100.4 | 1.44e-3 m/s |
| 12 h | 99.8 | 2.14e-3 m/s |
| 24 h | 95.7 | 1.71e-3 m/s |
| 48 h | 87.3 | 1.63e-3 m/s |

The 12 h value matches the fine box, whose 12 h length could not show this later decline. The cause is not established:
closure comparisons (job 8917) have not run on this grid, and resolved and subgrid contributions have not been separated.

All other checks passed:

- Final time 48.000 h; 577 budget records; 36 saved full-field arrays, 0 non-finite.
- Heat: ΔT = −1.32037e-2 K, max error 2.84e-14 K against exact.
- Momentum: inertial amplitude 3.0488e-3 m/s, max error 2.72e-12 (u), 2.50e-12 (v) m/s.
- Advective CFL at most 0.400; diffusive CFL at most 0.247; median Δt 10.0 s.
- Mixed layer 33.9 → 47.1 m; column-mean resolved TKE at end 2.518e-5 m²/s².
- x lag-1 correlation of w at 48 h: 0.949 at −20 m, 0.775 at −100 m.

Cost: 16 970 steps, 16 267 s (4.52 h) wall including I/O, 958.6 ms/step mean. Slurm elapsed 4:32:33.
GPU: 66450 MiB by nvidia-smi early in the run (not sampled continuously); CUDA 64.92 of 79.10 GiB at the end. Peak host RSS
45.9 GiB. Disk: 98 GB, including one 44.8 GB checkpoint. Horizontal movies and final-time figures are available; see the animation section below.

### Where the interior N² loss occurs (`src/n2_depth.jl`, from `profiles.jld2`)

| Layer (m) | 12 h | 24 h | 36 h | 48 h (% of initial N²) |
|---|---|---|---|---|
| −50 to −60 | 96.1 | 91.7 | 87.5 | 82.3 |
| −70 to −80 | 99.4 | 98.3 | 96.8 | 94.7 |
| −90 to −100 | 100.1 | 99.7 | 98.9 | 97.2 |
| −110 to −120 | 100.4 | 99.3 | 96.8 | 93.4 |
| −130 to −140 | 99.0 | 90.2 | 82.9 | 77.3 |
| −150 to −160 | 56.6 | 42.8 | 36.4 | 32.9 |

The failed bulk metric (−100 to −140 m) is dominated by loss growing upward from the bottom. Mid-column N² stays at 97%.
Averaged over the last 6 h, mean κₑ is about 2e-3 m²/s from −140 to −60 m. The diffusive heat flux estimated from mean κₑ and
mean ∂T/∂z (about −1.1e-5 K m/s at −100 m, ignoring κ′∂T′/∂z covariance) is about 10 times the resolved ⟨wT⟩ (about 9e-7).
√(κₑ t) over 48 h is about 19 m, and the deep warming (+0.023 K at −138 m) has the sign expected for downward flux converging at
the no-flux bottom. This points to AMD subgrid diffusion acting below the mixed layer, but no closure comparison has confirmed it.

## Horizontal-slice animation of production-4m2m

Renderer `src/animate_xy.jl` (CairoMakie), run CPU-only by `slurm/animate_xy.sbatch` (job 9474, git aba0384). It streams one frame
at a time from `xy_upper.jld2` and `xy_lower.jld2`. Output is in `/shared/greg_aeolus_earth/AngularOceanScattering/animations/production-4m2m-xy/v2`:

- `xy-detail.mp4`: optional close-up. Four 1.536 km squares (384 × 384 cells) at native 4 m. H.264 High, 1920×1080, 289 frames at 24 fps (12.0 s).
- `xy-overview.mp4`: primary movie showing the full 20.48 × 3.60 km domain, shown as 4 × 4-cell (16 m) block averages. H.264 High, 1920×1700, 289 frames, 24 fps.
- `xy-detail-final.png`, `xy-overview-final.png`: the 48 h frame. `animation-info.txt` records the settings.
- Final-time PNGs at native resolution for the overview too: `/shared/greg_aeolus_earth/AngularOceanScattering/animations/production-4m2m-xy/xy-*-final.png` (from the cancelled first render, 9435).

Slice depths, from the saved indices: w at faces z = −6 m (k = 78) and −42 m (k = 60); T at centres z = −5 m and −41 m.
Shown: q′ = q − instantaneous mean over the full slice. Fixed colour limits, the 99.5th percentile of |q′| over 25 evenly spaced
frames (0.5% of those samples saturate): w′ ±12.78 / ±6.642 mm/s and T′ ±8.488 / ±15.44 mK (upper / lower). No temporal interpolation anywhere. The detail movie has no spatial smoothing or interpolation. The overview's 4 × 4 block
averaging is intentional, for display only. Every frame carries
the failed interior-stratification check as a caveat.
