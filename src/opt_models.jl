function build_model(agent::Aggregator, period::Period, prices::Dict)
    "The model with CVAR and WCVAR constraints"
    model = agent.name
    println("Building model for $model")
    #BUILDING GENERIC MODEL
    model = Model()
    model.ext[:param] = Dict()
    model.ext[:dec_vars] = Dict()
    param = model.ext[:param]
    dec_vars = model.ext[:dec_vars]
    param[:t_steps] = t_steps = period.number_of_t_steps
    param[:step_size] = step_size = period.step_size
    param[:days] = days = period.number_of_days
    number_of_ID_dev =
        try
            number_of_ID_dev =  length(agent.DER_agents[1].dev_ID) # Number of intra-day deviation scenarios
        catch
            number_of_ID_dev = 1
        end
    number_of_RT_dev =
        try
            number_of_RT_dev =  length(agent.DER_agents[1].dev_RT) # Number of intra-day deviation scenarios
        catch
            number_of_RT_dev = 1
        end
    number_of_RT_market =
        try
            number_of_RT_market =  length(prices[:RT]) # Number of intra-day deviation scenarios
        catch
            number_of_RT_market = 1
        end
    number_of_DA_market =
        try
            number_of_DA_market =  length(prices[:DA]) # Number of intra-day deviation scenarios
        catch
            number_of_DA_market = 1
        end
    param[:scens_DA_market] = scens_DA_market = Array{String}(undef, days, t_steps, number_of_DA_market) #Day-ahead market scenario set
    param[:scens_RT_market] = scens_RT_market = Array{String}(undef, days, t_steps, number_of_DA_market, number_of_RT_market) #Real-time imbalance market scenario set
    param[:demands] = demands = Array{String}(undef, days, t_steps)
    param[:scens_ID_dev] = scens_ID_dev = Array{String}(undef, days, t_steps, number_of_ID_dev) #Intra-day DER deviation scenario set
    param[:scens_RT_dev] = scens_RT_dev = Array{String}(undef, days, t_steps, number_of_ID_dev, number_of_RT_dev)  #Real-time DER deviation scenario set
    param[:number_of_DER] = number_of_DER =  length(agent.DER_agents)
    param[:DERs] = DERs = [agent.DER_agents[j].name for j in 1:number_of_DER]
    param[:max_DA] = max_DA = agent.max_DA
    param[:max_RT] = max_RT = agent.max_RT

    # agent.DER_agents[1].dev_ID.scenario.id
    param[:π] = π = 1:number_of_ID_dev
    param[:scens_ID_dev] = scens_ID_dev = [agent.DER_agents[j].dev_ID for j in 1:number_of_DER]
    #to access scens_ID_dev[2]; where j = 2
    #IMPORTANT: USE THE COUNTER FOR THE SCENARIOS
    param[:ξ] = ξ = vec([agent.DER_agents[j].dev_RT[n].scenario.counter for j in 1:number_of_DER, n in 1:number_of_RT_dev])
    param[:scens_RT_dev] = scens_RT_dev = [agent.DER_agents[j].dev_RT for j in 1:number_of_DER]
    #Get only the unique scenario groups
    param[:group_RT_dev] = group_RT_dev = unique([agent.DER_agents[j].dev_RT[n].scenario.id for j in 1:number_of_DER, n in 1:number_of_RT_dev])
    #Ordering the scenario objects to a matrix according to the groups
    s_matrix =
    [
        filter(!isnothing,
            [if (agent.DER_agents[j].dev_RT[n].scenario.id == group_RT_dev[i]) agent.DER_agents[j].dev_RT[n] end for j in 1:number_of_DER, n in 1:number_of_RT_dev])
            for i in 1:length(group_RT_dev)
        ]
    #Sorting the counters in a matrix along the same vein as above, but now using AxisArray
    scen_matrix =
    AxisArray(
       [
        [s_matrix[m][n].scenario.counter for n in 1:length(s_matrix[m])]
        for m in 1:length(group_RT_dev)
        ],
       Axis{:Scen_IDs}(group_RT_dev)
    )

    # scen_matrix["RTdev_scen_group2"]    #to access the scenarios belinging to group 2


    param[:ζ] = ζ = 1:number_of_DA_market
    param[:scens_DA_market] = scens_DA_market = prices[:DA]
    #to access scens_DA_market

    param[:θ] = θ = 1:number_of_RT_market
    param[:scens_RT_market] = scens_RT_market = prices[:RT]
    #to access scens_RT_market scens_RT_market[3]; where s =3

    param[:demands] = demands = [agent.DER_agents[j].demand for j in 1:number_of_DER]
    #to access e.g. demands[2].values; where j = 2
    #Currently all operational costs are for the agents controlled by the aggregator
    param[:OPEX_DA] = OPEX_DA = [agent.DER_agents[j].OPEX_DA for j in 1:number_of_DER]
    param[:OPEX_ID] = OPEX_ID = [agent.DER_agents[j].OPEX_ID for j in 1:number_of_DER]
    param[:OPEX_RT] = OPEX_RT = [agent.DER_agents[j].OPEX_RT for j in 1:number_of_DER]

    param[:η_ch] = η_ch = [agent.DER_agents[j].battery.efficiency_ch for j in 1:number_of_DER]
    param[:η_dch] = η_dch = [agent.DER_agents[j].battery.efficiency_dch for j in 1:number_of_DER]
    param[:capₚ] = capₚ = [agent.DER_agents[j].battery.capacity_power for j in 1:number_of_DER]
    param[:capsₑ] = capsₑ = [agent.DER_agents[j].battery.capacity_energy for j in 1:number_of_DER]
    param[:initₑ] = initₑ = [agent.DER_agents[j].battery.soc_init for j in 1:number_of_DER]

    #Associated with the aggregator's risk-attitude:
    param[:βᴬ] = βᴬ = agent.preferences.βᴬ #adjustment param for the risk-averseness
    param[:γᴬ] = γᴬ = agent.preferences.γᴬ #tradeoff between maximizing expacted return vs risk aversion, 1.0 -> risk neutral
    param[:ϵ] = ϵ = agent.preferences.ϵ  #adjustment param for the risk-averseness

    param[:ϵ_power] = ϵ_power = agent.preferences.ϵ #possibility to vary for the power limits

    param[:coeff_CVaR] = coeff_CVaR = 1.00  #adjustment param for the risk-averseness


    #############THE MAIN DECISION VARIABLES########
    #NOTE: IT WOULD BE EASIER TO FIX VARS IF THEY WERE CATEGORIZED
    dec_vars[:aᴰᴬ] = @variable(model,
        - max_DA <= aᴰᴬ[d in 1:days, t in 1:t_steps] <= max_DA) #NOTE#Energy exchanged day-ahead
    dec_vars[:aᴿᵀ] = @variable(model,
        - max_RT <=  aᴿᵀ[d in 1:days, t in 1:t_steps, θ in θ] <= max_RT) #NOTE Only buying is allowed for the sake of the case study to avoid virtual bidding too much. #Energy exchanged real-time
    dec_vars[:fᴰᴬ] = @variable(model,
        fᴰᴬ[j in 1:number_of_DER, d in 1:days, t in 1:t_steps]) #Flexibility exchanged between the aggregator and the DERs day-ahead
    dec_vars[:fᴵᴰ] = @variable(model,
        0 == fᴵᴰ[j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π]) #Flexibility exchanged between the aggregator and the DERs intra-day
    dec_vars[:fᴿᵀ] = @variable(model,
        fᴿᵀ[j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π, ξ in ξ, θ in θ]) #Flexibility exchanged between the aggregator and the DERs real-time
    dec_vars[:chᴰᴬ] = @variable(model,
        0 <= chᴰᴬ[j in 1:number_of_DER, d in 1:days, t in 1:t_steps] <=  capₚ[j]) #Scheduling charging of the DERs day-ahead
    # dec_vars[:bᴰᴬ] = @variable(model,
    #     bᴰᴬ[j in 1:number_of_DER, d in 1:days, t in 1:t_steps], Bin) #Binary for dch/charging of the DERs day-ahead
    dec_vars[:chᴵᴰ] = @variable(model,
        0 == chᴵᴰ[j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π]) #Scheduling charging of the DERs intra-day
    # dec_vars[:bᴵᴰ] = @variable(model,
    #     bᴵᴰ[j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π], Bin) #Binary for dch/charging of the DERs intra-day
    dec_vars[:chᴿᵀ] = @variable(model,
        0 <= chᴿᵀ[j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π, ξ in ξ, θ in θ]) #Scheduling charging of the DERs real-time
    # dec_vars[:bᴿᵀ] = @variable(model,
    #     bᴿᵀ[j in 1:number_of_DER, d in 1:days, t in 1:t_steps, ξ in ξ, θ in θ], Bin) #Binary for dch/charging of the DERs real-time
    dec_vars[:dchᴰᴬ] = @variable(model,
        0 <= dchᴰᴬ[j in 1:number_of_DER, d in 1:days, t in 1:t_steps] <=  capₚ[j]) #Scheduling discharging of the DERs day-ahead
    dec_vars[:dchᴵᴰ] = @variable(model,
        0 == dchᴵᴰ[j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π]) #Scheduling discharging of the DERs intra-day
    dec_vars[:dchᴿᵀ] = @variable(model,
        0 <= dchᴿᵀ[j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π, ξ in ξ, θ in θ]) #Scheduling discharging of the DERs real-time
    dec_vars[:soc] = @variable(model,
        -10*capsₑ[j] <= soc[j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π, ξ in ξ, θ in θ] <= 10*capsₑ[j]) #NOTE #Scheduling state-of-charge of the DERs real-time

    #Pobabilistic constraint related
    dec_vars[:η_upper] = @variable(model,
        η_upper[j in 1:number_of_DER, d in 1:days, t in 1:t_steps, gr in group_RT_dev])
    dec_vars[:δ_upper] = @variable(model,
        0 <= δ_upper[j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π, ξ in ξ, θ in θ, gr in group_RT_dev; ξ ∈ scen_matrix[gr]])
    # dec_vars[:WCVaR_upper] = @variable(model,
    #     WCVaR_upper[j in 1:number_of_DER, d in 1:days, t in 1:t_steps])

    # dec_vars[:η_upper_ch] = @variable(model,
    #     η_upper_ch[j in 1:number_of_DER, d in 1:days, t in 1:t_steps, gr in group_RT_dev])
    # dec_vars[:δ_upper_ch] = @variable(model,
    #     0 <= δ_upper_ch[j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π, ξ in ξ, θ in θ, gr in group_RT_dev; ξ ∈ scen_matrix[gr]])
    # dec_vars[:η_lower_ch] = @variable(model,
    #     η_lower_ch[j in 1:number_of_DER, d in 1:days, t in 1:t_steps, gr in group_RT_dev])
    # dec_vars[:δ_lower_ch] = @variable(model,
    #     0 <= δ_lower_ch[j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π, ξ in ξ, θ in θ, gr in group_RT_dev; ξ ∈ scen_matrix[gr]])

    #
    # dec_vars[:η_balance_up] = @variable(model,
    #     η_balance_up[d in 1:days,t in 1:t_steps, gr in group_RT_dev])
    # dec_vars[:η_balance_down] = @variable(model,
    #     η_balance_down[d in 1:days,t in 1:t_steps, gr in group_RT_dev])
    # #
    # dec_vars[:δ_balance_up] = @variable(model,
    #     0 <= δ_balance_up[d in 1:days, t in 1:t_steps, π in π, ξ in ξ, θ in θ, gr in group_RT_dev; ξ ∈ scen_matrix[gr]])
    # dec_vars[:δ_balance_down] = @variable(model,
    #     0 <= δ_balance_down[d in 1:days, t in 1:t_steps, π in π, ξ in ξ, θ in θ, gr in group_RT_dev; ξ ∈ scen_matrix[gr]])



    # dec_vars[:WCVaR_upper_ch] = @variable(model,
    #     WCVaR_upper_ch[j in 1:number_of_DER, d in 1:days, t in 1:t_steps])

    # dec_vars[:η_upper_dch] = @variable(model,
    #     η_upper_dch[j in 1:number_of_DER, d in 1:days, t in 1:t_steps, gr in group_RT_dev])
    # dec_vars[:δ_upper_dch] = @variable(model,
    #     0 <= δ_upper_dch[j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π, ξ in ξ, θ in θ, gr in group_RT_dev; ξ ∈ scen_matrix[gr]])

    # dec_vars[:η_lower_dch] = @variable(model,
    #     η_lower_dch[j in 1:number_of_DER, d in 1:days, t in 1:t_steps, gr in group_RT_dev])
    # dec_vars[:δ_lower_dch] = @variable(model,
    #     0 <= δ_lower_dch[j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π, ξ in ξ, θ in θ, gr in group_RT_dev; ξ ∈ scen_matrix[gr]])
    # dec_vars[:WCVaR_upper_dch] = @variable(model,
    #     WCVaR_upper_dch[j in 1:number_of_DER, d in 1:days, t in 1:t_steps])

    dec_vars[:η_lower] = @variable(model,
        η_lower[j in 1:number_of_DER, d in 1:days, t in 1:t_steps, gr in group_RT_dev])
    dec_vars[:δ_lower] = @variable(model,
        0 <= δ_lower[j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π, ξ in ξ, θ in θ, gr in group_RT_dev; ξ ∈ scen_matrix[gr]])

    # dec_vars[:CVAR_soc_upper] = @variable(model,
    #     CVAR_soc_upper[j in 1:number_of_DER, d in 1:days, t in 1:t_steps, gr in group_RT_dev])
    # dec_vars[:CVAR_soc_lower] = @variable(model,
    #     CVAR_soc_lower[j in 1:number_of_DER, d in 1:days, t in 1:t_steps, gr in group_RT_dev])
    # dec_vars[:CVAR_ch_upper] = @variable(model,
    #     CVAR_ch_upper[j in 1:number_of_DER, d in 1:days, t in 1:t_steps, gr in group_RT_dev])
    # dec_vars[:CVAR_dch_upper] = @variable(model,
    #     CVAR_dch_upper[j in 1:number_of_DER, d in 1:days, t in 1:t_steps, gr in group_RT_dev])
    #
    # dec_vars[:WCVaR_lower] = @variable(model,
    #     WCVaR_lower[j in 1:number_of_DER, d in 1:days, t in 1:t_steps])
    #
    # dec_vars[:η_lower_ch] = @variable(model,
    #     η_lower_ch[j in 1:number_of_DER, d in 1:days, t in 1:t_steps, gr in group_RT_dev])
    # dec_vars[:δ_lower_ch] = @variable(model,
    #     0 <= δ_lower_ch[j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π, ξ in ξ, θ in θ, gr in group_RT_dev; ξ ∈ scen_matrix[gr]])
    # dec_vars[:WCVaR_lower_ch] = @variable(model,
    #     WCVaR_lower_ch[j in 1:number_of_DER, d in 1:days, t in 1:t_steps])
    #
    # dec_vars[:η_lower_dch] = @variable(model,
    #     η_lower_dch[j in 1:number_of_DER, d in 1:days, t in 1:t_steps, gr in group_RT_dev])
    # dec_vars[:δ_lower_dch] = @variable(model,
    #     0 <= δ_lower_dch[j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π, ξ in ξ, θ in θ, gr in group_RT_dev; ξ ∈ scen_matrix[gr]])
    # dec_vars[:WCVaR_lower_dch] = @variable(model,
    #     WCVaR_lower_dch[j in 1:number_of_DER, d in 1:days, t in 1:t_steps])

    # dec_vars[:viol_upper] = @variable(model,
    #     0 <= viol_upper[j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π, ξ in ξ, θ in θ])
    # dec_vars[:viol_lower] = @variable(model,
    #     0 <= viol_lower[j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π, ξ in ξ, θ in θ])

    ##################EXPRESSIONS##############
    model[:cost_DA_market] = cost_DA_market = @expression(model, [d in 1:days, t in 1:t_steps],
        scens_DA_market.scenario.prob .* (scens_DA_market.values[d,t] .* aᴰᴬ[d,t])) #Single DA scenario
    model[:cost_DA_DERs] = cost_DA_DERs = @expression(model, [j in 1:number_of_DER, d in 1:days, t in 1:t_steps],
        OPEX_DA[j] .* (dchᴰᴬ[j,d,t] + chᴰᴬ[j,d,t]))
    model[:cost_ID_DERs] = cost_ID_DERs = @expression(model, [j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π],
        scens_ID_dev[j][π].scenario.prob .* OPEX_ID[j] .* (dchᴵᴰ[j,d,t,π] + chᴵᴰ[j,d,t,π]))
    model[:cost_RT_market] = cost_RT_market = @expression(model, [d in 1:days, t in 1:t_steps, θ in θ],
        scens_RT_market[θ].scenario.prob .* (scens_RT_market[θ].values[d,t].* aᴿᵀ[d,t,θ]))
    model[:cost_RT_DERs] = cost_RT_DERs = @expression(model, [j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π, ξ in ξ, θ in θ],
        scens_RT_dev[j][ξ].scenario.prob .* OPEX_RT[j] .* (dchᴿᵀ[j,d,t,π,ξ,θ] + chᴿᵀ[j,d,t,π,ξ,θ]))
    #Cost of violation
    model[:cost_violation_upper] = cost_violation_upper =  0
    # cost_violation_upper = @expression(model, [j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π, ξ in ξ,  θ in θ],
    #     scens_RT_market[θ].scenario.prob .* scens_ID_dev[j][π].scenario.prob .* scens_RT_dev[j][ξ].scenario.prob .* (scens_RT_market[θ].values[d,t] .* viol_upper[j,d,t,π,ξ,θ]))
    # model[:qdr_cost_violation_upper] = qdr_cost_violation_upper = [
    #     @expression(model, scens_RT_market[θ].scenario.prob .* scens_ID_dev[j][π].scenario.prob .* scens_RT_dev[j][ξ].scenario.prob .* (scens_RT_market[θ].values[d,t] .* viol_upper[j,d,t,π,ξ,θ])^2)
    #     for j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π, ξ in ξ,  θ in θ
    # ]
    model[:cost_violation_lower] = cost_violation_lower =  0
    # cost_violation_lower = @expression(model, [j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π, ξ in ξ,  θ in θ],
    #     scens_RT_market[θ].scenario.prob .* scens_ID_dev[j][π].scenario.prob .* scens_RT_dev[j][ξ].scenario.prob .* (scens_RT_market[θ].values[d,t] .* viol_lower[j,d,t,π,ξ,θ]))
    # model[:qdr_cost_violation_lower] = qdr_cost_violation_lower = [
    #     @expression(model, scens_RT_market[θ].scenario.prob .* scens_ID_dev[j][π].scenario.prob .* scens_RT_dev[j][ξ].scenario.prob .* (scens_RT_market[θ].values[d,t] .* viol_lower[j,d,t,π,ξ,θ])^2)
    #     for j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π, ξ in ξ,  θ in θ
    # ]
    # @expression(model, [j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π, ξ in ξ,  θ in θ],
    #     scens_RT_market[θ].scenario.prob .* (scens_RT_market[θ].values[d,t] .* viol[j,d,t,π,ξ,θ])^2)
    # CVAR related:
    model[:CVAR_soc_upper] = CVAR_soc_upper = @expression(model, [j in 1:number_of_DER, d in 1:days, t in 1:t_steps, gr in group_RT_dev],
        η_upper[j,d,t,gr] + (1/(ϵ/length(group_RT_dev))) .* sum(scens_RT_market[θ].scenario.prob .* scens_ID_dev[j][π].scenario.prob .* scens_RT_dev[j][ξ].scenario.prob .* δ_upper[j,d,t,π,ξ,θ,gr] for π in π, ξ in ξ, θ in θ if ξ ∈ scen_matrix[gr]))
    model[:CVAR_soc_lower] = CVAR_soc_lower = @expression(model, [j in 1:number_of_DER, d in 1:days, t in 1:t_steps, gr in group_RT_dev],
        η_lower[j,d,t,gr] - (1/(ϵ/length(group_RT_dev))) .* sum(scens_RT_market[θ].scenario.prob .* scens_ID_dev[j][π].scenario.prob .* scens_RT_dev[j][ξ].scenario.prob .* δ_lower[j,d,t,π,ξ,θ,gr] for π in π, ξ in ξ, θ in θ if ξ ∈ scen_matrix[gr]))


    # model[:CVAR_ch_upper] = CVAR_ch_upper = @expression(model, [j in 1:number_of_DER, d in 1:days, t in 1:t_steps, gr in group_RT_dev],
    #     η_upper_ch[j,d,t,gr] + (1/(ϵ_power/length(group_RT_dev))) .* sum(scens_RT_market[θ].scenario.prob .* scens_ID_dev[j][π].scenario.prob .* scens_RT_dev[j][ξ].scenario.prob .* δ_upper_ch[j,d,t,π,ξ,θ,gr] for π in π, ξ in ξ, θ in θ if ξ ∈ scen_matrix[gr]))
    # model[:CVAR_dch_upper] = CVAR_dch_upper = @expression(model, [j in 1:number_of_DER, d in 1:days, t in 1:t_steps, gr in group_RT_dev],
    #     η_upper_dch[j,d,t,gr] + (1/(ϵ_power/length(group_RT_dev))) .* sum(scens_RT_market[θ].scenario.prob .* scens_ID_dev[j][π].scenario.prob .* scens_RT_dev[j][ξ].scenario.prob .* δ_upper_dch[j,d,t,π,ξ,θ,gr] for π in π, ξ in ξ, θ in θ if ξ ∈ scen_matrix[gr]))

    # model[:CVAR_ch_lower] = CVAR_ch_lower = @expression(model, [j in 1:number_of_DER, d in 1:days, t in 1:t_steps, gr in group_RT_dev],
    #     η_lower_ch[j,d,t,gr] - (1/(ϵ_power/length(group_RT_dev))) .* sum(scens_RT_market[θ].scenario.prob .* scens_ID_dev[j][π].scenario.prob .* scens_RT_dev[j][ξ].scenario.prob .* δ_lower_ch[j,d,t,π,ξ,θ,gr] for π in π, ξ in ξ, θ in θ if ξ ∈ scen_matrix[gr]))
    # model[:CVAR_dch_lower] = CVAR_dch_lower = @expression(model, [j in 1:number_of_DER, d in 1:days, t in 1:t_steps, gr in group_RT_dev],
    #     η_lower_dch[j,d,t,gr] - (1/(ϵ_power/length(group_RT_dev))) .* sum(scens_RT_market[θ].scenario.prob .* scens_ID_dev[j][π].scenario.prob .* scens_RT_dev[j][ξ].scenario.prob .* δ_lower_dch[j,d,t,π,ξ,θ,gr] for π in π, ξ in ξ, θ in θ if ξ ∈ scen_matrix[gr]))

    # model[:CVAR_balance_up] = CVAR_balance_up = @expression(model, [d in 1:days, t in 1:t_steps, gr in group_RT_dev],
    #     η_balance_up[d,t,gr] + (1/(ϵ_power/length(group_RT_dev))) .* sum(scens_RT_market[θ].scenario.prob .* scens_ID_dev[1][π].scenario.prob .* scens_RT_dev[1][ξ].scenario.prob .* δ_balance_up[d,t,π,ξ,θ,gr] for π in π, ξ in ξ, θ in θ if ξ ∈ scen_matrix[gr]))
    # model[:CVAR_balance_down] = CVAR_balance_down = @expression(model, [d in 1:days, t in 1:t_steps, gr in group_RT_dev],
    #     η_balance_down[d,t,gr] - (1/(ϵ_power/length(group_RT_dev))) .* sum(scens_RT_market[θ].scenario.prob .* scens_ID_dev[1][π].scenario.prob .* scens_RT_dev[1][ξ].scenario.prob .* δ_balance_down[d,t,π,ξ,θ,gr] for π in π, ξ in ξ, θ in θ if ξ ∈ scen_matrix[gr]))

    # model[:CVAR_balance_lower] = CVAR_balance_lower = @expression(model, [d in 1:days, t in 1:t_steps, gr in group_RT_dev],
    #     η_lower_balance[d,t,gr] + (1/(ϵ_power/length(group_RT_dev))) .* sum(scens_RT_market[θ].scenario.prob .* scens_ID_dev[j][π].scenario.prob .* scens_RT_dev[j][ξ].scenario.prob .* δ_lower_balance[d,t,π,ξ,θ,gr] for π in π, ξ in ξ, θ in θ if ξ ∈ scen_matrix[gr]))
    # model[:CVAR_ch_lower] = CVAR_ch_lower = @expression(model, [j in 1:number_of_DER, d in 1:days, t in 1:t_steps, gr in group_RT_dev],
    #     η_lower_ch[j,d,t,gr] - (1/(ϵ_power/length(group_RT_dev))) .* sum(scens_RT_market[θ].scenario.prob .* scens_ID_dev[j][π].scenario.prob .* scens_RT_dev[j][ξ].scenario.prob .* δ_lower_ch[j,d,t,π,ξ,θ,gr] for π in π, ξ in ξ, θ in θ if ξ ∈ scen_matrix[gr]))
    # model[:CVAR_dch_lower] = CVAR_dch_lower = @expression(model, [j in 1:number_of_DER, d in 1:days, t in 1:t_steps, gr in group_RT_dev],
    #     η_lower_dch[j,d,t,gr] - (1/(ϵ_power/length(group_RT_dev))) .* sum(scens_RT_market[θ].scenario.prob .* scens_ID_dev[j][π].scenario.prob .* scens_RT_dev[j][ξ].scenario.prob .* δ_lower_dch[j,d,t,π,ξ,θ,gr] for π in π, ξ in ξ, θ in θ if ξ ∈ scen_matrix[gr]))
    #

    model[:cost_AGG] = cost_AGG = @expression(model,
            sum(cost_DA_market[d,t] for d in 1:days, t in 1:t_steps)
        +   sum(cost_DA_DERs[j,d,t] for j in 1:number_of_DER, d in 1:days, t in 1:t_steps)
        +   sum(cost_ID_DERs[j,d,t,π] for j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π)
        +   sum(cost_RT_market[d,t,θ] for d in 1:days, t in 1:t_steps, θ in θ)
        +   sum(cost_RT_DERs[j,d,t,π,ξ,θ] for j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π, ξ in ξ, θ in θ)
    )

    @objective(model, Min, cost_AGG)

    penalty_term = [] # for ADMM

    model[:energy_balance] = energy_balance = @expression(model, [d in 1:days, t in 1:t_steps, π in π, ξ in ξ, θ in θ], sum(fᴰᴬ[j,d,t] + fᴵᴰ[j,d,t,π] + fᴿᵀ[j,d,t,π,ξ,θ] - demands[j].values[d,t] - scens_RT_dev[j][ξ].values[d,t] - scens_ID_dev[j][π].values[d,t]
    for j in 1:number_of_DER) + aᴰᴬ[d,t] + aᴿᵀ[d,t,θ])
    #Better force it to hold for each stage, otherwise weird behaviour might be present
    model[:energy_balance_DA] = energy_balance_DA = @expression(model, [d in 1:days, t in 1:t_steps], sum(fᴰᴬ[j,d,t] - demands[j].values[d,t] for j in 1:number_of_DER) + aᴰᴬ[d,t])
    model[:energy_balance_ID] = energy_balance_ID = @expression(model, [d in 1:days, t in 1:t_steps, π in π], sum(fᴵᴰ[j,d,t,π] - scens_ID_dev[j][π].values[d,t] for j in 1:number_of_DER))
    model[:energy_balance_RT] = energy_balance_RT = @expression(model, [d in 1:days, t in 1:t_steps, π in π, ξ in ξ, θ in θ], sum(fᴿᵀ[j,d,t,π,ξ,θ] - scens_RT_dev[j][ξ].values[d,t] for j in 1:number_of_DER) + aᴿᵀ[d,t,θ])

    @constraints(model, begin
        #Deinition of CVaRs
            # [j in 1:number_of_DER, d in 1:days, t in 1:t_steps, gr in group_RT_dev], CVAR_soc_upper == η_upper[j,d,t,gr], + (1/(ϵ/length(group_RT_dev))) .* sum(scens_RT_market[θ].scenario.prob .* scens_ID_dev[j][π].scenario.prob .* scens_RT_dev[j][ξ].scenario.prob .* δ_upper[j,d,t,π,ξ,θ,gr] for π in π, ξ in ξ, θ in θ if ξ ∈ scen_matrix[gr]))
            # [j in 1:number_of_DER, d in 1:days, t in 1:t_steps, gr in group_RT_dev], CVAR_ch_upper == η_upper_ch[j,d,t,gr], + (1/(ϵ_power/length(group_RT_dev))) .* sum(scens_RT_market[θ].scenario.prob .* scens_ID_dev[j][π].scenario.prob .* scens_RT_dev[j][ξ].scenario.prob .* δ_upper_ch[j,d,t,π,ξ,θ,gr] for π in π, ξ in ξ, θ in θ if ξ ∈ scen_matrix[gr]))
            # [j in 1:number_of_DER, d in 1:days, t in 1:t_steps, gr in group_RT_dev], CVAR_dch_upper == η_upper_dch[j,d,t,gr], + (1/(ϵ_power/length(group_RT_dev))) .* sum(scens_RT_market[θ].scenario.prob .* scens_ID_dev[j][π].scenario.prob .* scens_RT_dev[j][ξ].scenario.prob .* δ_upper_dch[j,d,t,π,ξ,θ,gr] for π in π, ξ in ξ, θ in θ if ξ ∈ scen_matrix[gr]))
            #
            # [j in 1:number_of_DER, d in 1:days, t in 1:t_steps, gr in group_RT_dev], CVAR_soc_lower == η_lower[j,d,t,gr], - (1/(ϵ/length(group_RT_dev))) .* sum(scens_RT_market[θ].scenario.prob .* scens_ID_dev[j][π].scenario.prob .* scens_RT_dev[j][ξ].scenario.prob .* δ_lower[j,d,t,π,ξ,θ,gr] for π in π, ξ in ξ, θ in θ if ξ ∈ scen_matrix[gr]))
            # [j in 1:number_of_DER, d in 1:days, t in 1:t_steps, gr in group_RT_dev], CVAR_ch_lower =
            #     η_lower_ch[j,d,t,gr] - (1/(ϵ_power/length(group_RT_dev))) .* sum(scens_RT_market[θ].scenario.prob .* scens_ID_dev[j][π].scenario.prob .* scens_RT_dev[j][ξ].scenario.prob .* δ_lower_ch[j,d,t,π,ξ,θ,gr] for π in π, ξ in ξ, θ in θ if ξ ∈ scen_matrix[gr])
            # [j in 1:number_of_DER, d in 1:days, t in 1:t_steps, gr in group_RT_dev], CVAR_dch_lower =
            #     η_lower_dch[j,d,t,gr] - (1/(ϵ_power/length(group_RT_dev))) .* sum(scens_RT_market[θ].scenario.prob .* scens_ID_dev[j][π].scenario.prob .* scens_RT_dev[j][ξ].scenario.prob .* δ_lower_dch[j,d,t,π,ξ,θ,gr] for π in π, ξ in ξ, θ in θ if ξ ∈ scen_matrix[gr])
            #

        #CVAR related:
            [j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π, ξ in ξ, θ in θ, gr in group_RT_dev; ξ ∈ scen_matrix[gr]], δ_upper[j,d,t,π,ξ,θ,gr] >= + soc[j,d,t,π,ξ,θ] - η_upper[j,d,t,gr]
            # [d in 1:days, t in 1:t_steps, π in π, ξ in ξ, θ in θ, gr in group_RT_dev; ξ ∈ scen_matrix[gr]], δ_balance_up[d,t,π,ξ,θ,gr] >= + energy_balance[d,t,π,ξ,θ] - η_balance_up[d,t,gr]
            # [j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π, ξ in ξ, θ in θ, gr in group_RT_dev; ξ ∈ scen_matrix[gr]], δ_upper_dch[j,d,t,π,ξ,θ,gr] >=  (dchᴰᴬ[j,d,t] + dchᴵᴰ[j,d,t,π] + dchᴿᵀ[j,d,t,π,ξ,θ]) - η_upper_dch[j,d,t,gr]
            # [j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π, ξ in ξ, θ in θ, gr in group_RT_dev; ξ ∈ scen_matrix[gr]], δ_upper_dch[j,d,t,π,ξ,θ,gr] >=  (chᴰᴬ[j,d,t] + chᴵᴰ[j,d,t,π] + chᴿᵀ[j,d,t,π,ξ,θ]) - η_upper_dch[j,d,t,gr]

            # [j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π, ξ in ξ, θ in θ, gr in group_RT_dev; ξ ∈ scen_matrix[gr]], δ_lower_dch[j,d,t,π,ξ,θ,gr] >= - (dchᴰᴬ[j,d,t] + dchᴵᴰ[j,d,t,π] + dchᴿᵀ[j,d,t,π,ξ,θ]) + η_lower_dch[j,d,t,gr]
            # [j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π, ξ in ξ, θ in θ, gr in group_RT_dev; ξ ∈ scen_matrix[gr]], δ_lower_ch[j,d,t,π,ξ,θ,gr] >= - (chᴰᴬ[j,d,t] + chᴵᴰ[j,d,t,π] + chᴿᵀ[j,d,t,π,ξ,θ]) + η_lower_ch[j,d,t,gr]


            [j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π, ξ in ξ, θ in θ, gr in group_RT_dev; ξ ∈ scen_matrix[gr]], δ_lower[j,d,t,π,ξ,θ,gr] >= - soc[j,d,t,π,ξ,θ] + η_lower[j,d,t,gr]
            # [d in 1:days, t in 1:t_steps, π in π, ξ in ξ, θ in θ, gr in group_RT_dev; ξ ∈ scen_matrix[gr]], δ_balance_down[d,t,π,ξ,θ,gr] >= - energy_balance[d,t,π,ξ,θ] + η_balance_down[d,t,gr]
            # [j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π, ξ in ξ, θ in θ, gr in group_RT_dev; ξ ∈ scen_matrix[gr]], δ_lower_dch[j,d,t,π,ξ,θ,gr] >= - (dchᴰᴬ[j,d,t] + dchᴵᴰ[j,d,t,π] + dchᴿᵀ[j,d,t,π,ξ,θ]) + η_lower_dch[j,d,t,gr]




            [j in 1:number_of_DER, d in 1:days, t in 1:t_steps, gr in group_RT_dev], CVAR_soc_upper[j,d,t,gr] <= capsₑ[j]
            [j in 1:number_of_DER, d in 1:days, t in 1:t_steps, gr in group_RT_dev], CVAR_soc_lower[j,d,t,gr] >= 0

            # [d in 1:days, t in 1:t_steps, gr in group_RT_dev], CVAR_balance_up[d,t,gr] <= 0.0001
            # [d in 1:days, t in 1:t_steps, gr in group_RT_dev], CVAR_balance_up[d,t,gr] >= -10e-6
            # [d in 1:days, t in 1:t_steps, gr in group_RT_dev], CVAR_balance_down[d,t,gr] <= 10e-6
            # [d in 1:days, t in 1:t_steps, gr in group_RT_dev], CVAR_balance_down[d,t,gr] >= -0.0001

            # [j in 1:number_of_DER, d in 1:days, t in 1:t_steps, gr in group_RT_dev], CVAR_ch_upper[j,d,t,gr] <= capₚ[j]
            # [j in 1:number_of_DER, d in 1:days, t in 1:t_steps, gr in group_RT_dev], CVAR_ch_lower[j,d,t,gr] >= 0

            # [j in 1:number_of_DER, d in 1:days, t in 1:t_steps, gr in group_RT_dev], CVAR_dch_upper[j,d,t,gr] <= capₚ[j]
            # [j in 1:number_of_DER, d in 1:days, t in 1:t_steps, gr in group_RT_dev], CVAR_dch_lower[j,d,t,gr] >= 0

        #To get the violation
            # [j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π, ξ in ξ, θ in θ], viol_upper[j,d,t,π,ξ,θ] >= soc[j,d,t,π,ξ,θ] - capsₑ[j]
            # [j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π, ξ in ξ, θ in θ], viol_lower[j,d,t,π,ξ,θ] >= 0 - soc[j,d,t,π,ξ,θ]
        # #Day-ahead balance
            #For the community:
            # [d in 1:days, t in 1:t_steps], energy_balance_DA[d,t] == 0
            #For the agents:
            [j in 1:number_of_DER, d in 1:days, t in 1:t_steps], fᴰᴬ[j,d,t] == dchᴰᴬ[j,d,t] - chᴰᴬ[j,d,t]
        #Intra-day balance
            #For the community:
            # [d in 1:days, t in 1:t_steps, π in π], energy_balance_ID[d,t,π] == 0
            #For the agents:
            [j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π], fᴵᴰ[j,d,t,π] == dchᴵᴰ[j,d,t,π] - chᴵᴰ[j,d,t,π]
        #Real-time balance
            #For the community:
            # [d in 1:days, t in 1:t_steps, ξ in ξ, θ in θ], energy_balance_RT[d,t,ξ,θ] == 0
            #option B
            [d in 1:days, t in 1:t_steps, π in π, ξ in ξ, θ in θ], energy_balance[d,t,π,ξ,θ] == 0
            #For the agents:
            [j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π, ξ in ξ, θ in θ], fᴿᵀ[j,d,t,π,ξ,θ] == dchᴿᵀ[j,d,t,π,ξ,θ] - chᴿᵀ[j,d,t,π,ξ,θ]
        #DER battery related ones
            [j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π, ξ in ξ, θ in θ], dchᴰᴬ[j,d,t] + dchᴵᴰ[j,d,t,π] + dchᴿᵀ[j,d,t,π,ξ,θ] <= capₚ[j]
            [j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π, ξ in ξ, θ in θ], chᴰᴬ[j,d,t] + chᴵᴰ[j,d,t,π] + chᴿᵀ[j,d,t,π,ξ,θ] <= capₚ[j]
            # [j in 1:number_of_DER, d in 1:days, t = 1, π in π, ξ in ξ, θ in θ], soc[j,d,t,π,ξ,θ] == initₑ[j] * capsₑ[j]
            #The binaries for avoinding simoultanious ch/dch, if not needed just comment them out with the variables;
            #might be good to ex-post validate if it was happening by checking the obj with and without
            # [j in 1:number_of_DER, d in 1:days, t = 1:t_steps], bᴰᴬ[j,d,t] * chᴰᴬ[j,d,t] == 0
            # [j in 1:number_of_DER, d in 1:days, t = 1:t_steps], (1 - bᴰᴬ[j,d,t]) * dchᴰᴬ[j,d,t] == 0
            #
            # [j in 1:number_of_DER, d in 1:days, t = 1:t_steps, π in π], bᴵᴰ[j,d,t,π] * chᴵᴰ[j,d,t,π] == 0
            # [j in 1:number_of_DER, d in 1:days, t = 1:t_steps, π in π], (1 - bᴵᴰ[j,d,t,π]) * dchᴵᴰ[j,d,t,π]  == 0
            #
            # [j in 1:number_of_DER, d in 1:days, t = 1:t_steps, ξ in ξ, θ in θ], bᴿᵀ[j,d,t,ξ,θ] * chᴿᵀ[j,d,t,ξ,θ] == 0
            # [j in 1:number_of_DER, d in 1:days, t = 1:t_steps, ξ in ξ, θ in θ], (1 - bᴿᵀ[j,d,t,ξ,θ]) * dchᴿᵀ[j,d,t,ξ,θ] == 0

            # # #Cyclic boundary conditions
            # #DA
            # [j in 1:number_of_DER, d in 1:days, t in 2:t_steps], soc_DA[j,d,t]  == soc_DA[j,d,t-1] + (chᴰᴬ[j,d,t]) .* step_size .* η_ch[j] - (dchᴰᴬ[j,d,t] .* step_size ./ η_dch[j])
            # [j in 1:number_of_DER, d in 1:days, t = 1], soc_DA[j,d,t]  == soc_DA[j,d,end] + (chᴰᴬ[j,d,t]).* step_size  .* η_ch[j] - (dchᴰᴬ[j,d,t] .* step_size ./ η_dch[j])
            # #ID
            # [j in 1:number_of_DER, d in 1:days, t in 2:t_steps, π in π], soc_ID[j,d,t,π]  == soc_ID[j,d,t-1,π] + (chᴰᴬ[j,d,t] + chᴵᴰ[j,d,t,π]) .* step_size .* η_ch[j] - ((dchᴰᴬ[j,d,t] + dchᴵᴰ[j,d,t,π]) .* step_size ./ η_dch[j])
            # [j in 1:number_of_DER, d in 1:days, t = 1, π in π], soc_ID[j,d,t,π]  == soc_ID[j,d,end,π] + (chᴰᴬ[j,d,t] + chᴵᴰ[j,d,t,π]).* step_size  .* η_ch[j] - ((dchᴰᴬ[j,d,t] + dchᴵᴰ[j,d,t,π]) .* step_size ./ η_dch[j])
            #RT
            [j in 1:number_of_DER, d in 1:days, t in 2:t_steps, π in π, ξ in ξ, θ in θ], soc[j,d,t,π,ξ,θ]  == soc[j,d,t-1,π,ξ,θ] + (chᴰᴬ[j,d,t] + chᴵᴰ[j,d,t,π] + chᴿᵀ[j,d,t,π,ξ,θ]) .* step_size .* η_ch[j] - ((dchᴰᴬ[j,d,t] + dchᴵᴰ[j,d,t,π] + dchᴿᵀ[j,d,t,π,ξ,θ]) .* step_size ./ η_dch[j])
            # [j in 1:number_of_DER, d in 1:days, t = 1, π in π, ξ in ξ, θ in θ], soc[j,d,t,π,ξ,θ]  == soc[j,d,end,π,ξ,θ] + (chᴰᴬ[j,d,t] + chᴵᴰ[j,d,t,π] + chᴿᵀ[j,d,t,π,ξ,θ]).* step_size  .* η_ch[j] - ((dchᴰᴬ[j,d,t] + dchᴵᴰ[j,d,t,π] + dchᴿᵀ[j,d,t,π,ξ,θ]) .* step_size ./ η_dch[j])

    end)

    return model
end

function build_test_model(agent::Aggregator, period::Period, prices::Dict)
    "The model with CVAR and WCVAR constraints"
    model = agent.name
    println("Building model for $model")
    #BUILDING GENERIC MODEL
    model = Model()
    model.ext[:param] = Dict()
    model.ext[:dec_vars] = Dict()
    param = model.ext[:param]
    dec_vars = model.ext[:dec_vars]
    param[:t_steps] = t_steps = period.number_of_t_steps
    param[:step_size] = step_size = period.step_size
    param[:days] = days = period.number_of_days
    number_of_ID_dev =
        try
            number_of_ID_dev =  length(agent.DER_agents[1].dev_ID) # Number of intra-day deviation scenarios
        catch
            number_of_ID_dev = 1
        end
    number_of_RT_dev =
        try
            number_of_RT_dev =  length(agent.DER_agents[1].dev_RT) # Number of intra-day deviation scenarios
        catch
            number_of_RT_dev = 1
        end
    number_of_RT_market =
        try
            number_of_RT_market =  length(prices[:RT]) # Number of intra-day deviation scenarios
        catch
            number_of_RT_market = 1
        end
    number_of_DA_market =
        try
            number_of_DA_market =  length(prices[:DA]) # Number of intra-day deviation scenarios
        catch
            number_of_DA_market = 1
        end
    param[:scens_DA_market] = scens_DA_market = Array{String}(undef, days, t_steps, number_of_DA_market) #Day-ahead market scenario set
    param[:scens_RT_market] = scens_RT_market = Array{String}(undef, days, t_steps, number_of_DA_market, number_of_RT_market) #Real-time imbalance market scenario set
    param[:demands] = demands = Array{String}(undef, days, t_steps)
    param[:scens_ID_dev] = scens_ID_dev = Array{String}(undef, days, t_steps, number_of_ID_dev) #Intra-day DER deviation scenario set
    param[:scens_RT_dev] = scens_RT_dev = Array{String}(undef, days, t_steps, number_of_ID_dev, number_of_RT_dev)  #Real-time DER deviation scenario set
    param[:number_of_DER] = number_of_DER =  length(agent.DER_agents)
    param[:DERs] = DERs = [agent.DER_agents[j].name for j in 1:number_of_DER]
    param[:max_DA] = max_DA = agent.max_DA
    param[:max_RT] = max_RT = agent.max_RT

    # # agent.DER_agents[1].dev_ID.scenario.id
    # param[:π] = π = 1:number_of_ID_dev
    # param[:scens_ID_dev]= scens_ID_dev = param[:scens_ID_dev] = scens_ID_dev = [agent.DER_agents[j].dev_ID for j in 1:number_of_DER]
    #to access scens_ID_dev[2]; where j = 2

    param[:ξ] = ξ = 1:number_of_RT_dev
    param[:scens_RT_dev] = scens_RT_dev = param[:scens_RT_dev] = scens_RT_dev = [agent.DER_agents[j].dev_RT for j in 1:number_of_DER]
    #to access scens_RT_dev[2][1]; where j = 2 and s = 1

    param[:ζ] = ζ = 1:number_of_DA_market
    param[:scens_DA_market] = scens_DA_market = prices[:DA]
    #to access scens_DA_market

    param[:θ] = θ = 1:number_of_RT_market
    param[:scens_RT_market] = scens_RT_market = prices[:RT]
    #to access scens_RT_market scens_RT_market[3]; where s =3

    param[:demands] = demands = [agent.DER_agents[j].demand for j in 1:number_of_DER]
    #to access e.g. demands[2].values; where j = 2
    #Currently all operational costs are for the agents controlled by the aggregator
    param[:OPEX_DA] = OPEX_DA = [agent.DER_agents[j].OPEX_DA for j in 1:number_of_DER]
    param[:OPEX_ID] = OPEX_ID = [agent.DER_agents[j].OPEX_ID for j in 1:number_of_DER]
    param[:OPEX_RT] = OPEX_RT = [agent.DER_agents[j].OPEX_RT for j in 1:number_of_DER]

    param[:η_ch] = η_ch = [agent.DER_agents[j].battery.efficiency_ch for j in 1:number_of_DER]
    param[:η_dch] = η_dch = [agent.DER_agents[j].battery.efficiency_dch for j in 1:number_of_DER]
    param[:capₚ] = capₚ = [agent.DER_agents[j].battery.capacity_power for j in 1:number_of_DER]
    param[:capsₑ] = capsₑ = [agent.DER_agents[j].battery.capacity_energy for j in 1:number_of_DER]
    param[:initₑ] = initₑ = [agent.DER_agents[j].battery.soc_init for j in 1:number_of_DER]

    #Associated with the aggregator's risk-attitude:
    param[:βᴬ] = βᴬ = agent.preferences.βᴬ #adjustment param for the risk-averseness
    param[:γᴬ] = γᴬ = agent.preferences.γᴬ #tradeoff between maximizing expacted return vs risk aversion, 1.0 -> risk neutral
    param[:ϵ] = ϵ = agent.preferences.ϵ  #adjustment param for the risk-averseness



    #############THE MAIN DECISION VARIABLES########
    #NOTE: IT WOULD BE EASIER TO FIX VARS IF THEY WERE CATEGORIZED
    dec_vars[:aᴰᴬ] = @variable(model,
     -max_DA <=  aᴰᴬ[d in 1:days, t in 1:t_steps] <= max_DA) #NOTE#Energy exchanged day-ahead
    dec_vars[:aᴿᵀ] = @variable(model,
      -max_RT <=  aᴿᵀ[d in 1:days, t in 1:t_steps, θ in θ] <= max_RT) #NOTE Only buying is allowed for the sake of the case study to avoid virtual bidding too much. #Energy exchanged real-time
    # dec_vars[:fᴰᴬ] = @variable(model,
    #     fᴰᴬ[j in 1:number_of_DER, d in 1:days, t in 1:t_steps]) #Flexibility exchanged between the aggregator and the DERs day-ahead
    # dec_vars[:fᴵᴰ] = @variable(model,
    #     0 == fᴵᴰ[j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π]) #Flexibility exchanged between the aggregator and the DERs intra-day
    # dec_vars[:fᴿᵀ] = @variable(model,
    #     fᴿᵀ[j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π, ξ in ξ, θ in θ]) #Flexibility exchanged between the aggregator and the DERs real-time
    dec_vars[:chᴰᴬ] = @variable(model,
        0 <= chᴰᴬ[j in 1:number_of_DER, d in 1:days, t in 1:t_steps]) #Scheduling charging of the DERs day-ahead
    # dec_vars[:bᴰᴬ] = @variable(model,
    #     bᴰᴬ[j in 1:number_of_DER, d in 1:days, t in 1:t_steps], Bin) #Binary for dch/charging of the DERs day-ahead
    # dec_vars[:chᴵᴰ] = @variable(model,
    #     0 == chᴵᴰ[j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π]) #Scheduling charging of the DERs intra-day
    # dec_vars[:bᴵᴰ] = @variable(model,
    #     bᴵᴰ[j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π], Bin) #Binary for dch/charging of the DERs intra-day
    dec_vars[:chᴿᵀ] = @variable(model,
        0 <= chᴿᵀ[j in 1:number_of_DER, d in 1:days, t in 1:t_steps, ξ in ξ, θ in θ]) #Scheduling charging of the DERs real-time
    # dec_vars[:bᴿᵀ] = @variable(model,
    #     bᴿᵀ[j in 1:number_of_DER, d in 1:days, t in 1:t_steps, ξ in ξ, θ in θ], Bin) #Binary for dch/charging of the DERs real-time
    dec_vars[:slack_up] = @variable(model,
        0 <= slack_up[j in 1:number_of_DER, d in 1:days, t in 1:t_steps,  ξ in ξ, θ in θ])
    dec_vars[:slack_down] = @variable(model,
        0 <= slack_down[j in 1:number_of_DER, d in 1:days, t in 1:t_steps, ξ in ξ, θ in θ])
    dec_vars[:slack_down_power_ch] = @variable(model,
        0 == slack_down_power_ch[j in 1:number_of_DER, d in 1:days, t in 1:t_steps, ξ in ξ, θ in θ])
    dec_vars[:slack_balance_up] = @variable(model,
        0 == slack_balance_up[d in 1:days, t in 1:t_steps, ξ in ξ, θ in θ])
    dec_vars[:slack_balance_down] = @variable(model,
        0 == slack_balance_down[d in 1:days, t in 1:t_steps, ξ in ξ, θ in θ])
    dec_vars[:slack_up_power_ch] = @variable(model,
        0 == slack_up_power_ch[j in 1:number_of_DER, d in 1:days, t in 1:t_steps, ξ in ξ, θ in θ])
    dec_vars[:slack_down_power_dch] = @variable(model,
        0 == slack_down_power_dch[j in 1:number_of_DER, d in 1:days, t in 1:t_steps, ξ in ξ, θ in θ])
    dec_vars[:slack_up_power_dch] = @variable(model,
        0 == slack_up_power_dch[j in 1:number_of_DER, d in 1:days, t in 1:t_steps, ξ in ξ, θ in θ])
    dec_vars[:dchᴰᴬ] = @variable(model,
        0 <= dchᴰᴬ[j in 1:number_of_DER, d in 1:days, t in 1:t_steps]) #Scheduling discharging of the DERs day-ahead
    # dec_vars[:dchᴵᴰ] = @variable(model,
    #     0 == dchᴵᴰ[j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π]) #Scheduling discharging of the DERs intra-day
    dec_vars[:dchᴿᵀ] = @variable(model,
        0 <= dchᴿᵀ[j in 1:number_of_DER, d in 1:days, t in 1:t_steps, ξ in ξ, θ in θ]) #Scheduling discharging of the DERs real-time
    dec_vars[:soc] = @variable(model,
        - 10 * capsₑ[j] <= soc[j in 1:number_of_DER, d in 1:days, t in 1:t_steps, ξ in ξ, θ in θ] <=  10 * capsₑ[j]) #NOTE #Scheduling state-of-charge of the DERs real-time
    # dec_vars[:soc_DA] = @variable(model,
    #     0 <= soc_DA[j in 1:number_of_DER, d in 1:days, t in 1:t_steps] <= capsₑ[j]) #Scheduling state-of-charge of the DERs day-ahead
    # dec_vars[:soc_ID] = @variable(model,
    #     0 <= soc_ID[j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π] <= capsₑ[j]) #Scheduling state-of-charge of the DERs day-ahead
    #To formulate the conditional-value-at-risk
    ##################EXPRESSIONS##############
    model[:cost_DA_market] = cost_DA_market = @expression(model, [d in 1:days, t in 1:t_steps],
        scens_DA_market.scenario.prob .* (scens_DA_market.values[d,t] .* aᴰᴬ[d,t])) #Single DA scenario
    model[:cost_DA_DERs] = cost_DA_DERs = @expression(model, [j in 1:number_of_DER, d in 1:days, t in 1:t_steps],
        OPEX_DA[j] .* (dchᴰᴬ[j,d,t] + chᴰᴬ[j,d,t]))
    # model[:cost_ID_DERs] = cost_ID_DERs = @expression(model, [j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π],
    #     scens_ID_dev[j][π].scenario.prob .* OPEX_ID[j] .* (dchᴵᴰ[j,d,t,π] + chᴵᴰ[j,d,t,π]))
    model[:cost_RT_market] = cost_RT_market = @expression(model, [d in 1:days, t in 1:t_steps, θ in θ],
        scens_RT_market[θ].scenario.prob .* (scens_RT_market[θ].values[d,t].* aᴿᵀ[d,t,θ]))
    model[:cost_RT_DERs] = cost_RT_DERs = @expression(model, [j in 1:number_of_DER, d in 1:days, t in 1:t_steps,  ξ in ξ, θ in θ],
        scens_RT_dev[j][ξ].scenario.prob .* OPEX_RT[j] .* (dchᴿᵀ[j,d,t,ξ,θ] + chᴿᵀ[j,d,t,ξ,θ]))
    model[:slack_cost_up] = slack_cost_up = @expression(model, [j in 1:number_of_DER, d in 1:days, t in 1:t_steps,ξ in ξ, θ in θ],
        slack_up[j,d,t,ξ,θ] .* 1000)
    model[:slack_cost_down] = slack_cost_down = @expression(model, [j in 1:number_of_DER, d in 1:days, t in 1:t_steps,ξ in ξ, θ in θ],
        slack_down[j,d,t,ξ,θ] .* 1000)

    # model[:slack_power_up_ch] = slack_power_up_ch = @expression(model, [j in 1:number_of_DER,d in 1:days, t in 1:t_steps, ξ in ξ, θ in θ],
    #     slack_up_power_ch[j,d,t,ξ,θ] .* 1000)
    # model[:slack_power_down_ch] = slack_power_down_ch = @expression(model, [j in 1:number_of_DER,d in 1:days, t in 1:t_steps, π in π, ξ in ξ, θ in θ],
    #     slack_down_power_ch[j,d,t,π,ξ,θ] .* 1000)
    #
    # model[:slack_power_up_dch] = slack_power_up_dch = @expression(model, [j in 1:number_of_DER,d in 1:days, t in 1:t_steps, ξ in ξ, θ in θ],
    #     slack_up_power_dch[j,d,t,ξ,θ] .* 1000)
    # model[:slack_power_down_dch] = slack_power_down_dch = @expression(model, [j in 1:number_of_DER,d in 1:days, t in 1:t_steps, π in π, ξ in ξ, θ in θ],
    #     slack_down_power_dch[j,d,t,π,ξ,θ] .* 1000)

    # model[:slack_balance_cost_up] = slack_balance_cost_up = @expression(model, [d in 1:days, t in 1:t_steps,  ξ in ξ, θ in θ],
    #     slack_balance_up[d,t,ξ,θ] .* 1000)
    # model[:slack_balance_cost_down] = slack_balance_cost_down = @expression(model, [d in 1:days, t in 1:t_steps, ξ in ξ, θ in θ],
    #     slack_balance_down[d,t,ξ,θ] .* 1000)

    model[:true_cost_AGG] = cost_AGG = @expression(model,
            sum(cost_DA_market[d,t] for d in 1:days, t in 1:t_steps)
        +   sum(cost_DA_DERs[j,d,t] for j in 1:number_of_DER, d in 1:days, t in 1:t_steps)
        # +   sum(cost_ID_DERs[j,d,t,π] for j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π)
        +   sum(cost_RT_market[d,t,θ] for d in 1:days, t in 1:t_steps, θ in θ)
        +   sum(cost_RT_DERs[j,d,t,ξ,θ] for j in 1:number_of_DER, d in 1:days, t in 1:t_steps, ξ in ξ, θ in θ)
    )

    model[:cost_AGG] = cost_AGG = @expression(model,
            sum(cost_DA_market[d,t] for d in 1:days, t in 1:t_steps)
        +   sum(cost_DA_DERs[j,d,t] for j in 1:number_of_DER, d in 1:days, t in 1:t_steps)
        # +   sum(cost_ID_DERs[j,d,t,π] for j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π)
        +   sum(cost_RT_market[d,t,θ] for d in 1:days, t in 1:t_steps, θ in θ)
        +   sum(cost_RT_DERs[j,d,t,ξ,θ] for j in 1:number_of_DER, d in 1:days, t in 1:t_steps, ξ in ξ, θ in θ)
        +   sum((slack_cost_up[j,d,t,ξ,θ] + slack_cost_down[j,d,t,ξ,θ]) for j in 1:number_of_DER, d in 1:days, t in 1:t_steps, ξ in ξ, θ in θ)
        # +   sum((slack_power_up_ch[j,d,t,ξ,θ]) for j in 1:number_of_DER, d in 1:days, t in 1:t_steps, ξ in ξ, θ in θ)
        # +   sum((slack_power_up_dch[j,d,t,ξ,θ]) for j in 1:number_of_DER, d in 1:days, t in 1:t_steps, ξ in ξ, θ in θ)
        # +   sum((slack_balance_cost_up[d,t,ξ,θ] + slack_balance_cost_down[d,t,ξ,θ]) for d in 1:days, t in 1:t_steps, ξ in ξ, θ in θ)
        )

    @objective(model, Min, cost_AGG)

    penalty_term = [] # for ADMM

    model[:energy_balance] = energy_balance = @expression(model, [d in 1:days, t in 1:t_steps, ξ in ξ, θ in θ], sum(dchᴰᴬ[j,d,t] - chᴰᴬ[j,d,t] + dchᴿᵀ[j,d,t,ξ,θ] - chᴿᵀ[j,d,t,ξ,θ] - demands[j].values[d,t] - scens_RT_dev[j][ξ].values[d,t]
        for j in 1:number_of_DER) + aᴰᴬ[d,t] + aᴿᵀ[d,t,θ])
    #Better force it to hold for each stage, otherwise weird behaviour might be present
    # model[:energy_balance_DA] = energy_balance_DA = @expression(model, [d in 1:days, t in 1:t_steps], sum(dchᴰᴬ[j,d,t] - chᴰᴬ[j,d,t] - demands[j].values[d,t] for j in 1:number_of_DER) + aᴰᴬ[d,t])
    # model[:energy_balance_ID] = energy_balance_ID = @expression(model, [d in 1:days, t in 1:t_steps, π in π], sum(fᴵᴰ[j,d,t,π] - scens_ID_dev[j][π].values[d,t] for j in 1:number_of_DER))
    # model[:energy_balance_RT] = energy_balance_RT = @expression(model, [d in 1:days, t in 1:t_steps, π in π, ξ in ξ, θ in θ], sum(fᴿᵀ[j,d,t,π,ξ,θ] - scens_RT_dev[j][ξ].values[d,t] for j in 1:number_of_DER) + aᴿᵀ[d,t,θ])

    @constraints(model, begin
        #SLACK constraints
            #Downward violation
            [j in 1:number_of_DER, d in 1:days, t in 1:t_steps, ξ in ξ, θ in θ], 0 - slack_down[j,d,t,ξ,θ] <= soc[j,d,t,ξ,θ]
            #Upward violation
            [j in 1:number_of_DER, d in 1:days, t in 1:t_steps, ξ in ξ, θ in θ], soc[j,d,t,ξ,θ] <= capsₑ[j] + slack_up[j,d,t,ξ,θ]
        #Day-ahead balance
            #For the community:
            # [d in 1:days, t in 1:t_steps], energy_balance_DA[d,t] == 0
            #For the agents:
            # [j in 1:number_of_DER, d in 1:days, t in 1:t_steps], fᴰᴬ[j,d,t] == dchᴰᴬ[j,d,t] - chᴰᴬ[j,d,t]
        #Intra-day balance
            #For the community:
            # [d in 1:days, t in 1:t_steps, π in π], energy_balance_ID[d,t,π] == 0
            #For the agents:
            # [j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π], fᴵᴰ[j,d,t,π] == dchᴵᴰ[j,d,t,π] - chᴵᴰ[j,d,t,π]
        #Real-time balance
            #For the community:
            # [d in 1:days, t in 1:t_steps, ξ in ξ, θ in θ], energy_balance_RT[d,t,ξ,θ] == 0
            #option B
            [d in 1:days, t in 1:t_steps, ξ in ξ, θ in θ], energy_balance[d,t,ξ,θ] == 0
            #For the agents:
            # [j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π, ξ in ξ, θ in θ], fᴿᵀ[j,d,t,π,ξ,θ] == dchᴿᵀ[j,d,t,π,ξ,θ] - chᴿᵀ[j,d,t,π,ξ,θ]
        #DER battery related ones
            [j in 1:number_of_DER, d in 1:days, t in 1:t_steps,  ξ in ξ, θ in θ], dchᴰᴬ[j,d,t]  + dchᴿᵀ[j,d,t,ξ,θ] <= capₚ[j]
            [j in 1:number_of_DER, d in 1:days, t in 1:t_steps,  ξ in ξ, θ in θ], chᴰᴬ[j,d,t] + chᴿᵀ[j,d,t,ξ,θ] <= capₚ[j]
            # [j in 1:number_of_DER, d in 1:days, t = 1, ξ in ξ, θ in θ], soc[j,d,t,ξ,θ] == initₑ[j] * capsₑ[j]
            #The binaries for avoinding simoultanious ch/dch, if not needed just comment them out with the variables;
            #might be good to ex-post validate if it was happening by checking the obj with and without
            # [j in 1:number_of_DER, d in 1:days, t = 1:t_steps], bᴰᴬ[j,d,t] * chᴰᴬ[j,d,t] == 0
            # [j in 1:number_of_DER, d in 1:days, t = 1:t_steps], (1 - bᴰᴬ[j,d,t]) * dchᴰᴬ[j,d,t] == 0
            #
            # [j in 1:number_of_DER, d in 1:days, t = 1:t_steps, π in π], bᴵᴰ[j,d,t,π] * chᴵᴰ[j,d,t,π] == 0
            # [j in 1:number_of_DER, d in 1:days, t = 1:t_steps, π in π], (1 - bᴵᴰ[j,d,t,π]) * dchᴵᴰ[j,d,t,π]  == 0
            #
            # [j in 1:number_of_DER, d in 1:days, t = 1:t_steps, ξ in ξ, θ in θ], bᴿᵀ[j,d,t,ξ,θ] * chᴿᵀ[j,d,t,ξ,θ] == 0
            # [j in 1:number_of_DER, d in 1:days, t = 1:t_steps, ξ in ξ, θ in θ], (1 - bᴿᵀ[j,d,t,ξ,θ]) * dchᴿᵀ[j,d,t,ξ,θ] == 0

            # # #Cyclic boundary conditions
            # #DA
            # [j in 1:number_of_DER, d in 1:days, t in 2:t_steps], soc_DA[j,d,t]  == soc_DA[j,d,t-1] + (chᴰᴬ[j,d,t]) .* step_size .* η_ch[j] - (dchᴰᴬ[j,d,t] .* step_size ./ η_dch[j])
            # [j in 1:number_of_DER, d in 1:days, t = 1], soc_DA[j,d,t]  == soc_DA[j,d,end] + (chᴰᴬ[j,d,t]).* step_size  .* η_ch[j] - (dchᴰᴬ[j,d,t] .* step_size ./ η_dch[j])
            # #ID
            # [j in 1:number_of_DER, d in 1:days, t in 2:t_steps, π in π], soc_ID[j,d,t,π]  == soc_ID[j,d,t-1,π] + (chᴰᴬ[j,d,t] + chᴵᴰ[j,d,t,π]) .* step_size .* η_ch[j] - ((dchᴰᴬ[j,d,t] + dchᴵᴰ[j,d,t,π]) .* step_size ./ η_dch[j])
            # [j in 1:number_of_DER, d in 1:days, t = 1, π in π], soc_ID[j,d,t,π]  == soc_ID[j,d,end,π] + (chᴰᴬ[j,d,t] + chᴵᴰ[j,d,t,π]).* step_size  .* η_ch[j] - ((dchᴰᴬ[j,d,t] + dchᴵᴰ[j,d,t,π]) .* step_size ./ η_dch[j])
            #RT
            [j in 1:number_of_DER, d in 1:days, t in 2:t_steps,  ξ in ξ, θ in θ], soc[j,d,t,ξ,θ] == soc[j,d,t-1,ξ,θ] + (chᴰᴬ[j,d,t]  + chᴿᵀ[j,d,t,ξ,θ]) .* step_size .* η_ch[j] - ((dchᴰᴬ[j,d,t] + dchᴿᵀ[j,d,t,ξ,θ]) .* step_size ./ η_dch[j])
            # soc2 = [j in 1:number_of_DER, d in 1:days, t = 1, ξ in ξ, θ in θ], soc[j,d,t,ξ,θ] == soc[j,d,end,ξ,θ] + (chᴰᴬ[j,d,t] + chᴿᵀ[j,d,t,ξ,θ]).* step_size  .* η_ch[j] - ((dchᴰᴬ[j,d,t] + dchᴿᵀ[j,d,t,ξ,θ]) .* step_size ./ η_dch[j])

    end)

    return model
end


function build_VAR_model(agent::Aggregator, period::Period, prices::Dict)
    "The model with CC"
    model = agent.name
    println("Building model for $model")
    #BUILDING GENERIC MODEL
    model = Model()
    model.ext[:param] = Dict()
    model.ext[:dec_vars] = Dict()
    param = model.ext[:param]
    dec_vars = model.ext[:dec_vars]
    param[:t_steps] = t_steps = period.number_of_t_steps
    param[:step_size] = step_size = period.step_size
    param[:days] = days = period.number_of_days
    number_of_ID_dev =
        try
            number_of_ID_dev =  length(agent.DER_agents[1].dev_ID) # Number of intra-day deviation scenarios
        catch
            number_of_ID_dev = 1
        end
    number_of_RT_dev =
        try
            number_of_RT_dev =  length(agent.DER_agents[1].dev_RT) # Number of intra-day deviation scenarios
        catch
            number_of_RT_dev = 1
        end
    number_of_RT_market =
        try
            number_of_RT_market =  length(prices[:RT]) # Number of intra-day deviation scenarios
        catch
            number_of_RT_market = 1
        end
    number_of_DA_market =
        try
            number_of_DA_market =  length(prices[:DA]) # Number of intra-day deviation scenarios
        catch
            number_of_DA_market = 1
        end
    param[:scens_DA_market] = scens_DA_market = Array{String}(undef, days, t_steps, number_of_DA_market) #Day-ahead market scenario set
    param[:scens_RT_market] = scens_RT_market = Array{String}(undef, days, t_steps, number_of_DA_market, number_of_RT_market) #Real-time imbalance market scenario set
    param[:demands] = demands = Array{String}(undef, days, t_steps)
    param[:scens_ID_dev] = scens_ID_dev = Array{String}(undef, days, t_steps, number_of_ID_dev) #Intra-day DER deviation scenario set
    param[:scens_RT_dev] = scens_RT_dev = Array{String}(undef, days, t_steps, number_of_ID_dev, number_of_RT_dev)  #Intra-day DER deviation scenario set
    param[:number_of_DER] = number_of_DER =  length(agent.DER_agents)
    param[:DERs] = DERs = [agent.DER_agents[j].name for j in 1:number_of_DER]
    param[:max_DA] = max_DA = agent.max_DA
    param[:max_RT] = max_RT = agent.max_RT

    # agent.DER_agents[1].dev_ID.scenario.id
    param[:π] = π = 1:number_of_ID_dev
    param[:scens_ID_dev]= scens_ID_dev = param[:scens_ID_dev] = scens_ID_dev = [agent.DER_agents[j].dev_ID for j in 1:number_of_DER]
    #to access scens_ID_dev[2]; where j = 2

    param[:ξ] = ξ = 1:number_of_RT_dev
    param[:scens_RT_dev] = scens_RT_dev = param[:scens_RT_dev] = scens_RT_dev = [agent.DER_agents[j].dev_RT for j in 1:number_of_DER]
    #to access scens_RT_dev[2][1]; where j = 2 and s = 1

    param[:ζ] = ζ = 1:number_of_DA_market
    param[:scens_DA_market] = scens_DA_market = prices[:DA]
    #to access scens_DA_market

    param[:θ] = θ = 1:number_of_RT_market
    param[:scens_RT_market] = scens_RT_market = prices[:RT]
    #to access scens_RT_market scens_RT_market[3]; where s =3

    param[:demands] = demands = [agent.DER_agents[j].demand for j in 1:number_of_DER]
    #to access e.g. demands[2].values; where j = 2
    #Currently all operational costs are for the agents controlled by the aggregator
    param[:OPEX_DA] = OPEX_DA = [agent.DER_agents[j].OPEX_DA for j in 1:number_of_DER]
    param[:OPEX_ID] = OPEX_ID = [agent.DER_agents[j].OPEX_ID for j in 1:number_of_DER]
    param[:OPEX_RT] = OPEX_RT = [agent.DER_agents[j].OPEX_RT for j in 1:number_of_DER]

    param[:η_ch] = η_ch = [agent.DER_agents[j].battery.efficiency_ch for j in 1:number_of_DER]
    param[:η_dch] = η_dch = [agent.DER_agents[j].battery.efficiency_dch for j in 1:number_of_DER]
    param[:capₚ] = capₚ = [agent.DER_agents[j].battery.capacity_power for j in 1:number_of_DER]
    param[:capsₑ] = capsₑ = [agent.DER_agents[j].battery.capacity_energy for j in 1:number_of_DER]
    param[:initₑ] = initₑ = [agent.DER_agents[j].battery.soc_init for j in 1:number_of_DER]

    #Associated with the aggregator's risk-attitude:
    param[:βᴬ] = βᴬ = agent.preferences.βᴬ #adjustment param for the risk-averseness
    param[:γᴬ] = γᴬ = agent.preferences.γᴬ #tradeoff between maximizing expacted return vs risk aversion, 1.0 -> risk neutral
    param[:ϵ] = ϵ = agent.preferences.ϵ  #adjustment param for the risk-averseness
    param[:M] = M = agent.preferences.bigM  #big-M value


    # ############THE MAIN DECISION VARIABLES########
    dec_vars[:aᴰᴬ] = @variable(model,
         - max_DA <= aᴰᴬ[d in 1:days, t in 1:t_steps] <= max_DA) #NOTE#Energy exchanged day-ahead
    dec_vars[:aᴿᵀ] = @variable(model,
         - max_RT <=  aᴿᵀ[d in 1:days, t in 1:t_steps, θ in θ] <= max_RT) #NOTE Only buying is allowed for the sake of the case study to avoid virtual bidding too much. #Energy exchanged real-time
    dec_vars[:fᴰᴬ] = @variable(model,
        fᴰᴬ[j in 1:number_of_DER, d in 1:days, t in 1:t_steps]) #Flexibility exchanged between the aggregator and the DERs day-ahead
    dec_vars[:fᴵᴰ] = @variable(model,
        0 == fᴵᴰ[j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π]) #Flexibility exchanged between the aggregator and the DERs intra-day
    dec_vars[:fᴿᵀ] = @variable(model,
        fᴿᵀ[j in 1:number_of_DER, d in 1:days, t in 1:t_steps, ξ in ξ, θ in θ]) #Flexibility exchanged between the aggregator and the DERs real-time
    dec_vars[:chᴰᴬ] = @variable(model,
        0 <= chᴰᴬ[j in 1:number_of_DER, d in 1:days, t in 1:t_steps]) #Scheduling charging of the DERs day-ahead
    # dec_vars[:bᴰᴬ] = @variable(model,
    #     bᴰᴬ[j in 1:number_of_DER, d in 1:days, t in 1:t_steps], Bin) #Binary for dch/charging of the DERs day-ahead
    dec_vars[:chᴵᴰ] = @variable(model,
        0 == chᴵᴰ[j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π]) #Scheduling charging of the DERs intra-day
    # dec_vars[:bᴵᴰ] = @variable(model,
    #     bᴵᴰ[j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π], Bin) #Binary for dch/charging of the DERs intra-day
    dec_vars[:chᴿᵀ] = @variable(model,
        0 <= chᴿᵀ[j in 1:number_of_DER, d in 1:days, t in 1:t_steps, ξ in ξ, θ in θ]) #Scheduling charging of the DERs real-time
    # dec_vars[:bᴿᵀ] = @variable(model,
    #     bᴿᵀ[j in 1:number_of_DER, d in 1:days, t in 1:t_steps, ξ in ξ, θ in θ], Bin) #Binary for dch/charging of the DERs real-time
    dec_vars[:dchᴰᴬ] = @variable(model,
        0 <= dchᴰᴬ[j in 1:number_of_DER, d in 1:days, t in 1:t_steps]) #Scheduling discharging of the DERs day-ahead
    dec_vars[:dchᴵᴰ] = @variable(model,
        0 == dchᴵᴰ[j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π]) #Scheduling discharging of the DERs intra-day
    dec_vars[:dchᴿᵀ] = @variable(model,
        0 <= dchᴿᵀ[j in 1:number_of_DER, d in 1:days, t in 1:t_steps, ξ in ξ, θ in θ]) #Scheduling discharging of the DERs real-time
    dec_vars[:soc] = @variable(model,
        -10 * capsₑ[j] <= soc[j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π, ξ in ξ, θ in θ] <= capsₑ[j]) #Scheduling state-of-charge of the DERs real-time
    # dec_vars[:soc_DA] = @variable(model,
    #     0 <= soc_DA[j in 1:number_of_DER, d in 1:days, t in 1:t_steps] <= capsₑ[j]) #Scheduling state-of-charge of the DERs day-ahead
    # dec_vars[:soc_ID] = @variable(model,
    #     0 <= soc_ID[j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π] <= capsₑ[j]) #Scheduling state-of-charge of the DERs day-ahead
    #To formulate the conditional-value-at-risk
    dec_vars[:η_upper] = @variable(model,
        η_upper[j in 1:number_of_DER, d in 1:days, t in 1:t_steps])
    dec_vars[:b_upper] = @variable(model,
        b_upper[j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π, ξ in ξ, θ in θ], Bin)
    dec_vars[:η_lower] = @variable(model,
        η_lower[j in 1:number_of_DER, d in 1:days, t in 1:t_steps])
    dec_vars[:b_lower] = @variable(model,
        b_lower[j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π, ξ in ξ, θ in θ], Bin)
    dec_vars[:viol_upper] = @variable(model,
        0 <= viol_upper[j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π, ξ in ξ, θ in θ])
    dec_vars[:viol_lower] = @variable(model,
        0 <= viol_lower[j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π, ξ in ξ, θ in θ])


    ##################EXPRESSIONS##############
    model[:cost_DA_market] = cost_DA_market = @expression(model, [d in 1:days, t in 1:t_steps],
        scens_DA_market.scenario.prob  .* (scens_DA_market.values[d,t] .* aᴰᴬ[d,t])) #Single DA scenario
    model[:cost_DA_DERs] = cost_DA_DERs = @expression(model, [j in 1:number_of_DER, d in 1:days, t in 1:t_steps],
        OPEX_DA[j] .* (dchᴰᴬ[j,d,t] + chᴰᴬ[j,d,t]))
    model[:cost_ID_DERs] = cost_ID_DERs = @expression(model, [j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π],
        scens_ID_dev[j][π].scenario.prob .* OPEX_ID[j] .* (dchᴵᴰ[j,d,t,π] + chᴵᴰ[j,d,t,π]))
    model[:cost_RT_market] = cost_RT_market = @expression(model, [d in 1:days, t in 1:t_steps, θ in θ],
        scens_RT_market[θ].scenario.prob .* (scens_RT_market[θ].values[d,t] * aᴿᵀ[d,t,θ]))
    model[:cost_RT_DERs] = cost_RT_DERs = @expression(model, [j in 1:number_of_DER, d in 1:days, t in 1:t_steps, ξ in ξ, θ in θ],
        scens_RT_dev[j][ξ].scenario.prob .* OPEX_RT[j] .* (dchᴿᵀ[j,d,t,ξ,θ] + chᴿᵀ[j,d,t,ξ,θ]))
    #Cost of violation
    model[:cost_violation_upper] = cost_violation_upper = @expression(model, [j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π, ξ in ξ,  θ in θ],
        scens_RT_market[θ].scenario.prob .* scens_ID_dev[j][π].scenario.prob .* scens_RT_dev[j][ξ].scenario.prob .* (scens_RT_market[θ].values[d,t] .* viol_upper[j,d,t,π,ξ,θ]))
    # model[:qdr_cost_violation_upper] = qdr_cost_violation_upper = [
    #     @expression(model, scens_RT_market[θ].scenario.prob .* scens_ID_dev[j][π].scenario.prob .* scens_RT_dev[j][ξ].scenario.prob .* (scens_RT_market[θ].values[d,t] .* viol_upper[j,d,t,π,ξ,θ])^2)
    #     for j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π, ξ in ξ,  θ in θ
    # ]
    model[:cost_violation_lower] = cost_violation_lower = @expression(model, [j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π, ξ in ξ,  θ in θ],
        scens_RT_market[θ].scenario.prob .* scens_ID_dev[j][π].scenario.prob .* scens_RT_dev[j][ξ].scenario.prob .* (scens_RT_market[θ].values[d,t] .* viol_lower[j,d,t,π,ξ,θ]))
    # model[:qdr_cost_violation_lower] = qdr_cost_violation_lower = [
    #     @expression(model, scens_RT_market[θ].scenario.prob .* scens_ID_dev[j][π].scenario.prob .* scens_RT_dev[j][ξ].scenario.prob .* (scens_RT_market[θ].values[d,t] .* viol_lower[j,d,t,π,ξ,θ])^2)
    #     for j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π, ξ in ξ,  θ in θ
    # ]
    # model[:qdr_cost_violation] = qdr_cost_violation = @expression(model, [j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π, ξ in ξ,  θ in θ],
    #     scens_RT_market[θ].scenario.prob .* (scens_RT_market[θ].values[d,t] .* viol[j,d,t,π,ξ,θ])^2)

    model[:cost_AGG] = cost_AGG = @expression(model,
            sum(cost_DA_market[d,t] for d in 1:days, t in 1:t_steps)
        +   sum(cost_DA_DERs[j,d,t] for j in 1:number_of_DER, d in 1:days, t in 1:t_steps)
        +   sum(cost_ID_DERs[j,d,t,π] for j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π)
        +   sum(cost_RT_market[d,t,θ] for d in 1:days, t in 1:t_steps, θ in θ)
        +   sum(cost_RT_DERs[j,d,t,ξ,θ] for j in 1:number_of_DER, d in 1:days, t in 1:t_steps, ξ in ξ, θ in θ)
    )

    @objective(model, Min, cost_AGG)

    penalty_term = [] # for ADMM

    model[:energy_balance] = energy_balance = @expression(model, [d in 1:days, t in 1:t_steps, π in π, ξ in ξ, θ in θ], sum(fᴰᴬ[j,d,t] + fᴵᴰ[j,d,t,π] + fᴿᵀ[j,d,t,ξ,θ] - demands[j].values[d,t] - scens_RT_dev[j][ξ].values[d,t] - scens_ID_dev[j][π].values[d,t]
    for j in 1:number_of_DER) + aᴰᴬ[d,t] + aᴿᵀ[d,t,θ])
    #Better force it to hold for each stage, otherwise weird behaviour might be present
    model[:energy_balance_DA] = energy_balance_DA = @expression(model, [d in 1:days, t in 1:t_steps], sum(fᴰᴬ[j,d,t] - demands[j].values[d,t] for j in 1:number_of_DER) + aᴰᴬ[d,t])
    model[:energy_balance_ID] = energy_balance_ID = @expression(model, [d in 1:days, t in 1:t_steps, π in π], sum(fᴵᴰ[j,d,t,π] - scens_ID_dev[j][π].values[d,t] for j in 1:number_of_DER))
    model[:energy_balance_RT] = energy_balance_RT = @expression(model, [d in 1:days, t in 1:t_steps, ξ in ξ, θ in θ], sum(fᴿᵀ[j,d,t,ξ,θ] - scens_RT_dev[j][ξ].values[d,t] for j in 1:number_of_DER) + aᴿᵀ[d,t,θ])

    @constraints(model, begin
        #VAR related:
            [j in 1:number_of_DER, d in 1:days, t in 1:t_steps], sum(scens_RT_market[θ].scenario.prob .* scens_ID_dev[j][π].scenario.prob .* scens_RT_dev[j][ξ].scenario.prob .* b_upper[j,d,t,π,ξ,θ] for π in π, ξ in ξ, θ in θ) <= ϵ
            [j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π, ξ in ξ, θ in θ],  + soc[j,d,t,π,ξ,θ] - η_upper[j,d,t] <= M * b_upper[j,d,t,π,ξ,θ]

            [j in 1:number_of_DER, d in 1:days, t in 1:t_steps], sum(scens_RT_market[θ].scenario.prob .* scens_ID_dev[j][π].scenario.prob .* scens_RT_dev[j][ξ].scenario.prob .* b_lower[j,d,t,π,ξ,θ] for π in π, ξ in ξ, θ in θ) <= ϵ
            [j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π, ξ in ξ, θ in θ],  - soc[j,d,t,π,ξ,θ] + η_lower[j,d,t] <= M * b_lower[j,d,t,π,ξ,θ]


            [j in 1:number_of_DER, d in 1:days, t in 1:t_steps], η_upper[j,d,t] <= capsₑ[j]
            [j in 1:number_of_DER, d in 1:days, t in 1:t_steps], η_lower[j,d,t] >= 0

        #To get the violation
            [j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π, ξ in ξ, θ in θ], viol_upper[j,d,t,π,ξ,θ] >= soc[j,d,t,π,ξ,θ] - capsₑ[j]
            [j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π, ξ in ξ, θ in θ], viol_lower[j,d,t,π,ξ,θ] >= 0 - soc[j,d,t,π,ξ,θ]

        # #Day-ahead balance
            #For the community:
            [d in 1:days, t in 1:t_steps], energy_balance_DA[d,t] == 0
            #For the agents:
            [j in 1:number_of_DER, d in 1:days, t in 1:t_steps], fᴰᴬ[j,d,t] == dchᴰᴬ[j,d,t] - chᴰᴬ[j,d,t]
        #Intra-day balance
            #For the community:
            # [d in 1:days, t in 1:t_steps, π in π], energy_balance_ID[d,t,π] == 0
            #For the agents:
            [j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π], fᴵᴰ[j,d,t,π] == dchᴵᴰ[j,d,t,π] - chᴵᴰ[j,d,t,π]
        #Real-time balance
            #For the community:
            # [d in 1:days, t in 1:t_steps, ξ in ξ, θ in θ], energy_balance_RT[d,t,ξ,θ] == 0
            #option B
            [d in 1:days, t in 1:t_steps, π in π, ξ in ξ, θ in θ], energy_balance[d,t,π,ξ,θ] == 0
            #For the agents:
            [j in 1:number_of_DER, d in 1:days, t in 1:t_steps, ξ in ξ, θ in θ], fᴿᵀ[j,d,t,ξ,θ] == dchᴿᵀ[j,d,t,ξ,θ] - chᴿᵀ[j,d,t,ξ,θ]
        #DER battery related ones
            [j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π, ξ in ξ, θ in θ], dchᴰᴬ[j,d,t] + dchᴵᴰ[j,d,t,π] + dchᴿᵀ[j,d,t,ξ,θ] <= capₚ[j]
            [j in 1:number_of_DER, d in 1:days, t in 1:t_steps, π in π, ξ in ξ, θ in θ], chᴰᴬ[j,d,t] + chᴵᴰ[j,d,t,π] + chᴿᵀ[j,d,t,ξ,θ] <= capₚ[j]
            [j in 1:number_of_DER, d in 1:days, t = 1, π in π, ξ in ξ, θ in θ], soc[j,d,t,π,ξ,θ] == initₑ[j] * capsₑ[j]
            #The binaries for avoinding simoultanious ch/dch, if not needed just comment them out with the variables;
            #might be good to ex-post validate if it was happening by checking the obj with and without
            # [j in 1:number_of_DER, d in 1:days, t = 1:t_steps], bᴰᴬ[j,d,t] * chᴰᴬ[j,d,t] == 0
            # [j in 1:number_of_DER, d in 1:days, t = 1:t_steps], (1 - bᴰᴬ[j,d,t]) * dchᴰᴬ[j,d,t] == 0
            #
            # [j in 1:number_of_DER, d in 1:days, t = 1:t_steps, π in π], bᴵᴰ[j,d,t,π] * chᴵᴰ[j,d,t,π] == 0
            # [j in 1:number_of_DER, d in 1:days, t = 1:t_steps, π in π], (1 - bᴵᴰ[j,d,t,π]) * dchᴵᴰ[j,d,t,π]  == 0
            #
            # [j in 1:number_of_DER, d in 1:days, t = 1:t_steps, ξ in ξ, θ in θ], bᴿᵀ[j,d,t,ξ,θ] * chᴿᵀ[j,d,t,ξ,θ] == 0
            # [j in 1:number_of_DER, d in 1:days, t = 1:t_steps, ξ in ξ, θ in θ], (1 - bᴿᵀ[j,d,t,ξ,θ]) * dchᴿᵀ[j,d,t,ξ,θ] == 0

            # # #Cyclic boundary conditions
            # #DA
            # [j in 1:number_of_DER, d in 1:days, t in 2:t_steps], soc_DA[j,d,t]  == soc_DA[j,d,t-1] + (chᴰᴬ[j,d,t]) .* step_size .* η_ch[j] - (dchᴰᴬ[j,d,t] .* step_size ./ η_dch[j])
            # [j in 1:number_of_DER, d in 1:days, t = 1], soc_DA[j,d,t]  == soc_DA[j,d,end] + (chᴰᴬ[j,d,t]).* step_size  .* η_ch[j] - (dchᴰᴬ[j,d,t] .* step_size ./ η_dch[j])
            # #ID
            # [j in 1:number_of_DER, d in 1:days, t in 2:t_steps, π in π], soc_ID[j,d,t,π]  == soc_ID[j,d,t-1,π] + (chᴰᴬ[j,d,t] + chᴵᴰ[j,d,t,π]) .* step_size .* η_ch[j] - ((dchᴰᴬ[j,d,t] + dchᴵᴰ[j,d,t,π]) .* step_size ./ η_dch[j])
            # [j in 1:number_of_DER, d in 1:days, t = 1, π in π], soc_ID[j,d,t,π]  == soc_ID[j,d,end,π] + (chᴰᴬ[j,d,t] + chᴵᴰ[j,d,t,π]).* step_size  .* η_ch[j] - ((dchᴰᴬ[j,d,t] + dchᴵᴰ[j,d,t,π]) .* step_size ./ η_dch[j])
            #RT
            [j in 1:number_of_DER, d in 1:days, t in 2:t_steps, π in π, ξ in ξ, θ in θ], soc[j,d,t,π,ξ,θ]  == soc[j,d,t-1,π,ξ,θ] + (chᴰᴬ[j,d,t] + chᴵᴰ[j,d,t,π] + chᴿᵀ[j,d,t,ξ,θ]) .* step_size .* η_ch[j] - ((dchᴰᴬ[j,d,t] + dchᴵᴰ[j,d,t,π] + dchᴿᵀ[j,d,t,ξ,θ]) .* step_size ./ η_dch[j])
            [j in 1:number_of_DER, d in 1:days, t = 1, π in π, ξ in ξ, θ in θ], soc[j,d,t,π,ξ,θ]  == soc[j,d,end,π,ξ,θ] + (chᴰᴬ[j,d,t] + chᴵᴰ[j,d,t,π] + chᴿᵀ[j,d,t,ξ,θ]).* step_size  .* η_ch[j] - ((dchᴰᴬ[j,d,t] + dchᴵᴰ[j,d,t,π] + dchᴿᵀ[j,d,t,ξ,θ]) .* step_size ./ η_dch[j])

    end)

    return model
end

function add_objective(model::JuMP.Model)
    #will get relevant in the ADMM updates
end

function solve_model(model::JuMP.Model, optimizer::DataType; kwargs...)
    set_optimizer(model, optimizer)
    if haskey(kwargs, :timelimit)
        timelimit = kwargs[:timelimit]
        set_time_limit_sec(model, timelimit)
    end
    if haskey(kwargs,:method)
        method = kwargs[:method]
        set_optimizer_attribute(model, "Method", method)
        println("####Solving with method $method ####")
    end
    if haskey(kwargs, :presolve)
        presolve = kwargs[:presolve]
        set_optimizer_attribute(model, "Presolve", presolve)
    end
    optimize!(model)
    return model
end


function fix_model_variable!(model::JuMP.Model, s::Symbol, value::JuMP.Containers.DenseAxisArray)
    """
        Thx Seb!
        fix_model_variable!(gep, var::Symbol, value::AbstractArray)
        Fixes a JuMP variable `var` to `value`.
    """
    # Get the JuMP model variable
    var = model[s]
    # Get it's axes
    # TODO: should check that var and value have the same axes
    ax = var.axes
    # Make an array of tuples which are the indices of the JuMP arrays
    indices = collect(Iterators.product(ax...))[:]
    # Iterate over the indices
    for i in indices
        # Since i is a tuple, need to splat it to index the array
        fix(var[i...], value[i...], force=true)
    end
end

function fix_model_variable!(model::JuMP.Model, s::Symbol, value::AbstractArray)
    # Get the JuMP model variable
    var = model[s]
    JuMP.fix.(var, value; force = true)
end

function unfix_model_variable!(model::JuMP.Model, s::Symbol)
    # Get the JuMP model variable
    var = model[s]
    # Get it's axes
    # TODO: should check that var and value have the same axes
    ax = var.axes
    # Make an array of tuples which are the indices of the JuMP arrays
    indices = collect(Iterators.product(ax...))[:]
    # Iterate over the indices
    for i in indices
        # Since i is a tuple, need to splat it to index the array
        unfix(var[i...])
    end
end

function unfix_model_variable!(model::JuMP.Model, s::Symbol)
    # Get the JuMP model variable
    var = model[s]
    JuMP.unfix.(var)
end
