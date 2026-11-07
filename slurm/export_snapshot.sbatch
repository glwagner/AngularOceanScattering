#!/bin/bash
#SBATCH --job-name=aos-export
#SBATCH --partition=gpua100largex4
#SBATCH --cpus-per-task=2
#SBATCH --mem=32G
#SBATCH --time=02:00:00
#SBATCH --open-mode=append
# CPU-only (no GPU requested). Usage: sbatch --output=LOG slurm/export_snapshot.sbatch SOURCE_RUN_DIR OUTPUT_DIR
set -euo pipefail
REPO=${AOS_REPO:-$HOME/AngularOceanScattering}
SRC=$1; OUT=$2; FILE=$OUT/snapshot-48h.jld2
[ -e "$FILE" ] && { echo "refusing to overwrite $FILE"; exit 3; }
mkdir -p "$OUT"
unset LD_LIBRARY_PATH
export JULIA_DEPOT_PATH=/shared/greg_aeolus_earth/AngularOceanScattering/depot:$(dirname "$(julia --startup-file=no -e 'print(Sys.BINDIR)')")/share/julia
GIT=$(git -C "$REPO" rev-parse HEAD)
echo "=== $(date -u +%FT%TZ) job=${SLURM_JOB_ID:-} node=$(hostname) git=$GIT dirty=$(git -C "$REPO" status --porcelain | wc -l)"
julia --startup-file=no --compiled-modules=existing --project="$REPO" "$REPO/src/export_snapshot.jl" "$SRC" "$FILE" 172800 | tee "$OUT/export.log"
grep -q '^COMPLETE' "$OUT/export.log" || { echo "export did not complete"; exit 1; }
chmod a-w "$FILE"
(cd "$OUT" && sha256sum snapshot-48h.jld2 > snapshot-48h.jld2.sha256)
SIZE=$(stat -c %s "$FILE"); SHA=$(cut -d' ' -f1 "$OUT/snapshot-48h.jld2.sha256")
cat > "$OUT/README.md" <<EOF
# production-4m2m: 3-D snapshot at t = 48 h

File: \`snapshot-48h.jld2\` ($SIZE bytes), SHA-256 \`$SHA\`.
Readable with JLD2.jl alone, as plain arrays, strings and numbers with no Oceananigans types:
\`using JLD2; f = jldopen("snapshot-48h.jld2"); T = f["fields/T/data"]; z = f["grid/z_center"]\`.

**Preliminary; see \`caveat\` in the file.** The run passed its heat and momentum budget and CFL checks, but it failed its
interior-stratification check (bulk N² from −100 to −140 m at 87.3% of initial after 48 h). The loss is concentrated near the
bottom and just below the mixed layer. The bottom at −160 m is rigid and no-flux, with no sponge layer.

## Run
LES with Oceananigans NonhydrostaticModel (WENO5, AMD closure). Domain 20480 × 3600 × 160 m, grid 5120 × 900 × 80
(Δx = Δy = 4 m, Δz = 2 m). x and y are periodic; z is bounded. Forcing: τx = 0.05 N/m², surface cooling 50 W/m², f = 1e-4 s⁻¹.
Initial state: 30 m mixed layer at 15 °C over N² = 1e-5 s⁻², α = 2e-4 K⁻¹, g = 9.81 m/s². Snapshot at t = 172800 s (iteration 16970).
The full configuration is in \`config/\` and \`config_toml\`. Simulation commit: see \`source/git_commit\`. Export commit: $GIT.

## Structure
| Path | Contents |
|---|---|
| \`fields/{u,v,w,T}/data\` | Float32 arrays in the original staggering, index order [x, y, z], z upward |
| \`fields/*/location\` | e.g. ["Face","Center","Center"] for u |
| \`fields/*/coordinates\` | names of the matching grid arrays, e.g. ["x_face","y_center","z_center"] |
| \`fields/*/units\`, \`description\` | u, v, w in m s⁻¹; T in °C |
| \`grid/{x,y,z}_{center,face}\` | Float64 coordinates in m (x_face starts at 0; z_face runs −160 … 0, Nz+1 values) |
| \`time_seconds\`, \`time_hours\`, \`iteration\` | 172800, 48, 16970 |
| \`config/*\`, \`config_toml\`, \`source/*\`, \`export/*\` | run parameters and provenance |
| \`README\`, \`caveat\` | text |

Sizes: u, v, T are 5120 × 900 × 80; w is 5120 × 900 × 81 (it includes both boundary faces, where w = 0).

## Validation at export
$(grep -E '^(WROTE|VALID)' "$OUT/export.log" | sed 's/^/- /')
EOF
echo "DONE $FILE $SIZE $SHA"
