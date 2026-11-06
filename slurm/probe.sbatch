#!/bin/bash
#SBATCH --job-name=aos-probe
#SBATCH --partition=gpuprod
#SBATCH --gres=gpu:1
#SBATCH --cpus-per-task=8
#SBATCH --mem=180G
#SBATCH --open-mode=append
# Memory and speed ladder at Δx=Δy=4 m, Δz=2 m. Each probe writes real output and one checkpoint, then deletes them.
# Before each attempt, peak = fixed + per-cell × cells is fitted to the last two measurements; a grid predicted to
# exceed HEADROOM_PCT of the card is skipped. A grid is also skipped unless disk holds its output plus a margin.
# Usage: sbatch --time=3:00:00 --output=LOG slurm/probe.sbatch ["NxxNy ..."] [CFL] [MAX_DT]
set -uo pipefail
REPO=${AOS_REPO:-$HOME/AngularOceanScattering}
SCRATCH=${AOS_SCRATCH:-/shared/greg_aeolus_earth/AngularOceanScattering}
PROBE_ROOT=${AOS_PROBE_ROOT:-$HOME/AngularOceanScattering-data/probe}
ulimit -v unlimited; unset LD_LIBRARY_PATH
export JULIA_DEPOT_PATH=$SCRATCH/depot:$(dirname "$(julia --startup-file=no -e 'print(Sys.BINDIR)')")/share/julia
GRIDS=${1:-"1024x256 2048x256 2048x512 4096x512 4096x640 4096x768 4096x896 4096x1024 5120x1024"}
CFL=${2:-0.4}; MAX_DT=${3:-20}
HEADROOM_PCT=85; DISK_MARGIN_GB=100
BYTES_PER_CELL_ON_DISK=450  # upper estimate: two raw checkpoints during cleanup (2×180) + saves; replaced by measurement in the report
mkdir -p "$PROBE_ROOT"
TOTAL=$(nvidia-smi --query-gpu=memory.total --format=csv,noheader,nounits)
LIMIT=$((TOTAL*HEADROOM_PCT/100))
echo "git=$(git -C "$REPO" rev-parse HEAD) card_total_MiB=$TOTAL limit_MiB=$LIMIT probe_root=$PROBE_ROOT"
c1=0; p1=0; c2=0; p2=0
for g in $GRIDS; do
  Nx=${g%x*}; Ny=${g#*x}; cells=$((Nx*Ny*80)); name=probe-${Nx}x${Ny}; dir=$PROBE_ROOT/$name
  if [ "$c1" != 0 ]; then
    pred=$(awk -v c1=$c1 -v p1=$p1 -v c2=$c2 -v p2=$p2 -v c=$cells 'BEGIN{printf "%d", p2+(p2-p1)/(c2-c1)*(c-c2)}')
    echo "PREDICT $name cells=$cells peak_MiB=$pred limit_MiB=$LIMIT"
    if [ "$pred" -gt "$LIMIT" ]; then echo "SKIP $name: predicted over limit"; continue; fi
  fi
  free_gb=$(df -BG --output=avail "$PROBE_ROOT" | tail -1 | tr -dc 0-9)
  need_gb=$((cells*BYTES_PER_CELL_ON_DISK/1000000000+DISK_MARGIN_GB))
  echo "DISK $name free_GB=$free_gb need_GB=$need_gb"
  if [ "$free_gb" -lt "$need_gb" ]; then echo "SKIP $name: insufficient disk"; continue; fi
  rm -rf "$dir"
  echo "=== $name cells=$cells Lx=$((4*Nx)) Ly=$((4*Ny)) $(date -u +%T)"
  smi=$(mktemp); nvidia-smi --query-gpu=memory.used --format=csv,noheader,nounits -l 1 > "$smi" & sampler=$!
  start=$(date +%s)
  # 30 steps from Δt=5 s reach about 3 minutes: saves at t=0 and 2 min, one checkpoint at 2 min.
  julia --startup-file=no --project="$REPO" "$REPO/src/simulation.jl" "output_dir=$dir" Nx=$Nx Ny=$Ny Nz=80 \
      Lx=$((4*Nx)).0 Ly=$((4*Ny)).0 Lz=160.0 cfl=$CFL max_dt=$MAX_DT stop_iteration=30 log_interval=5 \
      checkpoint_minutes=2.0 full_field_minutes=2.0 profile_minutes=2.0 transect_minutes=2.0 slice_minutes=2.0 2>&1 \
      | grep -E 'ERROR|Out of GPU|summary|GPU memory|Effective|Memory pool|Peak host|iter [0-9]+ t='
  status=${PIPESTATUS[0]}
  kill $sampler; peak=$(sort -n "$smi" | tail -1); rm -f "$smi"
  echo "RESULT $name status=$status elapsed=$(( $(date +%s)-start ))s nvidia_peak_MiB=$peak ($((100*peak/TOTAL))%)"
  du -h "$dir"/* | sed 's/^/  /'
  awk -F, 'NR>1{printf "  iter=%s wall=%.2f\n",$2,$1}' "$dir/steps.csv"
  rm -rf "$dir"
  [ "$status" != 0 ] && { echo "STOP: probe failed"; break; }
  c1=$c2; p1=$p2; c2=$cells; p2=$peak
done
echo "=== ladder done $(date -u +%T)"
