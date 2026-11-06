# Run log

## production-48h: job 8854 (completed and numerically validated)

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

### Numerical validation (`src/analyze.jl`, job 8860): all checks passed

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

## smoke: jobs 8851 and 8852 (restart test)

Ran to 2.5 h with a checkpoint at 2 h, then resumed to 3.5 h (revision `798aab51728249e5197924f59b4476fc2594e1ab`).

- Resume removed exactly the output after iteration 179. Output times remain strictly increasing at 300 s spacing across the restart.
- Over 3.5 h: heat error 4e-15 K, momentum error 1e-10 m/s (checked with raw JLD2, because analysis job 8853 was cancelled).
- The restarted run was **not** compared bit for bit with an uninterrupted run.
- Production itself had no restart.

Job 8847 failed before stepping on a `JLD2Writer` keyword error, since fixed.
