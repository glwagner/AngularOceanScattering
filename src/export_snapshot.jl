using JLD2, TOML, Printf, Dates

# Export one full-field snapshot of a completed run as a self-contained JLD2 file readable with JLD2 alone
# (plain arrays, strings and numbers only; no Oceananigans types).
# Usage: julia --project=. src/export_snapshot.jl SOURCE_RUN_DIR OUTPUT_FILE [TIME_SECONDS=172800]
# Never modifies the source and refuses to overwrite OUTPUT_FILE.

const FIELDS = ("u", "v", "w", "T")
const UNITS = Dict("u" => "m s^-1", "v" => "m s^-1", "w" => "m s^-1", "T" => "degC")
const DESCRIPTION = Dict("u" => "x (along-wind) velocity", "v" => "y velocity", "w" => "vertical velocity, positive up",
                         "T" => "potential temperature (linear equation of state, buoyancy b = g α (T - T0))")
const CAVEAT = "PRELIMINARY. The run passed its heat and momentum budget and CFL checks but FAILED its interior-stratification " *
    "check: bulk N^2 between z = -100 and -140 m fell to 87.3% of initial by 48 h. The loss is concentrated near the bottom " *
    "(lowest 10 m at 32.9%) and just below the mixed layer (-50 to -60 m at 82.3%); about -70 to -120 m stays above 90%. " *
    "The bottom (z = -160 m) is a rigid, impermeable, no-flux boundary with NO sponge or damping layer, so internal waves " *
    "can reflect from it. The likely cause of the loss, subgrid (AMD) diffusion, is not yet confirmed. See RUNS.md in the source repository."

locstr(L) = occursin("Face", string(L)) ? "Face" : "Center"

function main(src, out, t_target=172800.0)
    isfile(out) && error("Refusing to overwrite existing $out")
    mkpath(dirname(out))
    cfg = TOML.parsefile(joinpath(src, "config.toml"))
    provenance = read(joinpath(src, "provenance.txt"), String)
    git = match(r"git=([0-9a-f]{40})", provenance)
    git === nothing && error("No git hash in provenance.txt")
    Nx, Ny, Nz = cfg["Nx"], cfg["Ny"], cfg["Nz"]; Lx, Ly, Lz = cfg["Lx"], cfg["Ly"], cfg["Lz"]
    Δx, Δy, Δz = Lx / Nx, Ly / Ny, Lz / Nz
    coords = Dict("x_center" => collect((0.5:Nx) .* Δx), "x_face" => collect((0:Nx-1) .* Δx),
                  "y_center" => collect((0.5:Ny) .* Δy), "y_face" => collect((0:Ny-1) .* Δy),
                  "z_center" => collect(-Lz .+ (0.5:Nz) .* Δz), "z_face" => collect(-Lz .+ (0:Nz) .* Δz))
    srcfile = joinpath(src, "fields.jld2")
    f = jldopen(srcfile, "r")
    ids = sort(parse.(Int, filter(!=("serialized"), keys(f["timeseries/t"]))))
    i = ids[end]; t = f["timeseries/t/$i"]
    println("Source final iteration $i, t = $t s; ", length(ids), " snapshots")
    abs(t - t_target) < 1e-6 * t_target || error("Final time $t s is not $t_target s")
    for v in FIELDS; haskey(f["timeseries"], v) || error("Source lacks $v"); end

    summary = Dict{String,Any}()
    jldopen(out, "w") do g
        g["README"] = "Single 3-D snapshot of a surface-forced ocean boundary-layer LES (Oceananigans NonhydrostaticModel). " *
            "Fields are on a staggered C-grid: each field's location gives Center or Face in (x, y, z); use the matching " *
            "coordinate arrays (e.g. u is (Face, Center, Center): x_face, y_center, z_center). x and y are periodic, so there are " *
            "Nx x-faces and Ny y-faces; z is bounded, so there are Nz + 1 z-faces and w includes both boundary faces (where w = 0). " *
            "Array index order is [x, y, z], z increasing upward, z = 0 at the surface. Coordinates in metres, time in seconds."
        g["caveat"] = CAVEAT
        g["time_seconds"] = Float64(t); g["time_hours"] = Float64(t) / 3600; g["iteration"] = i
        for (k, c) in coords; g["grid/$k"] = c; end
        g["grid/units"] = "m"; g["grid/Nx"] = Nx; g["grid/Ny"] = Ny; g["grid/Nz"] = Nz
        g["grid/Lx"] = Lx; g["grid/Ly"] = Ly; g["grid/Lz"] = Lz; g["grid/topology"] = "x Periodic, y Periodic, z Bounded"
        for (k, v) in cfg; g["config/$k"] = v; end
        g["config_toml"] = read(joinpath(src, "config.toml"), String)
        g["source/git_commit"] = git.captures[1]
        g["source/provenance"] = provenance
        g["source/file"] = abspath(srcfile)
        g["source/iteration_key"] = string(i)
        g["export/created_utc"] = string(Dates.now(Dates.UTC))
        g["export/script"] = "src/export_snapshot.jl"
        for v in FIELDS
            A = Float32.(f["timeseries/$v/$i"])
            loc = locstr.(f["timeseries/$v/serialized/location"])
            expected = (loc[1] == "Face" ? Nx : Nx, loc[2] == "Face" ? Ny : Ny, loc[3] == "Face" ? Nz + 1 : Nz)
            size(A) == expected || error("$v has size $(size(A)), expected $expected for location $loc")
            all(isfinite, A) || error("$v has non-finite values")
            g["fields/$v/data"] = A
            g["fields/$v/location"] = collect(String, loc)
            g["fields/$v/coordinates"] = [string(lowercase(a), "_", lowercase(l)) for (a, l) in zip(("x", "y", "z"), loc)]
            g["fields/$v/units"] = UNITS[v]; g["fields/$v/description"] = DESCRIPTION[v]
            summary[v] = (size(A), loc, extrema(A))
            @printf("WROTE %s size=%s location=%s min=%.6g max=%.6g\n", v, string(size(A)), join(loc, ","), extrema(A)...); flush(stdout)
            A = nothing; GC.gc()
        end
    end

    # Validate: reopen, check every field equals the source bit-for-bit and coordinates match the sizes.
    jldopen(out, "r") do g
        g["time_seconds"] == t || error("time mismatch")
        for v in FIELDS
            B = g["fields/$v/data"]
            S = Float32.(f["timeseries/$v/$i"])
            B == S || error("$v differs from source")
            loc = g["fields/$v/location"]
            for (d, (a, l)) in enumerate(zip(("x", "y", "z"), loc))
                length(g["grid/$(a)_$(lowercase(l))"]) == size(B, d) || error("$v dim $d coordinate length mismatch")
            end
            @printf("VALID %s equal to source, %d values, extrema %.6g %.6g\n", v, length(B), extrema(B)...); flush(stdout)
            B = nothing; S = nothing; GC.gc()
        end
        g["grid/z_face"][1] == -Lz && g["grid/z_face"][end] == 0 || error("z_face endpoints")
    end
    close(f)
    println("COMPLETE ", out)
end

main(ARGS[1], ARGS[2], length(ARGS) > 2 ? parse(Float64, ARGS[3]) : 172800.0)
