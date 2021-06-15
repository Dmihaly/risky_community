module RiskyCommunity

    # __precompile__(true)
    using Parameters
    using JuMP
    using AxisArrays

    include("base_structs.jl")
    include("community_agents.jl")
    include("DER_assets.jl")
    include("grid_agents.jl")
    include("opt_models.jl")

    export build_model, build_test_model, build_VAR_model, add_objective, solve_model, fix_model_variable!, read_results
    export Period, Scenario, Result, Demand, Price
    export DER_Agent, Battery
    export Battery, PV
    export Conv_Generator, Res_Generator, Load_Shed, Central_Opt, Aggregator

end # module
