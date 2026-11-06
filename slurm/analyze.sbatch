#!/bin/bash
#SBATCH --job-name=aos-analyze
#SBATCH --partition=gpuprod
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=8
#SBATCH --open-mode=append
# Usage: sbatch --time=0:30:00 --output=LOG slurm/analyze.sbatch RUN_NAME  [--figure]
set -euo pipefail
REPO=${AOS_REPO:-$HOME/AngularOceanScattering}
SCRATCH=${AOS_SCRATCH:-/shared/greg_aeolus_earth/AngularOceanScattering}
unset LD_LIBRARY_PATH
export JULIA_DEPOT_PATH=$SCRATCH/depot:$(dirname "$(julia --startup-file=no -e 'print(Sys.BINDIR)')")/share/julia
export JULIA_NUM_PRECOMPILE_TASKS=${SLURM_CPUS_PER_TASK:-1}
julia --startup-file=no --project="$REPO" -e 'using Pkg; Pkg.instantiate(allow_autoprecomp=false)'
exec julia --startup-file=no --project="$REPO" "$REPO/src/analyze.jl" "${AOS_RUNS:-$SCRATCH/runs}/$1" "${@:2}"
