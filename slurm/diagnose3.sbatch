#!/bin/bash
#SBATCH --job-name=aos-diag3
#SBATCH --partition=gpuprod,gpuprodflex
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=8
#SBATCH --time=03:00:00
#SBATCH --open-mode=append
# Closure test for the 4 m / 2 m production loss of N², which concentrates near the bottom and under the mixed layer.
# Fine box (production grid spacing, CFL 0.4, max_dt 20 s), 12 h: AMD control vs no closure vs Smagorinsky,
# each followed by the bulk analysis and the N² depth / flux diagnostic.
set -uo pipefail
REPO=${AOS_REPO:-$HOME/AngularOceanScattering}
SCRATCH=${AOS_SCRATCH:-/shared/greg_aeolus_earth/AngularOceanScattering}
ulimit -v unlimited; unset LD_LIBRARY_PATH
export JULIA_DEPOT_PATH=$SCRATCH/depot:$(dirname "$(julia --startup-file=no -e 'print(Sys.BINDIR)')")/share/julia
julia --startup-file=no --project="$REPO" -e 'using Pkg; Pkg.instantiate(allow_autoprecomp=false)'
FINE="Nx=256 Ny=256 Nz=80 Lx=1024 Ly=1024 full_field_minutes=360 stop_hours=12 cfl=0.4 max_dt=20"
run() { name=$1; shift
  dir=$SCRATCH/runs/diag3/$name; echo "=== $name: $* $(date -u +%T) git=$(git -C "$REPO" rev-parse HEAD)"
  julia --startup-file=no --project="$REPO" "$REPO/src/simulation.jl" "output_dir=$dir" "$@" 2>&1 | grep -E 'ERROR|summary'
  julia --startup-file=no --project="$REPO" "$REPO/src/analyze.jl" "$dir" 2>&1 | grep -E '^(FAIL|INFO|PASS interior)|ERROR'
  julia --startup-file=no --project="$REPO" "$REPO/src/n2_depth.jl" "$dir" 2>&1
}
run fine-amd  $FINE closure=AMD
run fine-none $FINE closure=none
run fine-smag $FINE closure=Smagorinsky
echo "=== done $(date -u +%T)"
