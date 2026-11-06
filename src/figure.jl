# Quick-look figure; included by analyze.jl with --figure, using its validated series.
using CairoMakie

hours = tb ./ 3600
fig = Figure(size=(1300, 1100), fontsize=15)
ax = Axis(fig[1, 1], xlabel="t (h)", ylabel="ΔT̄ (K)", title="Domain-mean temperature change")
lines!(ax, hours, ΔT, label="LES", linewidth=3); lines!(ax, hours, ΔT_exact, label="−Jᵀt/Lz", linestyle=:dash, color=:black); axislegend(ax, position=:lb)
ax = Axis(fig[1, 2], xlabel="t (h)", ylabel="m/s", title="Domain-mean velocity")
lines!(ax, hours, Ū, label="U", linewidth=3); lines!(ax, hours, V̄, label="V", linewidth=3)
lines!(ax, hours, Ū_exact, color=:black, linestyle=:dash, label="inertial budget"); lines!(ax, hours, V̄_exact, color=:black, linestyle=:dash); axislegend(ax, position=:lb)
ax = Axis(fig[2, 1], xlabel="t (h)", ylabel="z (m)", title="Horizontal-mean resolved TKE (log₁₀ m²/s²)")
hm = heatmap!(ax, tp ./ 3600, zc, log10.(max.(tke', 1e-9)); colorrange=(-7, -3))
Colorbar(fig[2, 1][1, 2], hm); lines!(ax, tp ./ 3600, -h, color=:white, linewidth=2)
ax = Axis(fig[2, 2], xlabel="T̄ (°C)", ylabel="z (m)", title="Temperature profiles")
for n in round.(Int, range(1, length(tp), length=5))
    lines!(ax, prof["T"][n], zc, label=@sprintf("%.0f h", tp[n] / 3600), linewidth=2)
end
axislegend(ax, position=:rb)
ax = Axis(fig[3, 1], xlabel="t (h)", title="Time step control", ylabel="CFL")
lines!(ax, ts ./ 3600, cfl, label="advective"); lines!(ax, ts ./ 3600, dcfl, label="diffusive"); axislegend(ax, position=:rb)
jldopen(joinpath(dir, "xz_transect.jld2"), "r") do file
    iters = sort(parse.(Int, filter(!=("serialized"), keys(file["timeseries/t"]))))
    last_iter = iters[end]
    Tsec = dropdims(Float64.(file["timeseries/T/$last_iter"]); dims=2)
    x = range(0, step=config["Lx"] / size(Tsec, 1), length=size(Tsec, 1))
    ax = Axis(fig[3, 2], xlabel="x (km)", ylabel="z (m)", title=@sprintf("T′ at y=j₁, t=%.0f h (K)", file["timeseries/t/$last_iter"] / 3600))
    anomaly = Tsec .- mean(Tsec, dims=1)
    m = max(maximum(abs, anomaly), 1e-6)
    hm = heatmap!(ax, x ./ 1e3, zc, anomaly; colormap=:balance, colorrange=(-m, m))
    Colorbar(fig[3, 2][1, 2], hm)
end
output = joinpath(dir, "diagnostics.png")
save(output, fig)
println("Figure: ", output)
