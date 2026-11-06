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
