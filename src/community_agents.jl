abstract type Community_Agent <: Agent end


@with_kw mutable struct DER_Agent <: Community_Agent
    name::String = "anonymus"
    location::String = "under_AGG_1"
    period::Period = Period()
    demand::Any = Demand(period = period) #Type Any was the only thing working on passing in multiple elements, to be reslved
    dev_ID::Any = Demand(period = period)
    dev_RT::Any = Demand(period = period)
    preferences::Preferences = Preferences()
    battery::Any = Battery()
    pv = PV()
    OPEX_DA::Float64 = 0.0
    OPEX_ID::Float64 = 0.0
    OPEX_RT::Float64 = 0.0
    #HERE A FUNCTION SHOULD BE ADDED TO CHECK THE SUM OF THE PROBABILITIES PER FORECAST
end
