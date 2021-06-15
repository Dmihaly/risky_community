abstract type Grid_Agent <: Agent end

@with_kw mutable struct Conv_Generator <: Grid_Agent
    OPEX_DA::Float64 = 0.0
    OPEX_RT::Float64 = 0.0
end

@with_kw mutable struct Res_Generator <: Grid_Agent
    attributes::Any
end

@with_kw mutable struct Load_Shed <: Grid_Agent
    VoLL::Float64
end

@with_kw mutable struct Central_Opt
    Conv_Generators::Any = Conv_Generator()
    Res_Generators::Any = Res_Generator()
end

@with_kw mutable struct Aggregator <: Grid_Agent
    name::String = "anonymus"
    battery::Any = Battery() #OWN ESS
    pv::Any = PV() #OWN PV
    connection_limit::Float64  = 0.0 #Line power limit on the aggregated exchange
    preferences::Preferences = Preferences()
    DER_agents::Any = DER_Agent()
    max_DA::Float64 = 100.0
    max_RT::Float64 = 100.0
end
