#!/bin/bash
# Lightweight login-node progress check: reads steps.csv only, appends to the status file, exits when the job ends.
# Usage: slurm/monitor.sh JOB RUN_DIR STOP_HOURS STATUS_FILE [INTERVAL_S]
J=$1; D=$2; H=$3; F=$4; I=${5:-1800}
while :; do
  s=$(sacct -nXj "$J" -o State | head -1 | tr -d ' ')
  awk -F, -v H="$H" -v now="$(date +%s)" -v st="$s" -v free="$(df -BG --output=avail "$D" | tail -1 | tr -d ' ')" 'NR==2{w0=$1;t0=$3}
    NR>1{w=$1;t=$3;dt=$4;c=$5;d=$6;wm=$9;a=$10;b=$11; for(i=2;i<=11;i++) if($i!~/^-?[0-9.]+(e[-+]?[0-9]+)?$/) bad=1}
    END{ if(NR<2){print "state=" st " no steps yet"; exit}
      r=(t>t0)?(w-w0)/(t-t0):0; printf "state=%s t=%.2f h dt=%.2f s CFL=%.3f dCFL=%.3f max|w|=%.2e T=[%.3f,%.3f] ETA=%.1f h last_step_age=%d s free=%s%s\n",st,t/3600,dt,c,d,wm,a,b,(H*3600-t)*r/3600,now-w,free,bad?" NONFINITE":"" }' "$D/steps.csv" 2>/dev/null \
    | sed "s/^/- $(date -u +%FT%TZ) job $J: /" >> "$F"
  case "$s" in COMPLETED|FAILED*|CANCEL*|TIMEOUT*|NODE_FAIL*|OUT_OF*) echo "ended $s"; tail -1 "$F"; exit;; esac
  sleep "$I"
done
