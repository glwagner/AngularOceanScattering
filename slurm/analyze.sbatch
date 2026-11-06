#!/bin/bash
#SBATCH --job-name=aos-analyze
#SBATCH --partition=gpua100
#SBATCH --gres=gpu:1
#SBATCH --open-mode=append
# Usage: sbatch --time=0:30:00 --output=LOG slurm/analyze.sbatch RUN_NAME
set -euo pipefail
REPO=${AOS_REPO:-$HOME/AngularOceanScattering}
SCRATCH=${AOS_SCRATCH:-/shared/greg_aeolus_earth/AngularOceanScattering}
unset LD_LIBRARY_PATH
export JULIA_DEPOT_PATH=$SCRATCH/depot:$(dirname "$(julia --startup-file=no -e 'print(Sys.BINDIR)')")/share/julia
julia --startup-file=no --project="$REPO" -e 'using Pkg; Pkg.instantiate()'
exec julia --startup-file=no --project="$REPO" "$REPO/src/analyze.jl" "$SCRATCH/runs/$1"
