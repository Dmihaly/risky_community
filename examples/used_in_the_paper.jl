using Revise
#]add RiskyCommunity
using RiskyCommunity
using Parameters
using CSV
using DataFrames
using Statistics
using Glob
using JuMP
using Gurobi
using Query
using StatsBase

###########FUNCTIONS TO USE#########
    function read_result(model::JuMP.Model)
        cost_AGG = JuMP.value(model[:cost_AGG])
        cost_DA_market = sum(JuMP.value.(model[:cost_DA_market]))
        cost_RT_market = sum(JuMP.value.(model[:cost_RT_market]))
        @show cost_AGG, cost_DA_market, cost_RT_market

        soc = JuMP.value.(model[:soc])
        cap = model.ext[:param][:capsₑ][1]

        viol_balance_up = soc.data[soc.data .> (0.001 + cap)]
        viol_balance_down = soc.data[soc.data .< -0.001]
        sum_balance_down = sum(viol_balance_down)
        sum_balance_up = sum(viol_balance_up)
        numb_balance_up = length(viol_balance_up)
        numb_balance_down = length(viol_balance_down)


        reliability_in = (1-(numb_balance_up + numb_balance_down)/(5*96*65))

        @show numb_balance_up, numb_balance_down


        in_res_dict = Dict("cost_AGG" => cost_AGG, "reliability_in" => reliability_in , "cost_DA_market" => cost_DA_market, "cost_RT_market" => cost_RT_market,
        "numb_viol_UP" => numb_balance_up, "numb_viol_DOWN" => numb_balance_down, "sum_balance_down" => sum_balance_down, "sum_balance_up" => sum_balance_up)

        return in_res_dict
    end

    function read_test_result(model::JuMP.Model)
        cost_AGG = JuMP.value(model[:true_cost_AGG])
        cost_DA_market = sum(JuMP.value.(model[:cost_DA_market]))
        cost_RT_market = sum(JuMP.value.(model[:cost_RT_market]))


        slack_DOWN = JuMP.value.(model.ext[:dec_vars][:slack_down])
        slack_UP = JuMP.value.(model.ext[:dec_vars][:slack_up])

        #Violations of Balance
        numb_upper_violation = length(slack_DOWN.data[slack_DOWN.data .≠ 0])
        numb_lower_violation = length(slack_UP.data[slack_UP.data .≠ 0])
        numb_viol = (numb_upper_violation + numb_lower_violation)


        max_DOWN = max(slack_DOWN...)
        max_UP = max(slack_UP...)

        sum_DOWN = sum(slack_DOWN)
        sum_UP= sum(slack_UP)

        @show cost_AGG, cost_DA_market, cost_RT_market

        res_dict = Dict("numb_viol" => numb_viol,  "cost_AGG" => cost_AGG, "cost_DA_market" => cost_DA_market, "cost_RT_market" => cost_RT_market,
         "max_DOWN" => max_DOWN, "max_UP" => max_UP, "sum_UP" => sum_UP, "sum_DOWN" => sum_DOWN)
        return res_dict
    end

##############INIT THE MARKET DATA################
    period = Period(number_of_days = 1, number_of_t_steps= 96)
    # ##########OBTAIN THE RT IMBALANCE PRICE SCENARIOS FOR THE TRAINING SET##########
    scenarios_train = Dict()
    scen_price_RT_train = Dict()
    dat = glob("*.csv","data/imb_price_scenarios/cluster_train_5/")
    train_dat = dat
    for d in 1:length(train_dat)
        scenario_train = DataFrame!(CSV.File(train_dat[d], header = true, decimal='.'))
        scenario_train = scenario_train[2:end, :]
        scenarios_train[d] = scenario_train
        scen_price_RT_train[d] = Scenario(id = "RT_price_$d", counter = d, prob = 1/length(train_dat)) #Equal probability
    end

    prices_RT_train = []
    for d in 1:length(train_dat)
        push!(prices_RT_train, Price(period = period,  scenario = scen_price_RT_train[d], id = scen_price_RT_train[d].id))
        prices_RT_train[d].values[1,:] = scenarios_train[d].values
    end

##########CHOSING ONE FORECAST FOR DA PRICES##########
    da_price_init =  DataFrame!(CSV.File("data/Day-ahead Prices_202003150000-202003160000.csv", header = true, decimal=','))[:,2]
    da_price = [parse(Float64, da_price_init[i]) for i in range(1, stop = length(da_price_init))]
    da_price_96 = repeat(da_price, inner = [4]) #EUR/MWh
    #Single scenario for DA price
    scen_price_DA = Scenario(id = :DA_price, prob = 1.0) #Single DA scenario
    #Init DA price forecast
    price_DA = Price(period = period)
    price_DA.values[1,:] = da_price_96

    #Use this form when passing to the JuMP model
    prices_train = Dict(:DA => price_DA, :RT => prices_RT_train)

###########INIT THE DER AGENT DATA AS A SINGLE AGENT WITH BESS#############
    dat_agent = DataFrame!(CSV.File("data/WCVaR_dat/single_site/63/da_fc/63_err_1.csv", header=true, delim= ","))
    values(dat_agent[1,2:end])
    # sort(dat_agent, [:timestamp])
    loads = collect(values(dat_agent[1,2:end]) ./1000) # To get something reasonable in MW
    my_der_agent = DER_Agent(period = period)
    my_der_agent.demand.values[1,:] = loads
    my_der_agent.dev_ID.values[1,:] = zeros(length(loads)) #No ID dev
    my_der_agent.dev_RT.values[1,:] = zeros(length(loads)) #No RT dev
    #The model complains if there are no scenarios added as it expects
    scen_ID_dev_1 = Scenario(id = :ID_dev_1, counter = 1, prob = 1.0)
    dev_ID_1 = Demand(period = period, id= :ID_dev_1, scenario = scen_ID_dev_1, values = zeros(period.number_of_days, period.number_of_t_steps))
    deviations_ID = [dev_ID_1]
    my_der_agent.dev_ID = deviations_ID


#####LOADING RT DEV SCENARIOS##########FOR  WCVAR OPT#######
    # loc = "data/WCVaR_dat/diff_per_site/mix2/split"
    # # loc = "data/WCVaR_dat/single_site/58/clustered"
    # groups = readdir(loc)
    #
    # errors_dict = Dict()
    # # errors_dict["$curr_group"] = glob("*.csv","data/WCVaR_dat/diff_per_site/mix2/split/$curr_group")
    # err_scenarios_train = Dict()
    # scen_err_RT_train = Dict()
    # global counter = 0
    # for g in groups
    #     curr_group = g
    #     errors_dict["$curr_group"] = glob("*.csv","$loc/$curr_group")
    #     for d in 1:length(errors_dict["$curr_group"])
    #         global counter = counter + 1
    #         ###GET THE PROBABILITY OF THE SCENARIO STORED IN THE NAME######
    #         str = errors_dict[g][d]
    #         prob_str = last(str, 10)
    #         prob_str = first(prob_str, 6)
    #         prob_float = parse(Float64, prob_str)
    #         #########UPDATE VALUES##########
    #         err_scenario_train = DataFrame!(CSV.File(errors_dict["$curr_group"][d], header = true, decimal='.'))
    #         err_scenario_train = err_scenario_train[1:end, :].values .* loads
    #         err_scenarios_train[g,d] = err_scenario_train
    #         scen_err_RT_train[g,d] = Scenario(id = "RT_error_SITE$curr_group", counter = counter, prob = prob_float/5) #Equal probability
    #     end
    # end
    #
    # errors_RT_train = []
    # for g in groups
    #     curr_group = g
    #     for d in 1:length(errors_dict["$curr_group"])
    #         push!(errors_RT_train, Demand(period = period,  scenario = scen_err_RT_train[g,d], id = scen_err_RT_train[g,d].id, values = permutedims(err_scenarios_train[g,d])))
    #         # errors_RT_train[d].values[1,:] = err_scenarios_train[g,d]
    #     end
    # end



    # FOR  CVAR OPT#######
    error_dat = glob("*.csv","data/WCVaR_dat/diff_per_site/mix2/")
    err_scenarios_train = Dict()
    scen_err_RT_train = Dict()
    for d in 1:length(error_dat)
        ###GET THE PROBABILITY OF THE SCENARIO STORED IN THE NAME######
        str = error_dat[d]
        prob_str = last(str, 10)
        prob_str = first(prob_str, 6)
        prob_float = parse(Float64, prob_str)
        #########UPDATE VALUES##########
        err_scenario_train = DataFrame!(CSV.File(error_dat[d], header = true, decimal='.'))
        err_scenario_train = err_scenario_train[1:end, :].values .* loads
        err_scenarios_train[d] = err_scenario_train
        scen_err_RT_train[d] = Scenario(id = "RT_error_group_1", counter = d, prob = prob_float/5) #Equal probability
    end

    errors_RT_train = []
    for d in 1:length(error_dat)
        push!(errors_RT_train, Demand(period = period,  scenario = scen_err_RT_train[d], id = scen_err_RT_train[d].id))
        errors_RT_train[d].values[1,:] = err_scenarios_train[d]
    end


    my_der_agent.dev_RT = errors_RT_train

##########BESS SETTING############
    batt_1 = Battery(capacity_power = 3.0, capacity_energy = 0.4, efficiency_dch = 0.99, efficiency_ch = 0.99)
    my_der_agent.battery = batt_1
    my_der_agent_2 = deepcopy(my_der_agent)
    my_aggregator = Aggregator(name ="Mihalys_aggregator")
    DER_agents = [my_der_agent]
    my_aggregator.DER_agents = DER_agents

#OPEXs OF THE DIFFERENT STAGES
    my_aggregator.DER_agents[1].OPEX_DA = mean(price_DA.values) .* 0.01
    my_aggregator.DER_agents[1].OPEX_ID = 0.001
    my_aggregator.DER_agents[1].OPEX_RT = sum(mean(prices_RT_train[j].values) for j in [1,2,3,4,5])./5 .* 0.05

    my_aggregator.preferences.bigM = 3000.0 #For the VaR version
    my_aggregator.max_DA = 2 * max(loads...)
    my_aggregator.max_RT = 0.5 * max(Iterators.flatten([errors_RT_train[j].values for j in range(1, 65, step = 1)])...) #Max error among the scenarios




#TESTS
NEW_in_DICT_CVAR = Dict()
NEW_out_DICT_CVAR = Dict()
# NEW_in_DICT_WCVAR = Dict()
# NEW_out_DICT_WCVAR = Dict()
#
# ADD_in_DICT_WCVAR = Dict()
# ADD_out_DICT_WCVAR = Dict()

#OR LOAD THE EXISTING RESULTS
# using JLD
# out_DICT_CVAR = load("data/results/WCVaR/out_DICT_CVAR.jld")["NEW_out_DICT_CVAR"]
# NEW_out_DICT_WCVAR = load("data/results/WCVaR/out_DICT_WCVAR.jld")["NEW_out_DICT_WCVAR"]
# NEW_in_DICT_WCVAR = load("data/results/WCVaR/in_DICT_WCVAR.jld")["NEW_in_DICT_WCVAR"]
#
# NEW_out_DICT_CVAR = load("data/results/WCVaR/out_DICT_CVAR.jld")["NEW_out_DICT_CVAR"]
# NEW_in_DICT_CVAR = load("data/results/WCVaR/in_DICT_CVAR.jld")["NEW_in_DICT_CVAR"]
#
# ADD_out_DICT_WCVAR = load("data/results/WCVaR/ADD_out_DICT_WCVAR.jld")["ADD_out_DICT_WCVAR"]
# ADD_in_DICT_WCVAR = load("data/results/WCVaR/ADD_in_DICT_WCVAR.jld")["ADD_in_DICT_WCVAR"]


sites_test = ["12", "58", "40", "17", "29", "70", "68"]
for s in sites_test
    in_results_CVAR =  DataFrame(ϵ = [], reliability = [], cost = [], numb_violation_UP = [],  numb_violation_DOWN = [], sum_UP = [], sum_DOWN = [], t_build = [], t_solve = [])
    out_results_CVAR = DataFrame(ϵ = [], numb_viol = [], iter = [], cost_AGG = [], max_upper = [], max_lower = [], sum_upper = [], sum_lower = [])
    rng = range(0.01, 0.1, step = 0.01)
    for epsilon in rng
            println("epsilon was $epsilon")
            # epsilon = 0.1
            my_aggregator.preferences.ϵ = epsilon
            (aggregator_model) , time_to_build = @timed build_model(my_aggregator, period, prices_train)
            #Some debugging options
            # aggregator_model.ext[:param][:scens_RT_dev][1][2].values[1,2]
            # aggregator_model.ext[:param][:group_RT_dev]
            # aggregator_model[:energy_balance]
            #
            # aggregator_model.ext[:param][:ϵ]
            #
            # aggregator_model.ext[:param][:scens_RT_market][1]

            optimizer = Gurobi.Optimizer
            max_time = 4000
            psolve = -1
            meth = -1
            #CVAR MODEL
            (solved_aggregator_model) , time_to_solve = @timed solve_model(aggregator_model, optimizer; timelimit = max_time, method = meth, presolve = psolve)
            in_res = read_result(solved_aggregator_model)
            push!(in_results_CVAR, [epsilon, in_res["reliability_in"], in_res["cost_AGG"], in_res["numb_viol_UP"], in_res["numb_viol_DOWN"], in_res["sum_balance_up"], in_res["sum_balance_down"], time_to_build, time_to_solve])

            #Copying the aggregator for the out-of-sample tests
            test_aggregator = deepcopy(my_aggregator)
            test_DER_agent = deepcopy(my_der_agent)
            test_aggregator.DER_agents[1].dev_RT
            test_DER_agent.dev_RT = []

            #Attaining test data
            error_dat_test = glob("*.csv", "data/WCVaR_dat/single_site/$s")
            err_scenarios_test = Dict()
            scen_err_RT_test = Dict()
            for d in 1:length(error_dat_test)
                err_scenario_test = DataFrame!(CSV.File(error_dat_test[d], header = true, decimal='.'))
                err_scenario_test = err_scenario_test[1:end, :].values .* loads
                err_scenarios_test[d] = err_scenario_test
                scen_err_RT_test[d] = Scenario(id = "RT_error_group_1", counter = d, prob = 1) #Equal probability
            end

            # results_CVAR = DataFrame(ϵ = [], iter = [], cost_AGG = [], max_upper = [], max_lower = [], sum_upper = [], sum_lower = [])

            for i in 1:length(error_dat_test)
                errors_RT_test = []
                errors_RT_test = Demand(period = period,  scenario = scen_err_RT_test[i], id = scen_err_RT_test[i].id)
                errors_RT_test.values[1,:] = err_scenarios_test[i]
                test_DER_agent.dev_RT = []
                test_DER_agent.dev_RT = [errors_RT_test]
                test_aggregator.DER_agents = [test_DER_agent]
                test_aggregator_model = build_test_model(test_aggregator, period, prices_train)
                ####FIX DA DECISIONS TO CVAR MODEL#########
                # fix_model_variable!(test_aggregator_model, :fᴰᴬ, JuMP.value.(solved_aggregator_model.ext[:dec_vars][:fᴰᴬ]))
                fix_model_variable!(test_aggregator_model, :aᴰᴬ, JuMP.value.(solved_aggregator_model.ext[:dec_vars][:aᴰᴬ]))
                fix_model_variable!(test_aggregator_model, :chᴰᴬ, JuMP.value.(solved_aggregator_model.ext[:dec_vars][:chᴰᴬ]))
                fix_model_variable!(test_aggregator_model, :dchᴰᴬ, JuMP.value.(solved_aggregator_model.ext[:dec_vars][:dchᴰᴬ]))

                # fix_model_variable!(test_aggregator_model, :fᴵᴰ, JuMP.value.(solved_aggregator_model.ext[:dec_vars][:fᴵᴰ]))
                # fix_model_variable!(test_aggregator_model, :chᴵᴰ, JuMP.value.(solved_aggregator_model.ext[:dec_vars][:chᴵᴰ]))
                # fix_model_variable!(test_aggregator_model, :dchᴵᴰ, JuMP.value.(solved_aggregator_model.ext[:dec_vars][:dchᴵᴰ]))
                #Fixing everything except the imbalance market position
                # fix_model_variable!(test_aggregator_model, :soc, JuMP.value.(solved_aggregator_model.ext[:dec_vars][:soc])[:,:,:,1,:,:])
                # fix_model_variable!(test_aggregator_model, :chᴿᵀ, JuMP.value.(solved_aggregator_model.ext[:dec_vars][:chᴿᵀ])[:,:,:,1,:,:])
                # fix_model_variable!(test_aggregator_model, :dchᴿᵀ, JuMP.value.(solved_aggregator_model.ext[:dec_vars][:dchᴿᵀ])[:,:,:,1,:,:])
                fix_model_variable!(test_aggregator_model, :aᴿᵀ, JuMP.value.(solved_aggregator_model.ext[:dec_vars][:aᴿᵀ]))
                # fix_model_variable!(test_aggregator_model, :fᴿᵀ, JuMP.value.(solved_aggregator_model.ext[:dec_vars][:fᴿᵀ]))

                test_solved_aggregator_model = solve_model(test_aggregator_model, optimizer, timelimit = max_time)
                term_stat = termination_status(test_solved_aggregator_model)

                # Gurobi.compute_conflict(test_solved_aggregator_model.moi_backend.optimizer.model)
                # MOI.get(test_solved_aggregator_model.moi_backend, Gurobi.ConstraintConflictStatus(), soc1.index)
                # test_solved_aggregator_model.computeIIS()
                # using Gurobi
                # compute_conflict!(test_solved_aggregator_model)
                # grb_model = test_solved_aggregator_model.moi_backend.optimizer.model
                # computeIIS(grb_model.inner)
                # test_solved_aggregator_model.feasRelax()
                # Gurobi.compute_conflict(grb_model)
                # feasRelax(grb_model.inner)
                # Gurobi.computeIIS(test_solved_aggregator_model)
                if term_stat == MOI.OPTIMAL || term_stat == MOI.LOCALLY_SOLVED
                    println("######The result was feasible at the $i-th iteration...####")
                    cost_AGG = JuMP.value(test_solved_aggregator_model[:true_cost_AGG])
                    println("######The cost was $cost_AGG...####")

                    res = read_test_result(test_solved_aggregator_model)
                    # res["sum_UP"]
                    # res["sum_DOWN"]
                    # res["max_UP"]
                    # res["max_DOWN"]
                    # real_cost = res["cost_AGG"]
                    push!(out_results_CVAR, [test_aggregator.preferences.ϵ, res["numb_viol"], i,  res["cost_AGG"], res["max_UP"],  res["max_DOWN"], res["sum_UP"], res["sum_DOWN"]])
                else
                    println("######The result was infeasible at the $i-th iteration...####")
                end
            end
    end

    NEW_in_DICT_CVAR["SITE$s","MIX2"] = in_results_CVAR
    NEW_out_DICT_CVAR["SITE$s","MIX2"] = out_results_CVAR
end

##########FROM HERE

rels_CVAR = Dict()
rels_WCVAR = Dict()
rels_norm_CVAR = Dict()
rels_norm_WCVAR = Dict()
cost_scaled_CVAR = Dict()
cost_scaled_WCVAR = Dict()
mean_costs_CVAR = Dict()
mean_costs_WCVAR = Dict()

mean_viol_CVAR_dict = Dict()
mean_viol_WCVAR_dict = Dict()
perc95_viol_CVAR_dict = Dict()
perc95_viol_WCVAR_dict = Dict()
add_perc95_viol_WCVAR_dict = Dict()

max_viol_CVAR_dict = Dict()
max_viol_WCVAR_dict = Dict()
add_max_viol_WCVAR_dict = Dict()


add_rels_WCVAR = Dict()
add_mean_costs_WCVAR = Dict()

numb_viol_CVAR_dict = Dict()
numb_viol_WCVAR_dict = Dict()
add_numb_viol_WCVAR_dict = Dict()
add_mean_viol_WCVAR_dict = Dict()

epsilons = rng = range(0.01, 0.1, step = 0.01)

sites  = ["70", "17", "68", "29", "12", "40", "58"]
mixes = ["MIX2"]

using PyCall, PyPlot
sns = pyimport("seaborn")
pygui(true)
plt.style.use("default")

for s in sites
    for m in mixes
        out_results_CVAR = NEW_out_DICT_CVAR["SITE$s","$m"]
        in_results_CVAR = NEW_in_DICT_CVAR["SITE$s","$m"]
        out_results_WCVAR = NEW_out_DICT_WCVAR["SITE$s","$m"]
        in_results_WCVAR = NEW_in_DICT_WCVAR["SITE$s","$m"]

        add_out_results_WCVAR = ADD_out_DICT_WCVAR["SITE$s","$m"]
        add_in_results_WCVAR = ADD_in_DICT_WCVAR["SITE$s","$m"]

        mean_cost = []
        mean_viol = []
        reliability_CVAR = []
        reliability_CVAR_perc_up = []
        reliability_CVAR_perc_down = []
        numb_viol_CVAR = []
        perc95_viol_CVAR = []
        max_viol_CVAR = []

        mean_cost_WCVAR = []
        mean_viol_WCVAR = []
        reliability_WCVAR = []
        reliability_WCVAR_perc_up = []
        reliability_WCVAR_perc_down = []
        numb_viol_WCVAR = []
        perc95_viol_WCVAR = []
        max_viol_WCVAR = []

        add_mean_cost_WCVAR = []
        add_mean_viol_WCVAR = []
        add_reliability_WCVAR = []
        add_reliability_WCVAR_perc_up = []
        add_reliability_WCVAR_perc_down = []
        add_numb_viol_WCVAR = []
        add_perc95_viol_WCVAR = []
        add_max_viol_WCVAR = []



        for eps in rng

            CVAR = out_results_CVAR |>
              @filter(_.ϵ == eps) |>
              DataFrame

            push!(mean_cost, mean(CVAR.cost_AGG))
            rel = (1 - sum(CVAR.numb_viol)/(length(CVAR.ϵ).*5 .* 96))
            push!(reliability_CVAR, rel)
            push!(reliability_CVAR_perc_up, percentile((1 .- (CVAR.numb_viol)./(length(CVAR.ϵ).*5 .* 96)), 95))
            push!(reliability_CVAR_perc_down, percentile((1 .- (CVAR.numb_viol)./(length(CVAR.ϵ).*5 .* 96)), 5))

            push!(numb_viol_CVAR, sum(CVAR.numb_viol))
            push!(perc95_viol_CVAR, percentile((CVAR.sum_upper + CVAR.sum_lower), 99))

            push!(mean_viol, mean(CVAR.sum_upper + CVAR.sum_lower))
            push!(max_viol_CVAR, max(CVAR.max_upper..., CVAR.max_lower...))


        end

        for eps in rng

            WCVAR = out_results_WCVAR |>
              @filter(_.ϵ == eps) |>
              DataFrame

            push!(mean_cost_WCVAR, mean(WCVAR.cost_AGG))
            rel = (1 - sum(WCVAR.numb_viol)/(length(WCVAR.ϵ).*5 .* 96))
            push!(reliability_WCVAR, rel)
            push!(reliability_WCVAR_perc_up, percentile((1 .- (WCVAR.numb_viol)./(length(WCVAR.ϵ).*5 .* 96)), 95))
            push!(reliability_WCVAR_perc_down, percentile((1 .- (WCVAR.numb_viol)./(length(WCVAR.ϵ).*5 .* 96)), 5))

            push!(numb_viol_WCVAR, sum(WCVAR.numb_viol))
            push!(mean_viol_WCVAR, mean(WCVAR.sum_upper + WCVAR.sum_lower))
            push!(perc95_viol_WCVAR, percentile((WCVAR.sum_upper + WCVAR.sum_lower), 99))
            push!(max_viol_WCVAR, max(WCVAR.max_upper..., WCVAR.max_lower...))




        end

        for eps in range(0.1, 0.17; step =0.01)

            add_WCVAR = add_out_results_WCVAR |>
              @filter(_.ϵ == eps) |>
              DataFrame

              push!(add_mean_cost_WCVAR, mean(add_WCVAR.cost_AGG))
              rel = (1 - sum(add_WCVAR.numb_viol)/(length(add_WCVAR.ϵ).*5 .* 96))
              push!(add_reliability_WCVAR, rel)
              push!(add_reliability_WCVAR_perc_up, percentile((1 .- (add_WCVAR.numb_viol)./(length(add_WCVAR.ϵ).*5 .* 96)), 95))
              push!(add_reliability_WCVAR_perc_down, percentile((1 .- (add_WCVAR.numb_viol)./(length(add_WCVAR.ϵ).*5 .* 96)), 5))
              push!(add_mean_viol_WCVAR, mean(add_WCVAR.sum_upper + add_WCVAR.sum_lower))

              push!(add_numb_viol_WCVAR, sum(add_WCVAR.numb_viol))
              push!(add_perc95_viol_WCVAR, percentile((add_WCVAR.sum_upper + add_WCVAR.sum_lower), 99))
              push!(add_max_viol_WCVAR, max(add_WCVAR.max_upper..., add_WCVAR.max_lower...))

        end


        mean_costs_CVAR["SITE$s","$m"] = -mean_cost
        mean_costs_WCVAR["SITE$s","$m"] = -mean_cost_WCVAR
        add_mean_costs_WCVAR["SITE$s","$m"] = -add_mean_cost_WCVAR

        # cost_scaled_CVAR["SITE$s","$m"]  = scaled_cost_CVAR
        # cost_scaled_WCVAR["SITE$s","$m"]  = scaled_cost_WCVAR

        rels_CVAR["SITE$s","$m"] = reliability_CVAR
        rels_WCVAR["SITE$s","$m"] = reliability_WCVAR
        add_rels_WCVAR["SITE$s","$m"] = add_reliability_WCVAR


        numb_viol_CVAR_dict["SITE$s","$m"] = numb_viol_CVAR
        numb_viol_WCVAR_dict["SITE$s","$m"] = numb_viol_WCVAR
        add_numb_viol_WCVAR_dict["SITE$s","$m"] = add_numb_viol_WCVAR

        mean_viol_CVAR_dict["SITE$s","$m"] = mean_viol
        mean_viol_WCVAR_dict["SITE$s","$m"] = mean_viol_WCVAR
        add_mean_viol_WCVAR_dict["SITE$s","$m"] = add_mean_viol_WCVAR

        perc95_viol_CVAR_dict["SITE$s","$m"] = perc95_viol_CVAR
        perc95_viol_WCVAR_dict["SITE$s","$m"] = perc95_viol_WCVAR
        add_perc95_viol_WCVAR_dict["SITE$s","$m"] = add_perc95_viol_WCVAR


        max_viol_CVAR_dict["SITE$s","$m"] = max_viol_CVAR
        max_viol_WCVAR_dict["SITE$s","$m"] = max_viol_WCVAR
        add_max_viol_WCVAR_dict["SITE$s","$m"] = add_max_viol_WCVAR

        # rels_norm_CVAR["SITE$s","$m"] = rel_out_vs_in_CVAR
        # rels_norm_WCVAR["SITE$s","$m"] = rel_out_vs_in_WCVAR
    end
end



cvar = NEW_out_DICT_CVAR["SITE29","MIX2"] |>
  @filter(_.cost_AGG <= -440) |>
  DataFrame

wcvar = NEW_out_DICT_WCVAR["SITE29","MIX2"] |>
    @filter(_.cost_AGG <= -440) |>
    DataFrame

add_wcvar = ADD_out_DICT_WCVAR["SITE29","MIX2"] |>
    @filter(_.cost_AGG <= -440) |>
    DataFrame

#adding up the dataframes
wcvar = [wcvar; add_wcvar]


sns.set_context("paper", font_scale=1.8)
sns.set_style("whitegrid")
sns.set_style("ticks")
sns.color_palette()


p = sns.JointGrid()
sns.kdeplot(color = "tab:blue", x=-wcvar.cost_AGG[:], y=max((wcvar.max_upper, wcvar.max_lower)...),  ax=p.ax_joint, alpha = 0.8, stat = "density", common_norm = true, label = "WCVaR")
sns.kdeplot(color = "tab:orange", x=-cvar.cost_AGG[:], y=max((cvar.max_upper, cvar.max_lower)...), ax=p.ax_joint, alpha = 0.8, stat = "density", common_norm = true, label = "CVaR")

sns.histplot(color = "tab:blue", y=max((wcvar.max_upper, wcvar.max_lower)...),  ax=p.ax_marg_y, element="step", stat = "density", alpha = 0.5)
sns.histplot(color = "tab:orange", y=max((cvar.max_upper, cvar.max_lower)...),  ax=p.ax_marg_y, element="step", stat = "density", alpha = 0.5)
sns.histplot(color = "tab:blue", x=-wcvar.cost_AGG[:],  ax=p.ax_marg_x, element="step", stat = "density", alpha = 0.5)
sns.histplot(color = "tab:orange", x=-cvar.cost_AGG[:],  ax=p.ax_marg_x, element="step", stat = "density", alpha = 0.5)

# plt.legend()
plt.ylim(0.0, 1.5)
mpatches = pyimport("matplotlib.patches")
blue_patch = mpatches.Patch(color="tab:blue", alpha = 0.5, label="WCVaR")
red_patch = mpatches.Patch(color="tab:orange", alpha = 0.5, label="CVaR")

text = mpatches.Patch(label = "29, d=0.501",fc="w", fill=false, edgecolor="none", linewidth=0)

p.ax_joint.legend(handles=[blue_patch, red_patch, text], ncol =1, loc = "upper right")
