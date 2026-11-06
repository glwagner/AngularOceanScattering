# Validation and quick-look figure for one run directory.
#
#   julia --project=. src/analyze.jl RUN_DIR
#
# Prints PASS/FAIL per check and exits nonzero if any check fails or could not be evaluated.

using CairoMakie
using JLD2
using Printf
using Statistics
using DelimitedFiles
using TOML

dir = ARGS[1]
config = TOML.parsefile(joinpath(dir, "config.toml"))  # always validate against the parameters of this run
stop_hours = config["stop_hours"]
Lz, τ, Q, f, ρ₀, cp = (config[k] for k in ("Lz", "tau_x", "Q_loss", "f", "rho0", "cp"))

function read_series(path, names)
    jldopen(path, "r") do file
        iters = sort(parse.(Int, filter(!=("serialized"), keys(file["timeseries/t"]))))
        t = [file["timeseries/t/$i"] for i in iters]
        data = Dict(n => [Float64.(vec(file["timeseries/$n/$i"])) for i in iters] for n in names)
        return iters, t, data
    end
end

failures = String[]
function check(name, ok, detail)
    println(ok ? "PASS " : "FAIL ", name, ": ", detail)
    ok || push!(failures, name)
end

_, tb, budget = read_series(joinpath(dir, "budget.jld2"), ["T", "u", "v", "KE"])
T̄ = first.(budget["T"]); Ū = first.(budget["u"]); V̄ = first.(budget["v"]); KE = first.(budget["KE"])

check("final time", tb[end] >= stop_hours * 3600 - 1, @sprintf("%.4f h saved, %.4f h requested", tb[end] / 3600, stop_hours))
check("monotonic output time", all(diff(tb) .> 0), "$(length(tb)) budget records")
check("finite budget", all(isfinite, vcat(T̄, Ū, V̄, KE)), "volume means")

# Exact domain budgets for a flux-only domain: bottom insulating and stress-free, periodic sides.
Jᵀ = Q / (ρ₀ * cp); Jᵤ = -τ / ρ₀
ΔT_exact = @. -Jᵀ * tb / Lz
ΔT = T̄ .- T̄[1]
err_T = maximum(abs, ΔT .- ΔT_exact)
check("heat budget sign+magnitude", ΔT[end] < 0 && err_T <= 0.01 * abs(ΔT_exact[end]),
      @sprintf("ΔT=%.5e K exact=%.5e K max|err|=%.2e K", ΔT[end], ΔT_exact[end], err_T))

U₀ = -Jᵤ / (Lz * f)
Ū_exact = @. U₀ * sin(f * tb)
V̄_exact = @. U₀ * (cos(f * tb) - 1)
err_U = maximum(abs, Ū .- Ū_exact); err_V = maximum(abs, V̄ .- V̄_exact)
check("momentum budget (inertial)", max(err_U, err_V) <= 0.01 * U₀,
      @sprintf("amplitude=%.4e m/s max|err u|=%.2e max|err v|=%.2e", U₀, err_U, err_V))

# Step log: CFL, Δt, extrema
rows, header = readdlm(joinpath(dir, "steps.csv"), ','; header=true)
col(name) = Float64.(rows[:, findfirst(==(name), vec(header))])
check("finite step log", all(isfinite, rows[:, 2:end] .|> Float64), "$(size(rows, 1)) rows")
cfl, dcfl, dt, ts = col("adv_cfl"), col("diff_cfl"), col("dt_s"), col("time_s")
spunup = ts .> 0.25 * ts[end]
capped = dt .>= 0.999 * maximum(dt)
@printf("INFO advective CFL median=%.3f max=%.3f; after spin-up median=%.3f\n", median(cfl), maximum(cfl), median(cfl[spunup]))
@printf("INFO diffusive CFL median=%.3f max=%.3f; Δt median=%.1f s, fraction at largest Δt=%.2f\n", median(dcfl), maximum(dcfl), median(dt), mean(capped))
check("advective CFL bounded", maximum(cfl) <= 1.0, @sprintf("max=%.3f", maximum(cfl)))

# Profiles
_, tp, prof = read_series(joinpath(dir, "profiles.jld2"), ["T", "U", "V", "uu", "vv", "ww"])
Nz = length(prof["T"][1]); Δz = Lz / Nz
zc = [-Lz + (k - 0.5) * Δz for k in 1:Nz]
function mixed_layer_depth(T; ΔT=0.02)
    for k in Nz-1:-1:1
        if T[end] - T[k] >= ΔT
            s = (T[end] - ΔT - T[k]) / (T[k+1] - T[k])
            return -(zc[k] + s * Δz)
        end
    end
    return Lz
end
h = mixed_layer_depth.(prof["T"])
@printf("INFO mixed-layer depth (ΔT=0.02 K below top cell): t=0 %.1f m, end %.1f m, max %.1f m\n", h[1], h[end], maximum(h))
check("mixed layer evolves", h[end] > h[1] + 1 && h[end] < Lz, @sprintf("%.1f m -> %.1f m", h[1], h[end]))
at_center(a) = length(a) == Nz ? a : (a[1:end-1] .+ a[2:end]) / 2
tke = reduce(hcat, [0.5 .* (prof["uu"][n] .- prof["U"][n] .^ 2 .+ prof["vv"][n] .- prof["V"][n] .^ 2 .+ at_center(prof["ww"][n]))
                    for n in eachindex(tp)])
@printf("INFO column-mean resolved TKE at end: %.3e m²/s²; surface-cell end %.3e\n", mean(tke[:, end]), tke[end, end])
check("turbulence developed", mean(tke[:, end]) > 1e-6, @sprintf("column TKE %.3e", mean(tke[:, end])))

# Full-field finiteness at every save
nonfinite = 0; nsaved = 0
jldopen(joinpath(dir, "fields.jld2"), "r") do file
    for n in ("u", "v", "w", "T"), key in filter(!=("serialized"), keys(file["timeseries/$n"]))
        global nsaved += 1
        all(isfinite, file["timeseries/$n/$key"]) || (global nonfinite += 1)
    end
end
check("finite full fields", nsaved > 0 && nonfinite == 0, "$nsaved snapshots, $nonfinite non-finite")

# Figure (Julia only)
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
println(isempty(failures) ? "ALL CHECKS PASSED" : "FAILED: " * join(failures, ", "))
exit(isempty(failures) ? 0 : 1)
