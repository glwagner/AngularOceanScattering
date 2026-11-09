#!/bin/bash
#SBATCH --job-name=aos-diag2
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=8
#SBATCH --open-mode=append
# Closure test: at depth AMD κₑ≈0.03 m²/s and its flux dominates the resolved one in the first diagnosis.
set -uo pipefail
REPO=${AOS_REPO:-$HOME/AngularOceanScattering}
SCRATCH=${AOS_SCRATCH:-$HOME/AngularOceanScattering-data}
ulimit -v unlimited; unset LD_LIBRARY_PATH
export JULIA_DEPOT_PATH=$SCRATCH/depot:$(dirname "$(julia --startup-file=no -e 'print(Sys.BINDIR)')")/share/julia
julia --startup-file=no --project="$REPO" -e 'using Pkg; Pkg.instantiate(allow_autoprecomp=false)'
FINE="Nx=256 Ny=256 Nz=80 Lx=1024 Ly=1024 full_field_minutes=360"
run() { name=$1; shift
  dir=$SCRATCH/runs/diag/$name; echo "=== $name: $* $(date -u +%T) git=$(git -C "$REPO" rev-parse HEAD)"
  julia --startup-file=no --project="$REPO" "$REPO/src/simulation.jl" "output_dir=$dir" "$@" 2>&1 | grep -E 'ERROR|summary'
  julia --startup-file=no --project="$REPO" "$REPO/src/analyze.jl" "$dir" 2>&1 | grep -E '^(FAIL|INFO|PASS interior)|ERROR'
}
run coarse-none full_field_minutes=360 stop_hours=12 closure=none
run coarse-smag full_field_minutes=360 stop_hours=12 closure=Smagorinsky
run fine-none   $FINE stop_hours=12 cfl=0.4 max_dt=20 closure=none
run fine-smag   $FINE stop_hours=12 cfl=0.4 max_dt=20 closure=Smagorinsky
echo "=== done $(date -u +%T)"
