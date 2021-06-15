@with_kw mutable struct Battery
    capacity_power::Float64 = 0.0
    capacity_energy::Float64 = 0.0
    soc_init::Float64 = 0.5
    # power::Float64 = 0.0, making the assumption that power is 1/4th of the energy
    efficiency_dch::Float64 = 0.9
    efficiency_ch::Float64 = 0.9
    CAPEXˢ::Float64 = 0.0 #per kWh energy capacity
end

@with_kw mutable struct PV
    period::Period = Period()
    load_factor_PV::Array{Float64,2} = zeros((period.number_of_days, period.number_of_t_steps))
    P_max::Float64 = 0.0
    CAPEXᴾⱽ::Float64 = 0.0 #per kW capacity
end
