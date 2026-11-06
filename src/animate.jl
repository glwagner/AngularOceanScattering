using CairoMakie, JLD2, TOML, Statistics, Printf

# Usage: julia --project=. src/animate.jl RUN_DIR OUTPUT_DIR
# Visualizes existing output only; does not modify or rerun the simulation.
function main(run_dir, output_dir)
    mkpath(output_dir)
    cfg = TOML.parsefile(joinpath(run_dir, "config.toml"))
    ids, times, temperatures, velocities = jldopen(joinpath(run_dir, "xz_transect.jld2"), "r") do f
        ids = sort(parse.(Int, keys(f["timeseries/t"])))
        selected = unique(vcat(collect(1:2:length(ids)), length(ids)))
        ids = ids[selected]
        times = [f["timeseries/t/$i"] / 3600 for i in ids]
        Ts = [dropdims(Float32.(f["timeseries/T/$i"]); dims=2) for i in ids]
        ws = [dropdims(Float32.(f["timeseries/w/$i"]); dims=2) for i in ids]
        ids, times, Ts, ws
    end
    nx, nz = size(first(temperatures))
    dx, dz = cfg["Lx"] / nx, cfg["Lz"] / nz
    x = ((collect(1:nx) .- 0.5) .* dx) ./ 1000
    z = -cfg["Lz"] .+ (collect(1:nz) .- 0.5) .* dz
    anomalies = [T .- mean(T; dims=1) for T in temperatures]
    # w is stored on vertical faces; interpolate to cell centers for comparison.
    wc = [size(w, 2) == nz + 1 ? (w[:, 1:end-1] .+ w[:, 2:end]) .* 500 : w .* 1000 for w in velocities]
    all(A -> all(isfinite, A), vcat(anomalies, wc)) || error("Nonfinite plot data")
    tlim = max(quantile(abs.(vcat(vec.(anomalies)...)), 0.995), 1e-6)
    wlim = max(quantile(abs.(vcat(vec.(wc)...)), 0.995), 1e-6)
    zoom = findall(xi -> 4.48 <= xi <= 5.76, x)
    isempty(zoom) && error("Default detail window lies outside this run")
    temp = Observable(anomalies[end])
    vel = Observable(wc[end])
    temp_zoom = Observable(anomalies[end][zoom, :])
    vel_zoom = Observable(wc[end][zoom, :])
    time_label = Observable(@sprintf("Surface-forced boundary layer | t = %.2f h", times[end]))
    fig = Figure(size=(1600, 1000), fontsize=18, backgroundcolor=:white)
    Label(fig[0, 1:4], time_label; fontsize=27, font=:bold)
    Label(fig[1, 1:4], "10 m grid | fixed x-z transect | existing run: interior mixing under investigation";
          fontsize=17, color=:gray35)
    a = Axis(fig[2, 1], title="Temperature anomaly — full 10.24 km", ylabel="z (m)", xlabel="x (km)")
    hm = heatmap!(a, x, z, temp; colormap=:balance, colorrange=(-tlim, tlim), interpolate=false)
    Colorbar(fig[2, 2], hm; label="T − along-transect mean (°C)")
    b = Axis(fig[2, 3], title="Vertical velocity — full 10.24 km", ylabel="z (m)", xlabel="x (km)")
    hm = heatmap!(b, x, z, vel; colormap=:balance, colorrange=(-wlim, wlim), interpolate=false)
    Colorbar(fig[2, 4], hm; label="w (mm/s)")
    c = Axis(fig[3, 1], title="Temperature anomaly — 1.28 km detail", ylabel="z (m)", xlabel="x (km)")
    hm = heatmap!(c, x[zoom], z, temp_zoom; colormap=:balance, colorrange=(-tlim, tlim), interpolate=false)
    Colorbar(fig[3, 2], hm; label="T − along-transect mean (°C)")
    d = Axis(fig[3, 3], title="Vertical velocity — 1.28 km detail", ylabel="z (m)", xlabel="x (km)")
    hm = heatmap!(d, x[zoom], z, vel_zoom; colormap=:balance, colorrange=(-wlim, wlim), interpolate=false)
    Colorbar(fig[3, 4], hm; label="w (mm/s)")
    for ax in (a, b, c, d)
        ylims!(ax, -cfg["Lz"], 0)
        hlines!(ax, [-cfg["mixed_layer_depth"]]; color=(:black, 0.5), linestyle=:dash, linewidth=1)
    end
    Label(fig[4, 1:4], "Dashed line: initial 30 m mixed-layer base. Vertical scale exaggerated; cells shown without smoothing."; fontsize=15)
    Label(fig[5, 1:4], "Fixed color limits: 99.5th percentile of |field| across displayed frames; values beyond limits saturate."; fontsize=15, color=:gray40)
    snapshot = joinpath(output_dir, "boundary-layer-48h.png")
    save(snapshot, fig; px_per_unit=1.5)
    println("SNAPSHOT ", snapshot); flush(stdout)
    function frame!(i)
        temp[] = anomalies[i]
        vel[] = wc[i]
        temp_zoom[] = anomalies[i][zoom, :]
        vel_zoom[] = wc[i][zoom, :]
        time_label[] = @sprintf("Surface-forced boundary layer | t = %.2f h", times[i])
    end
    movie = joinpath(output_dir, "boundary-layer-48h.mp4")
    record(fig, movie, eachindex(times); framerate=24) do i
        frame!(i)
        if i % 48 == 0
            println("FRAME ", i, "/", length(times)); flush(stdout)
        end
    end
    frame!(argmin(abs.(times .- 3)))
    save(joinpath(output_dir, "boundary-layer-3h-preview.png"), fig)
    open(joinpath(output_dir, "animation-info.txt"), "w") do io
        println(io, "Source: ", abspath(run_dir))
        println(io, "Frames: ", length(times), "; fps: 24; duration_s: ", length(times)/24)
        println(io, "Time range (h): ", first(times), " to ", last(times))
        println(io, "T anomaly limit (K): ", tlim, "; w limit (mm/s): ", wlim)
        println(io, "Existing coarse run; suspect interior mixing remains undiagnosed.")
    end
    println("COMPLETE ", movie)
end

main(ARGS[1], ARGS[2])
