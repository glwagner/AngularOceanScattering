#!/bin/bash
#SBATCH --job-name=aos-diag
#SBATCH --partition=gpuprod
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=8
#SBATCH --open-mode=append
# Small-box diagnosis of interior mixing, one change at a time. Usage: sbatch --time=2:00:00 --output=LOG slurm/diagnose.sbatch
set -uo pipefail
REPO=${AOS_REPO:-$HOME/AngularOceanScattering}
SCRATCH=${AOS_SCRATCH:-/shared/greg_aeolus_earth/AngularOceanScattering}
ulimit -v unlimited; unset LD_LIBRARY_PATH
export JULIA_DEPOT_PATH=$SCRATCH/depot:$(dirname "$(julia --startup-file=no -e 'print(Sys.BINDIR)')")/share/julia
export JULIA_NUM_PRECOMPILE_TASKS=${SLURM_CPUS_PER_TASK:-1}
julia --startup-file=no --project="$REPO" -e 'using Pkg; Pkg.instantiate(allow_autoprecomp=false)'
FINE="Nx=256 Ny=256 Nz=80 Lx=1024 Ly=1024 full_field_minutes=360"
COARSE="full_field_minutes=360"
REST="tau_x=0 Q_loss=0 noise_K=0"
run() { name=$1; shift
  dir=$SCRATCH/runs/diag/$name; echo "=== $name: $* $(date -u +%T) git=$(git -C "$REPO" rev-parse HEAD)"
  julia --startup-file=no --project="$REPO" "$REPO/src/simulation.jl" "output_dir=$dir" "$@" 2>&1 | grep -E 'ERROR|Finished|summary' 
  julia --startup-file=no --project="$REPO" "$REPO/src/analyze.jl" "$dir" 2>&1 | grep -E '^(FAIL|INFO|PASS interior)|ERROR'
}
run coarse-cfl02-dt10   $COARSE stop_hours=12 cfl=0.2 max_dt=10
run coarse-rest         $COARSE $REST stop_hours=6
run fine-cfl08          $FINE stop_hours=12 cfl=0.8 max_dt=150
run fine-cfl04-dt20     $FINE stop_hours=12 cfl=0.4 max_dt=20
run fine-cfl02-dt5      $FINE stop_hours=12 cfl=0.2 max_dt=5
run fine-rest           $FINE $REST stop_hours=6 cfl=0.4 max_dt=20
echo "=== done $(date -u +%T)"
