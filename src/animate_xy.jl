using CairoMakie, JLD2, TOML, Statistics, Printf

# Horizontal-slice animation of a completed run (reads saved output only; never modifies the run).
# Usage: julia --project=. src/animate_xy.jl RUN_DIR OUTPUT_DIR [MAX_FRAMES]
# Writes, in one streaming pass over xy_upper.jld2 and xy_lower.jld2 (one frame in memory at a time):
#   xy-detail.mp4    four fixed 1.536 km squares at native 4 m resolution (w′ and T′ at both slice depths)
#   xy-overview.mp4  the full horizontal domain for the same four fields, with the detail square outlined
#   xy-detail-final.png, xy-overview-final.png, animation-info.txt
# Shown fields are anomalies from the instantaneous mean over the whole slice: q′ = q − ⟨q⟩_xy.
# Colour limits are fixed for the whole movie: the 99.5th percentile of |q′| pooled over 25 frames evenly spaced in
# time (full domain). Larger values saturate; the saturated fraction over those frames is recorded in animation-info.txt.
# No temporal interpolation, spatial smoothing or interpolation between cells.

const CAVEAT = "Validation: budgets and CFL passed; interior-stratification check FAILED (bulk −100 to −140 m N² at 87.3% of initial after 48 h; " *
               "loss concentrated near the bottom and below the mixed layer). See RUNS.md."

frame_ids(f) = sort(parse.(Int, filter(!=("serialized"), keys(f["timeseries/t"]))))
slice(f, v, i) = dropdims(f["timeseries/$v/$i"]; dims=3)
anomaly(A) = (m = mean(Float64, A); Float32.(A .- m))

function slice_level(f, v, cfg)
    ind = f["timeseries/$v/serialized/indices"]
    loc = f["timeseries/$v/serialized/location"]
    k = first(ind[3])
    Δz = cfg["Lz"] / cfg["Nz"]
    face = occursin("Face", string(loc[3]))
    z = face ? -cfg["Lz"] + (k - 1) * Δz : -cfg["Lz"] + (k - 0.5) * Δz
    return k, z, face ? "face" : "center", Δz
end

function main(run_dir, out, nmax=typemax(Int))
    mkpath(out)
    cfg = TOML.parsefile(joinpath(run_dir, "config.toml"))
    Nx, Ny = cfg["Nx"], cfg["Ny"]; Lx, Ly = cfg["Lx"], cfg["Ly"]
    Δx, Δy = Lx / Nx, Ly / Ny
    x = (collect(1:Nx) .- 0.5) .* Δx ./ 1e3
    y = (collect(1:Ny) .- 0.5) .* Δy ./ 1e3
    fu = jldopen(joinpath(run_dir, "xy_upper.jld2"), "r")
    fl = jldopen(joinpath(run_dir, "xy_lower.jld2"), "r")
    files = (fu, fl)
    ids = frame_ids(fu)
    ids == frame_ids(fl) || error("xy_upper and xy_lower have different frames")
    nmax < length(ids) && (ids = ids[unique(round.(Int, range(1, length(ids), length=nmax)))])  # layout test: evenly spaced, includes last
    times = [fu["timeseries/t/$i"] / 3600 for i in ids]
    levels = [(slice_level(f, "w", cfg), slice_level(f, "T", cfg)) for f in files]
    for (n, L) in zip(("upper", "lower"), levels); println("LEVEL ", n, " w: ", L[1], " T: ", L[2]); end
    zlabel(L) = @sprintf("z = %.0f m", L[2])
    # Detail square: fixed 384 × 384 cells (1.536 km) centred in the domain.
    nd = min(384, Nx, Ny)
    ix = (Nx ÷ 2 - nd ÷ 2 + 1):(Nx ÷ 2 + nd ÷ 2); iy = (Ny ÷ 2 - nd ÷ 2 + 1):(Ny ÷ 2 + nd ÷ 2)

    # Colour limits from sampled frames.
    sample = unique(round.(Int, range(1, length(ids), length=25)))
    keyset = [(d, v) for d in 1:2 for v in ("w", "T")]
    lims = Dict{Tuple{Int,String},Float64}(); clipped = Dict{Tuple{Int,String},Float64}()
    for (d, v) in keyset
        vals = reduce(vcat, [abs.(vec(anomaly(slice(files[d], v, ids[n])))) for n in sample])
        lims[(d, v)] = max(quantile(vals, 0.995), v == "w" ? 1e-6 : 1e-7)
        clipped[(d, v)] = mean(vals .> lims[(d, v)])
        println(@sprintf("LIMIT %s %s %.3e clipped %.4f", d == 1 ? "upper" : "lower", v, lims[(d, v)], clipped[(d, v)])); flush(stdout)
    end

    scale(v) = 1e3                                     # w′ in mm/s, T′ in mK
    unit(v) = v == "w" ? "w′ (mm/s)" : "T′ (mK)"
    full = Dict(k => Observable(zeros(Float32, Nx, Ny)) for k in keyset)
    detail = Dict(k => Observable(zeros(Float32, nd, nd)) for k in keyset)
    tlabel = Observable("")
    title = @sprintf("Surface-forced ocean boundary layer LES: horizontal slices (Δx = Δy = %.0f m, Δz = %.0f m; %d × %d × %d)",
                     Δx, cfg["Lz"] / cfg["Nz"], Nx, Ny, cfg["Nz"])
    forcing = @sprintf("τx = %.2f N/m², cooling %.0f W/m², f = %.0e s⁻¹, N² = %.0e s⁻²; anomalies from the instantaneous slice mean",
                       cfg["tau_x"], cfg["Q_loss"], cfg["f"], cfg["N2"])
    limits_note = "Fixed colour limits: 99.5th percentile of |q′| over 25 sampled frames; values beyond saturate. No smoothing or interpolation."

    # Detail figure: 2 × 2 squares.
    figd = Figure(size=(1920, 1080), fontsize=17, backgroundcolor=:white)
    Label(figd[0, 1:4], title; fontsize=22, font=:bold)
    Label(figd[1, 1:4], tlabel; fontsize=20)
    for (row, d) in enumerate(1:2), (col, v) in enumerate(("w", "T"))
        L = levels[d][v == "w" ? 1 : 2]
        ax = Axis(figd[row + 1, 2col - 1]; aspect=DataAspect(), xlabel="x (km)", ylabel="y (km)",
                  title=@sprintf("%s, %s (%s), 1.536 km detail at native %.0f m", v == "w" ? "Vertical velocity w′" : "Temperature T′",
                                 zlabel(L), L[3], Δx), titlesize=17)
        hm = heatmap!(ax, x[ix], y[iy], detail[(d, v)]; colormap=v == "w" ? :balance : Reverse(:RdBu),
                      colorrange=(-1, 1) .* (lims[(d, v)] * scale(v)), interpolate=false)
        Colorbar(figd[row + 1, 2col], hm; label=unit(v), height=Relative(0.85))
    end
    Label(figd[4, 1:4], forcing * "\n" * limits_note * "\n" * CAVEAT; fontsize=14, color=:gray35, justification=:center, word_wrap=true)
    rowgap!(figd.layout, 6)

    # Overview figure: four full-domain strips.
    figo = Figure(size=(1920, 1700), fontsize=17, backgroundcolor=:white)
    Label(figo[0, 1:2], title; fontsize=22, font=:bold)
    Label(figo[1, 1:2], tlabel; fontsize=20)
    row = 2
    for d in 1:2, v in ("w", "T")
        L = levels[d][v == "w" ? 1 : 2]
        ax = Axis(figo[row, 1]; aspect=DataAspect(), ylabel="y (km)", xlabel=row == 5 ? "x (km)" : "",
                  title=@sprintf("%s, %s (%s), full %.2f × %.2f km domain", v == "w" ? "w′" : "T′", zlabel(L), L[3], Lx / 1e3, Ly / 1e3), titlesize=17)
        hm = heatmap!(ax, x, y, full[(d, v)]; colormap=v == "w" ? :balance : Reverse(:RdBu),
                      colorrange=(-1, 1) .* (lims[(d, v)] * scale(v)), interpolate=false)
        lines!(ax, x[first(ix)] .+ [-0.5, nd - 0.5, nd - 0.5, -0.5, -0.5] .* Δx / 1e3,
               y[first(iy)] .+ [-0.5, -0.5, nd - 0.5, nd - 0.5, -0.5] .* Δy / 1e3; color=:black, linewidth=1.5)
        Colorbar(figo[row, 2], hm; label=unit(v))
        row += 1
    end
    Label(figo[row, 1:2], forcing * "\nBlack square: detail-movie region. The full domain has more cells than screen pixels, so this view is " *
          "downsampled for display; use the detail movie for native resolution.\n" * limits_note * "\n" * CAVEAT;
          fontsize=14, color=:gray35, justification=:center, word_wrap=true)

    function frame!(n)
        for (d, v) in keyset
            A = anomaly(slice(files[d], v, ids[n])) .* Float32(scale(v))
            full[(d, v)][] = A
            detail[(d, v)][] = A[ix, iy]
        end
        tlabel[] = @sprintf("t = %5.2f h   (frame %d / %d, saved every %.0f min)", times[n], n, length(ids), cfg["slice_minutes"])
    end
    # Final-time preview first, so it can be inspected before the movies finish.
    frame!(length(ids)); save(joinpath(out, "xy-detail-final.png"), figd); save(joinpath(out, "xy-overview-final.png"), figo)
    println("PREVIEW ", joinpath(out, "xy-detail-final.png"), " ", joinpath(out, "xy-overview-final.png")); flush(stdout)
    sd = VideoStream(figd; framerate=24, format="mp4", compression=18, profile="high", pixel_format="yuv420p")
    so = VideoStream(figo; framerate=24, format="mp4", compression=18, profile="high", pixel_format="yuv420p")
    t0 = time()
    for n in eachindex(ids)
        frame!(n); recordframe!(sd); recordframe!(so)
        if n == 1 || n % 12 == 0 || n == length(ids)
            el = time() - t0
            println(@sprintf("FRAME %d/%d t=%.2f h wall=%.0f s eta=%.0f s", n, length(ids), times[n], el, el / n * (length(ids) - n))); flush(stdout)
        end
    end
    save(joinpath(out, "xy-detail.mp4"), sd); save(joinpath(out, "xy-overview.mp4"), so)
    frame!(length(ids)); save(joinpath(out, "xy-detail-final.png"), figd); save(joinpath(out, "xy-overview-final.png"), figo)
    open(joinpath(out, "animation-info.txt"), "w") do io
        println(io, "Source run: ", abspath(run_dir))
        println(io, "Frames: ", length(ids), " at 24 fps (", round(length(ids) / 24, digits=1), " s); t = ", times[1], " to ", times[end], " h")
        for (n, L) in zip(("xy_upper", "xy_lower"), levels)
            println(io, n, ": w at k=", L[1][1], " (", L[1][3], ") z=", L[1][2], " m; T at k=", L[2][1], " (", L[2][3], ") z=", L[2][2], " m")
        end
        println(io, "Detail square: i=", ix, ", j=", iy, " (", nd, " × ", nd, " cells, ", nd * Δx / 1e3, " km), x = ",
                (first(ix) - 1) * Δx / 1e3, "–", last(ix) * Δx / 1e3, " km, y = ", (first(iy) - 1) * Δy / 1e3, "–", last(iy) * Δy / 1e3, " km")
        println(io, "Shown: q′ = q − instantaneous mean over the full slice. Units: w′ mm/s, T′ mK.")
        println(io, "Colour limits (99.5th percentile of |q′|, 25 evenly spaced frames, full domain) and saturated fraction:")
        for (d, v) in keyset
            println(io, @sprintf("  %s %s: ±%.4g %s, saturated %.2f%%", d == 1 ? "upper" : "lower", v, lims[(d, v)] * scale(v),
                                 v == "w" ? "mm/s" : "mK", 100 * clipped[(d, v)]))
        end
        println(io, "No temporal interpolation, smoothing or cell interpolation. Overview is downsampled for display only.")
        println(io, CAVEAT)
    end
    close(fu); close(fl)
    println("COMPLETE ", out)
end

main(ARGS[1], ARGS[2], length(ARGS) > 2 ? parse(Int, ARGS[3]) : typemax(Int))
