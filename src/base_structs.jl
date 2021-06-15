abstract type Agent end
#TIME
@with_kw mutable struct Period @deftype Int32
    number_of_days = 1; @assert number_of_days > 0
    number_of_t_steps = 24
    step_size::Float64 = 24 / number_of_t_steps
end

@with_kw mutable struct Scenario
    id::Any = "anyscenario"
    counter::Int64 = 1
    prob::Float64 = 1.0
end

@with_kw mutable struct Result
    period::Period = Period()
    id::Any = 1
    scenario::Scenario = Scenario() #INIT WITH A SINGLE SCENARIO
    values::Array{Float64,2} = zeros((period.number_of_days, period.number_of_t_steps))
end

abstract type Forecast end
#EVERY FORECAST TYPE BELONGS TO A SINGLE SCENARIO

@with_kw mutable struct Demand <: Forecast
    period::Period = Period()
    root::Union{Nothing,Scenario} = nothing
    id::Any = 1
    scenario::Scenario = Scenario() #INIT WITH A SINGLE SCENARIO
    values::Array{Float64,2} = zeros((period.number_of_days, period.number_of_t_steps))
end


@with_kw mutable struct Price <: Forecast
    period::Period = Period()
    root::Union{Nothing,Scenario} = nothing
    id::Any = 1
    scenario::Scenario = Scenario() #INIT WITH A SINGLE SCENARIO
    values::Array{Float64,2} = zeros((period.number_of_days, period.number_of_t_steps))
end

@with_kw mutable struct Preferences
    ϵ::Float64 = 1.0 #For the CVAR based constraints
    βᴬ::Float64 = 0.1 #adjustment param for the risk-averseness
    γᴬ::Float64 = 1.0 #tradeoff between maximizing expacted return vs risk aversion, 1.0 -> risk neutral
    bigM::Float64 = 1000.0 #Big-M value if it is needed in the model
end
