#!/bin/bash
#SBATCH --job-name=aos-probe
#SBATCH --partition=gpuprod
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=8
#SBATCH --mem=180G
#SBATCH --open-mode=append
# Memory and speed ladder at Δx=Δy=4 m, Δz=2 m, smallest grid first. Each probe does real output and checkpoints.
# Stops growing once nvidia-smi peak passes 85% of the card, so that OOM is not provoked deliberately.
# Usage: sbatch --time=3:00:00 --output=LOG slurm/probe.sbatch "NxxNy NxxNy ..." [CFL] [MAX_DT]
set -uo pipefail
REPO=${AOS_REPO:-$HOME/AngularOceanScattering}
SCRATCH=${AOS_SCRATCH:-/shared/greg_aeolus_earth/AngularOceanScattering}
ulimit -v unlimited; unset LD_LIBRARY_PATH
export JULIA_DEPOT_PATH=$SCRATCH/depot:$(dirname "$(julia --startup-file=no -e 'print(Sys.BINDIR)')")/share/julia
GRIDS=${1:-"4096x512 4096x768 4096x1024"}; CFL=${2:-0.4}; MAX_DT=${3:-20}
TOTAL=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits)
echo "git=$(git -C "$REPO" rev-parse HEAD) card_total_MiB=$TOTAL"
for g in $GRIDS; do
  Nx=${g%x*}; Ny=${g#*x}; name=probe-${Nx}x${Ny}; dir=$SCRATCH/runs/probe/$name; rm -rf "$dir"
  echo "=== $name cells=$((Nx*Ny*80)) Lx=$((4*Nx)) Ly=$((4*Ny)) $(date -u +%T)"
  smi=$(mktemp); nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits -l 1 > "$smi" & sampler=$!
  start=$(date +%s)
  julia --startup-file=no --project="$REPO" "$REPO/src/simulation.jl" "output_dir=$dir" Nx=$Nx Ny=$Ny Nz=80 \
      Lx=$((4*Nx)).0 Ly=$((4*Ny)).0 Lz=160.0 cfl=$CFL max_dt=$MAX_DT stop_iteration=45 \
      checkpoint_minutes=1.0 full_field_minutes=1.0 profile_minutes=1.0 transect_minutes=1.0 2>&1 \
      | grep -E 'ERROR|OutOfGPU|Out of GPU|summary|GPU memory|Memory pool|Effective|Peak host|^iter|iter [0-9]+ t='
  status=${PIPESTATUS[0]}
  kill $sampler; peak=$(sort -n "$smi" | tail -1); rm -f "$smi"
  echo "RESULT $name status=$status elapsed=$(( $(date +%s)-start ))s nvidia_peak_MiB=$peak ($((100*peak/TOTAL))%)"
  du -h "$dir"/* | sed 's/^/  /'
  awk -F, 'NR>1{print}' "$dir/steps.csv" | tail -3
  rm -rf "$dir"
  [ "$status" != 0 ] && { echo "STOP: probe failed"; break; }
  [ $((100*peak/TOTAL)) -ge 85 ] && { echo "STOP: over 85% of the card"; break; }
done
echo "=== ladder done $(date -u +%T)"
