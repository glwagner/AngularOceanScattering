#!/bin/bash
#SBATCH --job-name=aos-les
#SBATCH --partition=gpuprod
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=8
#SBATCH --nodes=1
#SBATCH --requeue
#SBATCH --open-mode=append
#
# Usage:  sbatch --time=H:MM:SS --output=LOG slurm/run.sbatch RUN_NAME [key=value ...]
# gpuprod holds the H100s and is spot-backed: the job requeues and resumes from its checkpoint.
set -euo pipefail

REPO=${AOS_REPO:-$HOME/AngularOceanScattering}
SCRATCH=${AOS_SCRATCH:-/shared/greg_aeolus_earth/AngularOceanScattering}
RUN=$1; shift
RUN_DIR=$SCRATCH/runs/$RUN
mkdir -p "$RUN_DIR"

ulimit -v unlimited
unset LD_LIBRARY_PATH   # use CUDA.jl's artifacts rather than the system CUDA
export JULIA_DEPOT_PATH=$SCRATCH/depot:$(dirname "$(julia --startup-file=no -e 'print(Sys.BINDIR)')")/share/julia
export JULIA_NUM_THREADS=${SLURM_CPUS_ON_NODE:-1}
export JULIA_NUM_PRECOMPILE_TASKS=${SLURM_CPUS_PER_TASK:-1}

if [ -n "$(git -C "$REPO" status --porcelain)" ] && [ "${AOS_ALLOW_DIRTY:-0}" != 1 ]; then
  echo "Refusing to run: uncommitted changes in $REPO" >&2; exit 78
fi

{
  echo "=== $(date -u +%FT%TZ) job=${SLURM_JOB_ID:-none} restart=${SLURM_RESTART_COUNT:-0} node=$(hostname)"
  echo "git=$(git -C "$REPO" rev-parse HEAD) dirty=$(git -C "$REPO" status --porcelain | wc -l)"
  julia --version
  nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv,noheader
  echo "args: $*"
} | tee -a "$RUN_DIR/provenance.txt"

julia --startup-file=no --project="$REPO" -e 'using Pkg; Pkg.instantiate(allow_autoprecomp=false)'
exec julia --startup-file=no --project="$REPO" "$REPO/src/simulation.jl" "output_dir=$RUN_DIR" "$@"
