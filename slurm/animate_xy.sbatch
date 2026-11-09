#!/bin/bash
#SBATCH --job-name=aos-anim-xy
#SBATCH --cpus-per-task=4
#SBATCH --mem=48G
#SBATCH --time=06:00:00
#SBATCH --open-mode=append
# CPU-only render of horizontal-slice movies (no GPU requested). Usage: sbatch --output=LOG slurm/animate_xy.sbatch RUN_DIR OUT_DIR [MAX_FRAMES]
set -euo pipefail
REPO=${AOS_REPO:-$HOME/AngularOceanScattering}
SCRATCH=${AOS_SCRATCH:-$HOME/AngularOceanScattering-data}
unset LD_LIBRARY_PATH
# Same depot stack as the simulation jobs: shared depot plus the bundled stdlib depot.
export JULIA_DEPOT_PATH=$SCRATCH/depot:$(dirname "$(julia --startup-file=no -e 'print(Sys.BINDIR)')")/share/julia
echo "=== $(date -u +%FT%TZ) job=${SLURM_JOB_ID:-} node=$(hostname) git=$(git -C "$REPO" rev-parse HEAD) dirty=$(git -C "$REPO" status --porcelain | wc -l)"
# --compiled-modules=existing: load valid caches and never start cache compilation (another process keeps rewriting
# the bundled stdlib LibCURL_jll cache, which made every run recompile Pkg and dependents).
julia --startup-file=no --compiled-modules=existing --project="$REPO" "$REPO/src/animate_xy.jl" "$@"
