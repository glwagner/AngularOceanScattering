# Surface-forced ocean boundary-layer LES on a uniform 10 m grid.
#
#   julia --project=. src/simulation.jl [key=value ...]
#
# See README.md for the scientific specification. Every parameter below can be
# overridden on the command line, e.g. `stop_hours=2 output_dir=/path/run`.
# Rerunning with an existing checkpoint in output_dir resumes from it.

using Oceananigans
using Oceananigans.Units
using Oceananigans: fields
using Oceananigans.BoundaryConditions: FluxBoundaryCondition
using CUDA
using JLD2
using Printf
using Random
using Statistics
using TOML

const DEFAULTS = Dict{String, Any}(
    "Nx" => 1024, "Ny" => 64, "Nz" => 16,
    "Lx" => 10240.0, "Ly" => 640.0, "Lz" => 160.0,
    "mixed_layer_depth" => 30.0,   # m
    "T_surface" => 15.0,           # °C
    "N2" => 1e-5,                  # s⁻²
    "alpha" => 2e-4,               # K⁻¹
    "g" => 9.81,                   # m s⁻²
    "f" => 1e-4,                   # s⁻¹
    "tau_x" => 0.05,               # N m⁻², stress on the ocean toward +x
    "Q_loss" => 50.0,              # W m⁻², heat lost by the ocean
    "rho0" => 1025.0,              # kg m⁻³
    "cp" => 3990.0,                # J kg⁻¹ K⁻¹
    "noise_K" => 1e-3,             # K, seed amplitude
    "noise_depth" => 30.0,         # m
    "seed" => 20261106,
    "closure" => "AMD",            # AMD | Smagorinsky | none
    "weno_order" => 5,
    "cfl" => 0.8,
    "diffusive_cfl" => 0.5,
    "max_dt" => 150.0,             # s; N Δt ≈ 0.47, see README
    "initial_dt" => 5.0,           # s
    "stop_hours" => 48.0,
    "full_field_minutes" => 60.0,
    "profile_minutes" => 5.0,
    "transect_minutes" => 5.0,
    "checkpoint_minutes" => 60.0,
    "transect_j" => 1,
    "architecture" => "GPU",
    "output_dir" => "output",
)

function parse_config(args)
    config = copy(DEFAULTS)
    for arg in args
        key, value = split(arg, "="; limit=2)
        haskey(config, key) || error("Unknown parameter $key")
        default = config[key]
        config[key] = default isa AbstractString ? String(value) : parse(typeof(default), value)
    end
    return config
end

"Remove output saved after the checkpoint being resumed, so that output is not written twice."
function truncate_output!(path, iteration)
    isfile(path) || return 0
    removed = 0
    jldopen(path, "r+") do file
        haskey(file, "timeseries") || return
        for group_name in keys(file["timeseries"])
            group = file["timeseries/$group_name"]
            for key in keys(group)
                key == "serialized" && continue
                if parse(Int, key) > iteration
                    delete!(group, key)
                    removed += 1
                end
            end
        end
    end
    return removed
end

function latest_checkpoint_iteration(dir)
    paths = filter(startswith("checkpoint_iteration"), readdir(dir))
    isempty(paths) && return nothing
    return maximum(parse(Int, match(r"iteration(\d+)", p).captures[1]) for p in paths)
end

function main(config)
    for key in sort!(collect(keys(config)))
        @info "config" key value=config[key]
    end

    dir = abspath(config["output_dir"])
    mkpath(dir)
    # Persist the fully resolved configuration; refuse to resume under a different one.
    config_path = joinpath(dir, "config.toml")
    if isfile(config_path)
        previous = TOML.parsefile(config_path)
        for key in keys(config)
            key in ("stop_hours", "output_dir") && continue
            previous[key] == config[key] || error("Config mismatch for $key: run has $(previous[key]), got $(config[key])")
        end
    end
    open(io -> TOML.print(io, config; sorted=true), config_path, "w")

    arch = config["architecture"] == "GPU" ? GPU() : CPU()
    Lx, Ly, Lz = config["Lx"], config["Ly"], config["Lz"]
    Nx, Ny, Nz = config["Nx"], config["Ny"], config["Nz"]

    grid = RectilinearGrid(arch; size=(Nx, Ny, Nz), x=(0, Lx), y=(0, Ly), z=(-Lz, 0),
                           topology=(Periodic, Periodic, Bounded))
    @info "grid" grid

    # Oceananigans boundary fluxes are positive in the +z direction (upward).
    #   Eastward stress puts +x momentum into the ocean, a downward flux: Jᵤ < 0.
    #   Heat loss carries heat upward out of the ocean:                   Jᵀ > 0.
    α, g = config["alpha"], config["g"]
    ρ₀, cp = config["rho0"], config["cp"]
    Jᵤ = -config["tau_x"] / ρ₀
    Jᵀ = config["Q_loss"] / (ρ₀ * cp)

    # Bottom: default no-flux for T and free slip (zero stress) for u, v.
    # Top and bottom w = 0 is the impenetrable default of Bounded topology.
    u_bcs = FieldBoundaryConditions(top=FluxBoundaryCondition(Jᵤ))
    T_bcs = FieldBoundaryConditions(top=FluxBoundaryCondition(Jᵀ))

    equation_of_state = LinearEquationOfState(thermal_expansion=α, haline_contraction=0)
    buoyancy = SeawaterBuoyancy(; gravitational_acceleration=g, equation_of_state, constant_salinity=35)

    closure = config["closure"] == "AMD" ? AnisotropicMinimumDissipation() :
              config["closure"] == "Smagorinsky" ? SmagorinskyLilly() :
              config["closure"] == "none" ? nothing : error("Unknown closure")

    model = NonhydrostaticModel(grid;
                                advection = WENO(order=config["weno_order"]),
                                timestepper = :RungeKutta3,
                                coriolis = FPlane(f=config["f"]),
                                tracers = :T,
                                buoyancy,
                                closure,
                                boundary_conditions = (u=u_bcs, T=T_bcs))

    h = config["mixed_layer_depth"]
    T₀ = config["T_surface"]
    dTdz = config["N2"] / (α * g)
    d = config["noise_depth"]
    A = config["noise_K"]
    T̄(z) = z > -h ? T₀ : T₀ + dTdz * (z + h)

    # Seed on the CPU from a fixed seed, so that initial noise is reproducible across architectures.
    rng = Xoshiro(config["seed"])
    noise = randn(rng, Nx, Ny, Nz)
    Δz = Lz / Nz  # CPU coordinates: never scalar-index device-backed grid arrays
    zc = [-Lz + (k - 0.5) * Δz for k in 1:Nz]
    Tᵢ = [T̄(zc[k]) + (zc[k] > -d ? A * noise[i, j, k] : 0.0) for i in 1:Nx, j in 1:Ny, k in 1:Nz]

    # Initial conditions are overwritten when picking up from a checkpoint.
    set!(model, T=Tᵢ)

    simulation = Simulation(model; Δt=config["initial_dt"], stop_time=config["stop_hours"] * hours)
    wizard = TimeStepWizard(cfl=config["cfl"], diffusive_cfl=config["diffusive_cfl"],
                            max_change=1.1, max_Δt=config["max_dt"])
    simulation.callbacks[:wizard] = Callback(wizard, IterationInterval(5))

    u, v, w = model.velocities
    T = model.tracers.T
    νₑ = model.closure === nothing ? nothing : model.closure_fields.νₑ
    κₑ = model.closure === nothing ? nothing : model.closure_fields.κₑ.T

    # Output. Float32 on disk; state on the device stays Float64.

    full_fields = (; u, v, w, T)
    simulation.output_writers[:fields] = JLD2Writer(model, full_fields;
        filename=joinpath(dir, "fields.jld2"),
        schedule=TimeInterval(config["full_field_minutes"] * minutes),
        array_type=Array{Float32}, overwrite_existing=false)

    avg(op) = Average(op, dims=(1, 2))
    profiles = (; U=avg(u), V=avg(v), T=avg(T), W=avg(w),
                uu=avg(u * u), vv=avg(v * v), ww=avg(w * w), TT=avg(T * T), wT=avg(w * T),
                uw=avg(u * w), vw=avg(v * w))
    if νₑ !== nothing
        profiles = merge(profiles, (; νₑ=avg(νₑ), κₑ=avg(κₑ)))
    end
    simulation.output_writers[:profiles] = JLD2Writer(model, profiles;
        filename=joinpath(dir, "profiles.jld2"),
        schedule=TimeInterval(config["profile_minutes"] * minutes),
        array_type=Array{Float32}, overwrite_existing=false)

    j = config["transect_j"]
    simulation.output_writers[:transect] = JLD2Writer(model, full_fields;
        filename=joinpath(dir, "xz_transect.jld2"),
        indices=(:, j, :),
        schedule=TimeInterval(config["transect_minutes"] * minutes),
        array_type=Array{Float32}, overwrite_existing=false)

    volume_mean(op) = Average(op, dims=(1, 2, 3))
    budget = (; T=volume_mean(T), u=volume_mean(u), v=volume_mean(v),
              KE=volume_mean((u * u + v * v + w * w) / 2))
    simulation.output_writers[:budget] = JLD2Writer(model, budget;
        filename=joinpath(dir, "budget.jld2"),
        schedule=TimeInterval(config["profile_minutes"] * minutes),
        array_type=Array{Float64}, overwrite_existing=false)

    simulation.output_writers[:checkpointer] = Checkpointer(model;
        dir, prefix="checkpoint",
        schedule=TimeInterval(config["checkpoint_minutes"] * minutes),
        cleanup=true)

    # Step log: one CSV row per 20 iterations, appended across restarts.
    log_path = joinpath(dir, "steps.csv")
    isfile(log_path) || write(log_path, "wall_unix,iteration,time_s,dt_s,adv_cfl,diff_cfl,max_abs_u,max_abs_v,max_abs_w,min_T,max_T\n")
    adv_cfl = AdvectiveCFL(wizard)
    diff_cfl = DiffusiveCFL(wizard)
    wall₀ = Ref(time_ns())
    function log_step(sim)
        umax, vmax, wmax = maximum(abs, interior(u)), maximum(abs, interior(v)), maximum(abs, interior(w))
        Tmin, Tmax = minimum(interior(T)), maximum(interior(T))
        all(isfinite, (umax, vmax, wmax, Tmin, Tmax)) || error("Non-finite state at iteration $(iteration(sim))")
        cfl, dcfl = adv_cfl(sim.model), diff_cfl(sim.model)
        open(log_path, "a") do io
            @printf(io, "%.3f,%d,%.3f,%.4f,%.4f,%.4f,%.5e,%.5e,%.5e,%.6f,%.6f\n", time(), iteration(sim),
                    sim.model.clock.time, sim.Δt, cfl, dcfl, umax, vmax, wmax, Tmin, Tmax)
        end
        @info @sprintf("iter %d t=%.3f h Δt=%.2f s CFL=%.3f dCFL=%.3f |u|=%.3e |w|=%.3e T=[%.4f, %.4f] wall=%.1f s",
                       iteration(sim), sim.model.clock.time / 3600, sim.Δt, cfl, dcfl, umax, wmax, Tmin, Tmax,
                       (time_ns() - wall₀[]) * 1e-9)
    end
    simulation.callbacks[:log] = Callback(log_step, IterationInterval(20))

    pickup_iteration = latest_checkpoint_iteration(dir)
    if pickup_iteration === nothing
        @info "Starting from the initial condition"
        pickup = false
    else
        for name in ("fields", "profiles", "xz_transect", "budget")
            removed = truncate_output!(joinpath(dir, name * ".jld2"), pickup_iteration)
            @info "Pickup truncation" name pickup_iteration removed
        end
        pickup = true
    end

    t₀ = time_ns()
    iter₀ = pickup_iteration === nothing ? 0 : pickup_iteration
    run!(simulation; pickup)
    elapsed = (time_ns() - t₀) * 1e-9
    steps = iteration(simulation) - iter₀
    summary = @sprintf("wall=%.1f s steps=%d mean_ms_per_step=%.1f simulated_h=%.3f stop_reason=%s",
                       elapsed, steps, 1e3 * elapsed / max(steps, 1), model.clock.time / 3600,
                       string(simulation.stop_time))
    @info "Finished run" summary iteration=iteration(simulation)
    open(joinpath(dir, "run_summary.txt"), "a") do io
        println(io, "job=", get(ENV, "SLURM_JOB_ID", "none"), " ", summary)
    end
    return simulation
end

if abspath(PROGRAM_FILE) == @__FILE__
    @info "Versions" julia=VERSION oceananigans=pkgversion(Oceananigans) cuda=pkgversion(CUDA)
    CUDA.functional() && @info "GPU" device=CUDA.name(CUDA.device())
    main(parse_config(ARGS))
end
