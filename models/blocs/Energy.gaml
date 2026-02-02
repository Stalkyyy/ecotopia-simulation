/**
* Name: Energy
* Based on the internal empty template. 
* Author: Enzo Pinho Fernandes
* Tags: 
*/

model Energy
import "../API/API.gaml"

global {

	// API usage
	list<string> production_inputs_E <- ["L water", "m² land", "kg_cotton"];
	list<string> production_outputs_E <- ["kWh energy"];
	list<string> production_emissions_E <- ["gCO2e emissions"];
	 
	// Time scale (must stay consistent with Demography: 12 ticks = 1 year)
	int nb_ticks_per_year <- 12;
	
	// Initial production capacity for initial infrastructure (= total energy consumption, all sources, France)
	float initial_total_capacity_kwh <- 1.254e12 / nb_ticks_per_year;	
	
	// Energy mix target
	float nuclear_mix <- 0.40;
	float solar_mix <- 0.25;
	float wind_mix <- 0.15;
	float hydro_mix <- 0.20;
	
	// Stochasticity and system pressure
	bool enable_energy_stochasticity <- true;
	float network_losses_rate <- 0.079; 		// share of production lost in transmission/distribution (mean)
	
	// Demand fluctuations
	float demand_seasonality_amp <- 0.10; 				// more or less 10% seasonal swing
	float demand_seasonality_phase <- 1.57079633; 		// peak Jan (winter)
	float demand_noise_std <- 0.05; 					// gaussian noise (fraction of demand)
	float individual_noise_std <- 0.03; 				// per-person noise (fraction)
	float demand_multiplier_min <- 0.70;
	float demand_multiplier_max <- 1.30;
	
	// Shortage monitoring & build planning
	int demand_ma_window_months <- 12; 			// moving average window for demand forecast
	float shortage_alert_ratio <- 0.05; 		// threshold for "red" shortage (e.g., 5%)
	float shortage_buffer_threshold <- 0.20; 	// trigger builds when (remaining + pipeline) / demand < threshold
	int max_builds_per_tick_per_source <- 50; 	// cap to avoid explosive construction
	int fast_build_horizon_months <- 6; 		// horizon for fast techs (solar/wind)
	int long_build_horizon_months <- 36; 		// horizon for long techs (nuclear/hydro)
	float fast_build_share <- 0.85; 			// share of buffer gap allocated to fast build even without deficit
	
	// Source availability (outages + seasonality)
	float outage_prob_monthly <- 0.01;
	float outage_capacity_loss_min <- 0.05;
	float outage_capacity_loss_max <- 0.30;
	float availability_min <- 0.40;
	float availability_max <- 1.00;
	
	float nuclear_seasonality_amp <- 0.02;
	float solar_seasonality_amp <- 0.20;
	float wind_seasonality_amp <- 0.10;
	float hydro_seasonality_amp <- 0.15;
	
	// Phases chosen to align seasonal peak months for France, in radians
	// - (month_index: 0=Jan ... 11=Dec)
	float nuclear_seasonality_phase <- 1.57079633; 		// peak Jan (winter)
	float solar_seasonality_phase <- -1.57079633;  		// peak Jul (summer)
	float wind_seasonality_phase <- 1.57079633;    		// peak Jan (winter)
	float hydro_seasonality_phase <- -4.18879020;  		// peak Dec (late autumn/early winter)
	
	// Climate shock: drought (affects hydro)
	float drought_prob_monthly <- 0.005;
	int drought_duration_months <- 6;
	float drought_hydro_capacity_mult <- 0.60;
	
	// Tick state for stochasticity
	float current_demand_multiplier <- 1.0;
	map<string, float> availability_factor_by_source <- [
		"nuclear"::1.0,
		"solar"::1.0,
		"wind"::1.0,
		"hydro"::1.0
	];
	bool drought_active <- false;
	int drought_remaining <- 0;
	 
	// Config and data (loaded directly at global definition time, like in Demography)
	map<string, map<string, float>> energy_cfg <- load_energy_cfg("../data/data_energy.csv");
	map<string, float> human_cfg <- load_human_energy_cfg("../data/data_human_energy.csv");
	
	// Resource needs per site and per phase (per tick)
	map<string, map<string, float>> construction_site_inputs_E <- [
		"nuclear"::["kg_cotton"::8.3e6, "L water"::4.2e7],
		"solar"::["kg_cotton"::1.0e5, "L water"::1.0e5],
		"wind"::["kg_cotton"::3.0e5, "L water"::2.0e5],
		"hydro"::["kg_cotton"::8.3e7, "L water"::1.7e7]
	];
	map<string, map<string, float>> maintenance_site_inputs_E <- [
		"nuclear"::["kg_cotton"::5.0e6, "L water"::2.5e7],
		"solar"::["kg_cotton"::1.5e5, "L water"::1.25e5],
		"wind"::["kg_cotton"::2.5e5, "L water"::2.5e5],
		"hydro"::["kg_cotton"::3.3e7, "L water"::1.7e7]
	];
		
	// Aggregated tick counters
	map<string, float> tick_production_E <- [];
	map<string, float> tick_resources_used_E <- [];
	map<string, float> tick_emissions_E <- [];
	map<string, float> tick_pop_consumption_E <- [];
	map<string, float> tick_losses_E <- [];
	
	// Aggregated capacity indicators (kWh)
	float tick_total_installed_capacity_kwh <- 0.0;      // total capacity of all sites (operational + construction + maintenance)
	float tick_total_available_capacity_kwh <- 0.0;     // capacity from operational sites only
	float tick_total_remaining_capacity_kwh <- 0.0;     // remaining producible kWh this tick after production
	float tick_pipeline_capacity_kwh <- 0.0;            // capacity in construction/maintenance within horizon
	float tick_buffer_ratio <- 0.0;                     // (remaining + pipeline) / demand
	float tick_deficit_now_kwh <- 0.0;                  // current net deficit (demand - net production)
	 
	// Per source tick counters (initialized from energy_cfg keys)
	map<string, map<string, float>> tick_sub_production_E <- init_tick_source_map();
	map<string, map<string, float>> tick_sub_resources_used_E <- init_tick_source_map();
	map<string, map<string, float>> tick_sub_emissions_E <- init_tick_source_map();
	map<string, int> tick_sub_nb_installations <- init_tick_source_count_map();
	map<string, int> tick_sub_nb_operational_sites <- init_tick_source_count_map();
	map<string, int> tick_sub_nb_unavailable_sites <- init_tick_source_count_map();

	init{ 
		if (length(coordinator) = 0){
			error "Coordinator agent not found. Ensure you launched the experiment from the Main model";
		}
	}

	map<string, map<string, float>> load_energy_cfg(string filename){
		file config_csv <- csv_file(filename, ",", true);
		matrix config_matrix <- matrix(config_csv);
		list<string> headers <- config_csv.attributes;
		map<string, map<string, float>> cfg <- [];
		loop i from:0 to:config_matrix.rows-1 {
			string source_name <- string(config_matrix[0,i]);
			cfg[source_name] <- [];
			loop j from:1 to:length(headers) - 1 {
				cfg[source_name][headers[j]] <- float(config_matrix[j,i]);
			}
		}
		return cfg;
	}

	map<string, float> load_human_energy_cfg(string filename){
		file config_csv <- csv_file(filename, ",", true);
		matrix config_matrix <- matrix(config_csv);
		list<string> headers <- config_csv.attributes;
		map<string, float> cfg <- [];
		loop j from:0 to:length(headers)-1 {
			cfg[headers[j]] <- float(config_matrix[j,0]);
		}
		
		tick_losses_E["kWh energy"] <- 0.0;
		return cfg;
	}

	map<string, map<string, float>> init_tick_source_map {
		map<string, map<string, float>> m <- [];
		loop source_name over: energy_cfg.keys {
			m[source_name] <- [];
		}
		return m;
	}

	map<string, int> init_tick_source_count_map {
		map<string, int> m <- [];
		loop source_name over: energy_cfg.keys {
			m[source_name] <- 0;
		}
		return m;
	}
}





/**
 * Energy bloc - Main coordination species
 * Manages aggregated national energy production from 4 sources
 * Implements API methods for integration with coordinator
 */
species energy parent:bloc {
	string name <- "energy";
		
	energy_producer producer <- nil;
	energy_consumer consumer <- nil;
	
	action setup{
		create energy_producer number:1 returns:producers;
		create energy_consumer number:1 returns:consumers;
		producer <- first(producers);
		consumer <- first(consumers);

		// Create sub-producers for each source (as micro-species)
		ask producer{
			do create_energy_sources;
		}
	}
	
	action tick(list<human> pop, list<mini_ville> cities) {
		do update_stochastic_state();
		do collect_last_tick_data();
		do population_activity(pop);
	}
	
	production_agent get_producer{
		return producer;
	}

	list<string> get_output_resources_labels{
		return production_outputs_E;
	}
	
	list<string> get_input_resources_labels{
		return production_inputs_E;
	}
	
	action set_external_producer(string product, bloc bloc_agent){
		ask producer {
			do set_supplier(product, bloc_agent);
		}
	}
	
	action collect_last_tick_data{
		//if (cycle > 0) {
			tick_pop_consumption_E <- consumer.get_tick_consumption(); 		// collect consumption behaviors
			
			ask producer { do snapshot_sub_tick_data; }
	    	tick_resources_used_E <- producer.get_tick_inputs_used(); 		// collect resources used
	    	tick_production_E <- producer.get_tick_outputs_produced(); 		// collect production
	    	tick_emissions_E <- producer.get_tick_emissions(); 				// collect emissions
	    	ask producer {
	    		do plan_construction_after_tick(
	    			tick_pop_consumption_E["kWh energy"],
	    			tick_production_E["kWh energy"] - tick_losses_E["kWh energy"],
	    			tick_total_remaining_capacity_kwh
	    		);
	    	}
	    	
	    	ask energy_consumer{ // prepare next tick on consumer side
	    		do reset_tick_counters;
	    	}
	    	
	    	ask energy_producer{ // prepare next tick on producer side
	    		do reset_tick_counters;
	    	}
		//}
	}
	

	action update_stochastic_state{
		if (!enable_energy_stochasticity) {
			current_demand_multiplier <- 1.0;
			loop s over: availability_factor_by_source.keys {
				availability_factor_by_source[s] <- 1.0;
			}
			drought_active <- false;
			drought_remaining <- 0;
			return;
		}
		
		int month_index <- int(cycle mod 12);
		float season_angle <- (2.0 * 3.14159265) * (month_index / 12.0);
		
		float demand_season <- 1.0 + demand_seasonality_amp * sin(season_angle + demand_seasonality_phase);
		float demand_noise <- (demand_noise_std > 0.0) ? gauss(0.0, demand_noise_std) : 0.0;
		float demand_mult <- demand_season * (1.0 + demand_noise);
		current_demand_multiplier <- max(demand_multiplier_min, min(demand_multiplier_max, demand_mult));
		
		// Update drought state
		if (drought_remaining > 0) {
			drought_active <- true;
			drought_remaining <- drought_remaining - 1;
		} else {
			drought_active <- false;
			if (rnd(1.0) < drought_prob_monthly) {
				drought_active <- true;
				drought_remaining <- max(1, drought_duration_months) - 1;
			}
		}
		
		loop s over: availability_factor_by_source.keys {
			float season_mult <- 1.0;
			if (s = "nuclear") { season_mult <- 1.0 + nuclear_seasonality_amp * sin(season_angle + nuclear_seasonality_phase); }
			if (s = "solar") { season_mult <- 1.0 + solar_seasonality_amp * sin(season_angle + solar_seasonality_phase); }
			if (s = "wind") { season_mult <- 1.0 + wind_seasonality_amp * sin(season_angle + wind_seasonality_phase); }
			if (s = "hydro") { season_mult <- 1.0 + hydro_seasonality_amp * sin(season_angle + hydro_seasonality_phase); }
			
			float outage_loss <- 0.0;
			if (rnd(1.0) < outage_prob_monthly) {
				outage_loss <- outage_capacity_loss_min + rnd(outage_capacity_loss_max - outage_capacity_loss_min);
			}
			
			float shock_mult <- (s = "hydro" and drought_active) ? drought_hydro_capacity_mult : 1.0;
			
			float availability <- (1.0 - outage_loss) * season_mult * shock_mult;
			availability_factor_by_source[s] <- max(availability_min, min(availability_max, availability));
		}
	}
	
	
	action population_activity(list<human> pop) {
    	ask pop{ // execute the consumption behavior of the population
    		ask myself.energy_consumer{
    			do consume(myself); // individuals consume energy
    		}
    	}
    	 
    	ask energy_consumer{ // produce the required quantities
    		ask energy_producer{
    			loop c over: myself.consumed.keys{
		    		do produce("energy", [c::myself.consumed[c]]);
		    	}
		    } 
    	}
    }

    
    
    
    
    
    /**
     * National energy producer aggregator
     * Orchestrates production across multiple energy sources, distributes demand according to mix ratios and aggregates outputs/resources/emissions.
     */
	species energy_producer parent:production_agent {
		map<string, bloc> external_producers;
		
		// Sub-producer references
		map<string, sub_energy_producer_base> sub_producers <- [];
		
		map<string, float> tick_resources_used <- [];
		map<string, float> tick_production <- [];
		map<string, float> tick_emissions <- [];
		
		map<string, float> get_tick_inputs_used{		
			return tick_resources_used;
		}
		map<string, float> get_tick_outputs_produced{
			return tick_production;
		}
		map<string, float> get_tick_emissions{
			return tick_emissions;
		}

		action reset_tick_counters{
			loop sub_producer over:sub_producers {
				ask sub_producer {
					do reset_tick_counters;
				}
			}
		}
		
		float get_pipeline_capacity_within(int horizon_months){
			float total <- 0.0;
			loop sp over: sub_producers {
				total <- total + sp.get_pipeline_capacity_within(horizon_months);
			}
			return total;
		}
		
		float get_pipeline_capacity_for_sources(list<string> sources, int horizon_months){
			float total <- 0.0;
			loop s over: sources {
				if (s in sub_producers.keys) {
					total <- total + sub_producers[s].get_pipeline_capacity_within(horizon_months);
				}
			}
			return total;
		}
		
		action build_for_kwh(string source, float needed_kwh){
			if (needed_kwh <= 0.0) {
				return;
			}
			float cap_per_install <- energy_cfg[source]["capacity_per_installation_kwh"];
			int n_needed <- int(ceil(needed_kwh / cap_per_install));
			int n_to_build <- min(n_needed, max_builds_per_tick_per_source);
			if (n_to_build <= 0) {
				return;
			}
			if (source in sub_producers.keys) {
				ask sub_producers[source] {
					do try_build_installations(n_to_build * cap_per_install);
				}
			}
		}
		
		// Triggered at end of tick: build when buffer (remaining + pipeline) is below threshold
		action plan_construction_after_tick(float demand_kwh, float net_production_kwh, float remaining_kwh){
			if (demand_kwh <= 0.0) {
				return;
			}
			
			// Separate pipeline for fast vs long techs
			float pipeline_fast <- get_pipeline_capacity_for_sources(["solar", "wind"], fast_build_horizon_months);
			float pipeline_long <- get_pipeline_capacity_for_sources(["nuclear", "hydro"], long_build_horizon_months);
			tick_pipeline_capacity_kwh <- pipeline_fast + pipeline_long;
			tick_deficit_now_kwh <- max(0.0, demand_kwh - net_production_kwh);
			tick_buffer_ratio <- (remaining_kwh + tick_pipeline_capacity_kwh) / demand_kwh;
			
			if (tick_buffer_ratio >= shortage_buffer_threshold) {
				return;
			}
			
			// Compute buffer gap and allocate a share to fast build even without deficit
			float buffer_gap_kwh <- max(0.0, (shortage_buffer_threshold * demand_kwh) - (remaining_kwh + tick_pipeline_capacity_kwh));
			float fast_need <- max(tick_deficit_now_kwh, buffer_gap_kwh * fast_build_share);
			if (fast_need > 0.0) {
				float fast_wind <- fast_need * 0.5;
				float fast_solar <- fast_need - fast_wind;
				do build_for_kwh("wind", fast_wind);
				do build_for_kwh("solar", fast_solar);
			}
			
			// Long-term response: build according to target mix
			float long_need <- buffer_gap_kwh;
			if (long_need <= 0.0) {
				return;
			}
			
			do build_for_kwh("nuclear", long_need * nuclear_mix);
			do build_for_kwh("solar", long_need * solar_mix);
			do build_for_kwh("wind", long_need * wind_mix);
			do build_for_kwh("hydro", long_need * hydro_mix);
		}
		
		action not_sub_reset_tick {
			loop u over: production_inputs_E{
				tick_resources_used[u] <- 0.0;
			}
			loop p over: production_outputs_E{
				tick_production[p] <- 0.0;
			}
			loop e over: production_emissions_E{
				tick_emissions[e] <- 0.0;
			}
			tick_losses_E["kWh energy"] <- 0.0;
		}

		
		/**
		 * Create the national energy source managers
		 */
		action create_energy_sources{			
			create nuclear_producer number:1 returns:nuc;
			create solar_producer number:1 returns:sol;
			create wind_producer number:1 returns:wnd;
			create hydro_producer number:1 returns:hyd;
			
			sub_producers["nuclear"] <- first(nuc);
			sub_producers["solar"] <- first(sol);
			sub_producers["wind"] <- first(wnd);
			sub_producers["hydro"] <- first(hyd);
			
			// Initialize existing production sites according to desired mix
			do initialize_initial_sites;
		}
		
		action initialize_initial_sites {
			float target_capacity_nuclear <- initial_total_capacity_kwh * nuclear_mix;
			float target_capacity_solar <- initial_total_capacity_kwh * solar_mix;
			float target_capacity_wind <- initial_total_capacity_kwh * wind_mix;
			float target_capacity_hydro <- initial_total_capacity_kwh * hydro_mix;
			
			int n_nuclear <- int(target_capacity_nuclear / energy_cfg["nuclear"]["capacity_per_installation_kwh"]);
			int n_solar <- int(target_capacity_solar / energy_cfg["solar"]["capacity_per_installation_kwh"]);
			int n_wind <- int(target_capacity_wind / energy_cfg["wind"]["capacity_per_installation_kwh"]);
			int n_hydro <- int(target_capacity_hydro / energy_cfg["hydro"]["capacity_per_installation_kwh"]);
			
			if ("nuclear" in sub_producers.keys) {
				ask sub_producers["nuclear"] { do create_initial_sites(n_nuclear); }
			}
			if ("solar" in sub_producers.keys) {
				ask sub_producers["solar"] { do create_initial_sites(n_solar); }
			}
			if ("wind" in sub_producers.keys) {
				ask sub_producers["wind"] { do create_initial_sites(n_wind); }
			}
			if ("hydro" in sub_producers.keys) {
				ask sub_producers["hydro"] { do create_initial_sites(n_hydro); }
			}
		}
		
		
		/**
		 * Orchestrate national energy production across all sources according to energy mix ratios
		 */
		map<string, unknown> produce(string bloc_name, map<string, float> demand) {
			float total_energy_demanded <- 0.0;
			if ("kWh energy" in demand.keys) {
				total_energy_demanded <- demand["kWh energy"];
			}
			
			float gross_energy_demanded <- total_energy_demanded;
			if (enable_energy_stochasticity and network_losses_rate > 0.0) {
				gross_energy_demanded <- total_energy_demanded / (1.0 - network_losses_rate);
				tick_losses_E["kWh energy"] <- gross_energy_demanded - total_energy_demanded;
			}

			map<string, float> mix_ratios <- [
				"nuclear"::nuclear_mix,
				"solar"::solar_mix,
				"wind"::wind_mix,
				"hydro"::hydro_mix
			];
			
			// Execute production per energy source
			bool ok <- true;
			float total_allocated_gross_kwh <- 0.0;
			loop sub_producer over:sub_producers {	
				string source_name <- sub_producer.get_source_name();		
				float source_energy_requested <- gross_energy_demanded * mix_ratios[source_name];
				ask sub_producer {
					map<string, unknown> info <- produce("energy", ["kWh energy"::source_energy_requested]);
					if ("allocated_kwh" in info.keys) {
						total_allocated_gross_kwh <- total_allocated_gross_kwh + float(info["allocated_kwh"]);
					}
				}				
			}
			
			float transmitted_kwh <- total_allocated_gross_kwh;
			if (enable_energy_stochasticity and network_losses_rate > 0.0) {
				transmitted_kwh <- total_allocated_gross_kwh * (1.0 - network_losses_rate);
			}
			
			if (transmitted_kwh + 1e-6 < total_energy_demanded) {
				ok <- false;
			}
			
			map<string, unknown> prod_info <- [
            	"ok"::ok,
            	"transmitted_kwh"::transmitted_kwh
            ];
							       
			return prod_info;
		}
		
		// To update the finals values to print in experiments.
        action snapshot_sub_tick_data {
			do not_sub_reset_tick();
			
			// reset aggregated capacity indicators
			tick_total_installed_capacity_kwh <- 0.0;
			tick_total_available_capacity_kwh <- 0.0;
			tick_total_remaining_capacity_kwh <- 0.0;
			
			loop sub_producer over:sub_producers {
                string source_name <- sub_producer.get_source_name();
                map<string, float> sub_prod <- sub_producer.get_tick_outputs_produced();
                map<string, float> sub_inputs <- sub_producer.get_tick_inputs_used();
                map<string, float> sub_emis <- sub_producer.get_tick_emissions();
	            
				// capacity indicators per source
				float sub_installed_capacity <- sub_producer.get_total_installed_capacity_kwh();
				float sub_available_capacity <- sub_producer.get_total_capacity_kwh();
				float sub_remaining_capacity <- sub_producer.get_remaining_capacity_kwh_this_tick();
			
				tick_total_installed_capacity_kwh <- tick_total_installed_capacity_kwh + sub_installed_capacity;
				tick_total_available_capacity_kwh <- tick_total_available_capacity_kwh + sub_available_capacity;
				tick_total_remaining_capacity_kwh <- tick_total_remaining_capacity_kwh + sub_remaining_capacity;
                
                tick_sub_production_E[source_name] <- copy(sub_prod);
                tick_sub_resources_used_E[source_name] <- copy(sub_inputs);
                tick_sub_emissions_E[source_name] <- copy(sub_emis);
                
                loop p over: production_outputs_E {
                	if (p in tick_sub_production_E[source_name].keys) {
                		tick_production[p] <- tick_production[p] + tick_sub_production_E[source_name][p];
                	}
                }
                loop u over: production_inputs_E {
                	if (u in tick_sub_resources_used_E[source_name].keys) {
                		tick_resources_used[u] <- tick_resources_used[u] + tick_sub_resources_used_E[source_name][u];
                	}
                }
                loop e over: production_emissions_E {
                	if (e in tick_sub_emissions_E[source_name].keys) {
                		tick_emissions[e] <- tick_emissions[e] + tick_sub_emissions_E[source_name][e];
                	}
                }
                
				tick_sub_nb_installations[source_name] <- sub_producer.get_nb_installations();
				tick_sub_nb_operational_sites[source_name] <- sub_producer.get_nb_operational_sites();
				tick_sub_nb_unavailable_sites[source_name] <- sub_producer.get_nb_unavailable_sites();
            }
        }
		
		action set_supplier(string product, bloc bloc_agent){
			loop sub_producer over:sub_producers.values {
				ask sub_producer {
					do set_supplier(product, bloc_agent);
				}
			}
		}
	}
	
	
	
	
	/**
	 * Base class for individual energy source managers
	 * Handles production logic for a single energy source
	 */
	species sub_energy_producer_base parent:production_agent {		
		map<string, bloc> external_producers;
		
		string source_name <- "NULL"; // Its important to initialize it !!

		/*
		 * State and tick metrics
		 */
		int lifetime_ticks_max_site <- 0;
		int construction_ticks_max_site <- 0;
		int maintenance_ticks_max_site <- 0;
		float land_per_site <- 0.0;
		float remaining_capacity_kwh_this_tick <- 0.0;
		float base_capacity_kwh_this_tick <- 0.0;
		float land_occupied_m2 <- 0.0;
		map<string, float> tick_resources_used <- [];
		map<string, float> tick_production <- [];
		map<string, float> tick_emissions <- [];
		
		// List of sites:
		// Fields: "status" (string: "construction" or "operational" or "maintenance"),
		//         "construction_remaining", "lifetime_remaining", "maintenance_remaining" (int)
		list<map<string, unknown>> sites <- [];
		 
		string get_source_name {
			return source_name;
		}
		
		action update_tick_data {
			tick_sub_production_E[source_name] <- copy(tick_production);
			tick_sub_resources_used_E[source_name] <- copy(tick_resources_used);
			tick_sub_emissions_E[source_name] <- copy(tick_emissions);
		}
		 
		float get_total_capacity_kwh {
			int nb_operational <- 0;
			loop s over: sites {
				if (string(s["status"]) = "operational") {
					nb_operational <- nb_operational + 1;
				}
			}
			return nb_operational * energy_cfg[source_name]["capacity_per_installation_kwh"];
		}
		
		float get_total_installed_capacity_kwh {
			int nb_sites <- length(sites);
			return nb_sites * energy_cfg[source_name]["capacity_per_installation_kwh"];
		}
		
		float get_pipeline_capacity_within(int horizon_months){
			if (horizon_months <= 0) {
				return 0.0;
			}
			int nb_pipeline <- 0;
			loop s over: sites {
				string st <- string(s["status"]);
				if (st = "construction") {
					int rem_c <- int(s["construction_remaining"]);
					if (rem_c <= horizon_months) {
						nb_pipeline <- nb_pipeline + 1;
					}
				} else if (st = "maintenance") {
					int rem_m <- int(s["maintenance_remaining"]);
					if (rem_m <= horizon_months) {
						nb_pipeline <- nb_pipeline + 1;
					}
				}
			}
			return nb_pipeline * energy_cfg[source_name]["capacity_per_installation_kwh"];
		}
		
		float get_remaining_capacity_kwh_this_tick {
			return remaining_capacity_kwh_this_tick;
		}
		
		map<string, float> get_tick_inputs_used { 
			return tick_resources_used;
		}
		map<string, float> get_tick_outputs_produced { 
			return tick_production;
		}
		map<string, float> get_tick_emissions { 
			return tick_emissions;
		}
		
		int get_nb_installations {
			return length(sites);
		}
		
		int get_nb_operational_sites {
			int nb <- 0;
			loop s over: sites {
				if (string(s["status"]) = "operational") {
					nb <- nb + 1;
				}
			}
			return nb;
		}
		
		int get_nb_unavailable_sites {
			int nb <- 0;
			loop s over: sites {
				string st <- string(s["status"]);
				if (st = "construction" or st = "maintenance") {
					nb <- nb + 1;
				}
			}
			return nb;
		}
		
		action set_supplier(string product, bloc bloc_agent){
			write name+": external producer "+bloc_agent+" set for"+product;
			external_producers[product] <- bloc_agent;
		}
		
		/*
		 * Create initial sites that are already built and operational at t0.
		 * Their remaining lifetimes are uniformly distributed over [1, lifetime_ticks_max].
		 */
		action create_initial_sites(int n_sites) {
			if (n_sites <= 0) {
				return;
			}

			// Initialize per-site parameters from configuration
			land_per_site <- energy_cfg[source_name]["land_per_installation_m2"];
			lifetime_ticks_max_site <- int(energy_cfg[source_name]["lifetime_y"] * nb_ticks_per_year);
			construction_ticks_max_site <- int(energy_cfg[source_name]["construction_duration_y"] * nb_ticks_per_year);
			maintenance_ticks_max_site <- int(energy_cfg[source_name]["maintainance_duration"] * nb_ticks_per_year);
			
			loop i from:1 to:n_sites {
				int init_lifetime <- rnd(lifetime_ticks_max_site);
				map<string, unknown> site <- [
					"status"::"operational",
					"construction_remaining"::0,
					"lifetime_remaining"::init_lifetime,
					"maintenance_remaining"::0
				];
				sites <- sites + [site];
			}
		}
		 
		action reset_tick_counters {
			// reset aggregated tick counters
			loop u over: production_inputs_E{
				tick_resources_used[u] <- 0.0;
			}
			loop p over: production_outputs_E{
				tick_production[p] <- 0.0;
			}
			loop e over: production_emissions_E{
				tick_emissions[e] <- 0.0;
			}

			// Progress lifecycle of each site independently and count sites per phase (for debug)
			int nb_total_sites <- length(sites);
			int nb_operational_sites <- 0;
			int nb_construction_sites <- 0;
			int nb_maintenance_sites <- 0;
			int nb_newly_built <- 0;
			int nb_entering_maintenance <- 0;
			int nb_leaving_maintenance <- 0;
			
			loop i from:0 to:length(sites)-1 {
				map<string, unknown> s <- sites[i];
				string status <- string(s["status"]);
				
				if (status = "construction") {
					int rem_c <- int(s["construction_remaining"]);
					if (rem_c > 0) {
						rem_c <- rem_c - 1;
					}
					if (rem_c <= 0) {
						status <- "operational";
						int rem_l <- lifetime_ticks_max_site;
						s["status"] <- "operational";
						s["construction_remaining"] <- 0;
						s["lifetime_remaining"] <- rem_l;
						s["maintenance_remaining"] <- 0;
						nb_newly_built <- nb_newly_built + 1;
					} else {
						s["construction_remaining"] <- rem_c;
					}
				}
				else if (status = "operational") {
					int rem_l <- int(s["lifetime_remaining"]);
					if (rem_l > 0) {
						rem_l <- rem_l - 1;
					}
					if (rem_l <= 0) {
						status <- "maintenance";
						int rem_m <- maintenance_ticks_max_site;
						s["status"] <- "maintenance";
						s["maintenance_remaining"] <- rem_m;
						s["lifetime_remaining"] <- 0;
						nb_entering_maintenance <- nb_entering_maintenance + 1;
					} else {
						s["lifetime_remaining"] <- rem_l;
					}
				}
				else if (status = "maintenance") {
					int rem_m <- int(s["maintenance_remaining"]);
					if (rem_m > 0) {
						rem_m <- rem_m - 1;
					}
					if (rem_m <= 0) {
						status <- "operational";
						int rem_l <- lifetime_ticks_max_site;
						s["status"] <- "operational";
						s["maintenance_remaining"] <- 0;
						s["lifetime_remaining"] <- rem_l;
						nb_leaving_maintenance <- nb_leaving_maintenance + 1;
					} else {
						s["maintenance_remaining"] <- rem_m;
					}
				}
				
				// Update phase counters based on status
				if (status = "operational") {
					nb_operational_sites <- nb_operational_sites + 1;
				} else if (status = "construction") {
					nb_construction_sites <- nb_construction_sites + 1;
				} else if (status = "maintenance") {
					nb_maintenance_sites <- nb_maintenance_sites + 1;
				}
				
				sites[i] <- s;
			}
			
			// Compute land occupation and per-phase resource needs
			land_occupied_m2 <- nb_total_sites * land_per_site;
			float site_phase_water <- 0.0;
			float site_phase_cotton <- 0.0;
			site_phase_water <- site_phase_water
				+ nb_construction_sites * construction_site_inputs_E[source_name]["L water"]
				+ nb_maintenance_sites * maintenance_site_inputs_E[source_name]["L water"];
			site_phase_cotton <- site_phase_cotton
				+ nb_construction_sites * construction_site_inputs_E[source_name]["kg_cotton"]
				+ nb_maintenance_sites * maintenance_site_inputs_E[source_name]["kg_cotton"];
			
			// Request construction/maintenance resources (water & cotton)
			if (site_phase_water > 0.0 and "L water" in external_producers.keys) {
				map<string, unknown> info_w <- external_producers["L water"].producer.produce("energy", ["L water"::site_phase_water]);
				if (bool(info_w["ok"])) {
					tick_resources_used["L water"] <- tick_resources_used["L water"] + site_phase_water;
				}
			}
			if (site_phase_cotton > 0.0 and "kg_cotton" in external_producers.keys) {
				map<string, unknown> info_c <- external_producers["kg_cotton"].producer.produce("energy", ["kg_cotton"::site_phase_cotton]);
				if (bool(info_c["ok"])) {
					tick_resources_used["kg_cotton"] <- tick_resources_used["kg_cotton"] + site_phase_cotton;
				}
			}
			
			// Logging of lifecycle events
			if (nb_newly_built > 0) {
				if (source_name = "nuclear") {
					write "[ENERGIE] " + nb_newly_built + " centrales nucléaires construites";
				} else if (source_name = "solar") {
					write "[ENERGIE] Construction de " + nb_newly_built + " parcs solaires construits";
				} else if (source_name = "wind") {
					write "[ENERGIE] Construction de " + nb_newly_built + " parcs éoliens construits";
				} else if (source_name = "hydro") {
					write "[ENERGIE] Construction de " + nb_newly_built + " barrages hydroélectriques construits";
				}
			}
			// if (nb_entering_maintenance > 0) {
			// 	if (source_name = "nuclear") {
			// 		write "[ENERGIE] Maintenance de " + nb_entering_maintenance + " centrales nucléaires";
			// 	} else if (source_name = "solar") {
			// 		write "[ENERGIE] Maintenance de " + nb_entering_maintenance + " parcs solaires";
			// 	} else if (source_name = "wind") {
			// 		write "[ENERGIE] Maintenance de " + nb_entering_maintenance + " parcs éoliens";
			// 	} else if (source_name = "hydro") {
			// 		write "[ENERGIE] Maintenance de " + nb_entering_maintenance + " barrages hydroélectriques";
			// 	}
			// }
			// if (nb_leaving_maintenance > 0) {
			// 	if (source_name = "nuclear") {
			// 		write "[ENERGIE] " + nb_leaving_maintenance + " centrales nucléaires sortent de maintenance";
			// 	} else if (source_name = "solar") {
			// 		write "[ENERGIE] " + nb_leaving_maintenance + " parcs solaires sortent de maintenance";
			// 	} else if (source_name = "wind") {
			// 		write "[ENERGIE] " + nb_leaving_maintenance + " parcs éoliens sortent de maintenance";
			// 	} else if (source_name = "hydro") {
			// 		write "[ENERGIE] " + nb_leaving_maintenance + " barrages hydroélectriques sortent de maintenance";
			// 	}
			// }
			
			base_capacity_kwh_this_tick <- get_total_capacity_kwh();
			remaining_capacity_kwh_this_tick <- base_capacity_kwh_this_tick * availability_factor_by_source[source_name];
			tick_resources_used["m² land"] <- land_occupied_m2;
		}
		 
		/**
		 * Dynamically construct energy installations to meet unmet demand. 
		 */
		action try_build_installations(float deficit_kwh) {
			int installations_needed <- int(ceil(deficit_kwh / energy_cfg[source_name]["capacity_per_installation_kwh"]));
			if (installations_needed <= 0) {
				return;
			}
			// Ensure per-site parameters are initialized even if no initial sites were created
			if (land_per_site <= 0.0) {
				land_per_site <- energy_cfg[source_name]["land_per_installation_m2"];
				lifetime_ticks_max_site <- int(energy_cfg[source_name]["lifetime_y"] * nb_ticks_per_year);
				construction_ticks_max_site <- int(energy_cfg[source_name]["construction_duration_y"] * nb_ticks_per_year);
				maintenance_ticks_max_site <- int(energy_cfg[source_name]["maintainance_duration"] * nb_ticks_per_year);
			}
			if ("m² land" in external_producers.keys) {
				int built <- 0;
				loop i from:1 to:installations_needed {
					map<string, unknown> info <- external_producers["m² land"].producer.produce("energy", ["m² land"::land_per_site]);
					if (bool(info["ok"])) {
						built <- built + 1;
					} else {
						break;
					}
				}
				if (built > 0) {
					// Create new sites in construction phase
					loop j from:1 to:built {
						int rem_c <- construction_ticks_max_site;
						map<string, unknown> site <- [
							"status"::"construction",
							"construction_remaining"::rem_c,
							"lifetime_remaining"::0,
							"maintenance_remaining"::0
						];
						sites <- sites + [site];
					}

					// Logging of new construction starts
					if (source_name = "nuclear") {
						write "[ENERGIE] Construction de " + built + " centrales nucléaires";
					} else if (source_name = "solar") {
						write "[ENERGIE] Construction de " + built + " parcs solaires";
					} else if (source_name = "wind") {
						write "[ENERGIE] Construction de " + built + " parcs éoliens";
					} else if (source_name = "hydro") {
						write "[ENERGIE] Construction de " + built + " barrages hydroélectriques";
					}
				}
			}
		}
		
		
		/**
		 * Allocate available production capacity and resources to fulfill an energy demand request.
		 * - For now, to not fight with the API file, we request water in 10% increments from Ecosystem Bloc, in case it has not enough water to share with us.
		 */
		map<string, float> allocate_resources(float requested_kwh) {
			map<string, float> result <- ["allocated_kwh"::0.0, "shortfall_kwh"::0.0];
			
			// No auto-build here; construction is handled by the planning step
			
			float theoretical_kwh <- min(requested_kwh, remaining_capacity_kwh_this_tick);
			float water_withdrawal_per_kwh <- energy_cfg[source_name]["total_water_input_per_kwh_l"];
			float water_consumption_per_kwh <- energy_cfg[source_name]["water_per_kwh_l"];
			
			float water_needed_total <- theoretical_kwh * water_withdrawal_per_kwh;
			float water_to_ask <- water_needed_total;
			float water_asked_per_loop <- water_needed_total * 0.10; // Every 10%
			float water_withdrawn <- 0.0;
			if (water_to_ask > 0 and "L water" in external_producers.keys){
				loop while: water_to_ask > 0 {
					float water_chunk <- min(water_asked_per_loop, water_to_ask);
					map<string, unknown> info <- external_producers["L water"].producer.produce("energy", ["L water"::water_chunk]);
					bool water_ok <- bool(info["ok"]);
					if (water_ok) {
						water_to_ask <- water_to_ask - water_chunk;
						water_withdrawn <- water_withdrawn + water_chunk;
					} else {
						break;
					}
				}
			}
			
			// Effective energy production is limited by actually withdrawn water
			float actual_alloc_kwh <- 0.0;
			if (water_withdrawal_per_kwh > 0.0) {
				actual_alloc_kwh <- min(theoretical_kwh, water_withdrawn / water_withdrawal_per_kwh);
			} else {
				actual_alloc_kwh <- theoretical_kwh;
			}
			
			// Fix computation error due to floats (eg. if the request is almost fulfilled by an epsilonesque delta, it's actually fulfilled)
			float alloc_delta <- theoretical_kwh - actual_alloc_kwh;
			if (alloc_delta >= 0.0 and alloc_delta <= max(1e-3, theoretical_kwh * 1e-10)) {
				actual_alloc_kwh <- theoretical_kwh;
			}
			
			float emissions_g <- actual_alloc_kwh * energy_cfg[source_name]["emissions_per_kwh"];
			do send_ges_to_ecosystem("energy", emissions_g);
			
			// Water accounting: part is consumed, the rest is reinjected
			float water_consumed <- actual_alloc_kwh * water_consumption_per_kwh;
			float water_reinjected <- max(0.0, water_withdrawn - water_consumed);
			if (water_reinjected > 0.0) {
				do reinject_water_to_ecosystem(water_reinjected);
			}
			
			result["allocated_kwh"] <- actual_alloc_kwh;
			result["shortfall_kwh"] <- requested_kwh - actual_alloc_kwh;
						
			tick_resources_used["L water"] <- tick_resources_used["L water"] + water_consumed;
			tick_resources_used["m² land"] <- land_occupied_m2;
			tick_production["kWh energy"] <- tick_production["kWh energy"] + result["allocated_kwh"];
			tick_emissions["gCO2e emissions"] <- tick_emissions["gCO2e emissions"] + emissions_g;
			remaining_capacity_kwh_this_tick <- max(0.0, remaining_capacity_kwh_this_tick - actual_alloc_kwh);
					
			return result;
		}
		
		
		/**
		 * Execute energy production for this source to meet a specified demand. 
		 */
		map<string, unknown> produce(string bloc_name, map<string, float> demand) {
			if("kWh energy" in demand.keys) {
				float req <- demand["kWh energy"];
				if (req <= 0) {
					return ["ok" :: true, "allocated_kwh"::0.0];
				}
				
				map<string,float> res <- allocate_resources(req);
				
				map<string, unknown> prod_info <- [
            		"ok"::res["shortfall_kwh"] <= 0.0,
            		"allocated_kwh"::res["allocated_kwh"]
            	];
				
				return prod_info;
			}
			return ["ok" :: true, "allocated_kwh"::0.0];
		}
	}
	
	species nuclear_producer parent:sub_energy_producer_base {
		init { source_name <- "nuclear"; }
	}
	
	species solar_producer parent:sub_energy_producer_base {
		init { source_name <- "solar"; }
	}
	
	species wind_producer parent:sub_energy_producer_base {
		init { source_name <- "wind"; }
	}
	
	species hydro_producer parent:sub_energy_producer_base {
		init { source_name <- "hydro"; }
	}
	
    
    
    
    
    /**
	 * Energy consumption agent - models population energy consumption
	 * Ecotopia population uses energy efficiently (solar heating, efficient appliances)
	 * This is a micro-species of energy bloc
	 */
	species energy_consumer parent:consumption_agent{
	
		map<string, float> consumed <- [];
		
		map<string, float> get_tick_consumption{
			return copy(consumed);
		}
		
		init{
			loop c over: production_outputs_E{
				consumed[c] <- 0;
			}
		}
		
		action reset_tick_counters{
			loop c over: consumed.keys{
				consumed[c] <- 0;
			}
		}
		
		/**
		 * Calculate monthly energy consumption per individual
		 * Consumption varies slightly
		 */
		action consume(human h){
			float base_kwh <- human_cfg["avg_kwh_per_person"];
			float individual_noise <- (enable_energy_stochasticity and individual_noise_std > 0.0) ? gauss(0.0, individual_noise_std) : 0.0;
			float individual_kwh <- base_kwh * current_demand_multiplier * (1.0 + individual_noise);
			individual_kwh <- max(human_cfg["min_kwh_conso"], min(individual_kwh, human_cfg["max_kwh_conso"]));
			
			// Add to total consumption
			consumed["kWh energy"] <- consumed["kWh energy"] + individual_kwh * human_cfg["humans_per_agent"];
		}
	}
}





/**
 * Energy bloc experiments and displays
 * Visualizes aggregated national energy production and consumption
 * Shows breakdown by source (nuclear, solar, wind, hydro)
 */
experiment run_energy type: gui {		
	parameter "Initial total capacity (kWh per tick)" category:"Initialization" var:initial_total_capacity_kwh;
	parameter "Nuclear mix" category:"Mix ratio" var:nuclear_mix min:0.0 max:1.0;
	parameter "Solar mix" category:"Mix ratio" var:solar_mix min:0.0 max:1.0;
	parameter "Wind mix" category:"Mix ratio" var:wind_mix min:0.0 max:1.0;
	parameter "Hydro mix" category:"Mix ratio" var:hydro_mix min:0.0 max:1.0;
	
	parameter "Build buffer threshold" category:"Construction" var:shortage_buffer_threshold min:0.0 max:0.50;
	parameter "Max builds per tick per source" category:"Construction" var:max_builds_per_tick_per_source min:0 max:1000;
	parameter "Fast build horizon (months)" category:"Construction" var:fast_build_horizon_months min:1 max:24;
	parameter "Long build horizon (months)" category:"Construction" var:long_build_horizon_months min:12 max:240;
	parameter "Fast build share" category:"Construction" var:fast_build_share min:0.0 max:1.0;
	
	parameter "Enable stochasticity" category:"Stochasticity" var:enable_energy_stochasticity;
	parameter "Network losses rate" category:"Stochasticity" var:network_losses_rate min:0.0 max:0.20;
	parameter "Demand seasonality amp" category:"Stochasticity" var:demand_seasonality_amp min:0.0 max:0.30;
	parameter "Demand noise std" category:"Stochasticity" var:demand_noise_std min:0.0 max:0.20;
	parameter "Individual noise std" category:"Stochasticity" var:individual_noise_std min:0.0 max:0.20;
	parameter "Outage prob / month" category:"Stochasticity" var:outage_prob_monthly min:0.0 max:0.10;
	parameter "Drought prob / month" category:"Stochasticity" var:drought_prob_monthly min:0.0 max:0.05;
	parameter "Drought duration (months)" category:"Stochasticity" var:drought_duration_months min:1 max:24;
	parameter "Hydro capacity during drought" category:"Stochasticity" var:drought_hydro_capacity_mult min:0.10 max:1.00;
		
		
	/* ====================================================================================================================================
	 * LOG SCALE
	 ==================================================================================================================================== */	
	
	output {
		display Energy_information_log_scale type:2d {
			
			/* =-=-=-=-=-=
			 * ROW 1
			 =-=-=-=-=-=-= */

			chart "Total production (kWh)" type: series size: {0.20, 0.20} position: {0, 0} y_log_scale: true {
		    	data "Total production (kWh)" value: tick_production_E["kWh energy"];
			}
			
			chart "Emissions (gCO2e)" type: series size: {0.20, 0.20} position: {0.20, 0.0} y_log_scale: true {
		    	data "Emissions (gCO2e)" value: tick_emissions_E["gCO2e emissions"];
			}
			
			chart "Total land usage (m²)" type: series size: {0.20, 0.20} position: {0.40, 0} y_log_scale: true {
		    	data "Total land usage (m²)" value: tick_resources_used_E["m² land"];
			}
			
			chart "Total water withdrawn (L)" type: series size: {0.20, 0.20} position: {0.60, 0} y_log_scale: true {
		    	data "Total water withdrawn (L)" value: tick_resources_used_E["L water"];
			}
			
			chart "Total cotton usage (kg)" type: series size: {0.20, 0.20} position: {0.80, 0} y_log_scale: true {
				data "Total cotton (kg)" value: tick_resources_used_E["kg_cotton"];
			}
			
			/* =-=-=-=-=-=
			 * ROW 2
			 =-=-=-=-=-=-= */
			
			chart "Production by source (kWh)" type: series size: {0.20, 0.20} position: {0, 0.20} y_log_scale: true {
				data "Nuclear" value: tick_sub_production_E["nuclear"]["kWh energy"];
				data "Solar" value: tick_sub_production_E["solar"]["kWh energy"];
				data "Wind" value: tick_sub_production_E["wind"]["kWh energy"];
				data "Hydro" value: tick_sub_production_E["hydro"]["kWh energy"];
			}
			
			chart "Emissions by source (gCO2e)" type: series size: {0.20, 0.20} position: {0.20, 0.20} y_log_scale: true {
				data "Nuclear" value: tick_sub_emissions_E["nuclear"]["gCO2e emissions"];
				data "Solar" value: tick_sub_emissions_E["solar"]["gCO2e emissions"];
				data "Wind" value: tick_sub_emissions_E["wind"]["gCO2e emissions"];
				data "Hydro" value: tick_sub_emissions_E["hydro"]["gCO2e emissions"];
			}
			
			chart "Land usage by source (m²)" type: series size: {0.20, 0.20} position: {0.40, 0.20} y_log_scale: true {
				data "Nuclear" value: tick_sub_resources_used_E["nuclear"]["m² land"];
				data "Solar" value: tick_sub_resources_used_E["solar"]["m² land"];
				data "Wind" value: tick_sub_resources_used_E["wind"]["m² land"];
				data "Hydro" value: tick_sub_resources_used_E["hydro"]["m² land"];
			}
			
			chart "Water withdrawn by source (L)" type: series size: {0.20, 0.20} position: {0.60, 0.20} y_log_scale: true {
				data "Nuclear" value: tick_sub_resources_used_E["nuclear"]["L water"];
				data "Solar" value: tick_sub_resources_used_E["solar"]["L water"];
				data "Wind" value: tick_sub_resources_used_E["wind"]["L water"];
				data "Hydro" value: tick_sub_resources_used_E["hydro"]["L water"];
			}
			
			chart "Cotton usage by source (kg)" type: series size: {0.20, 0.20} position: {0.80, 0.20} y_log_scale: true {
				data "Nuclear" value: tick_sub_resources_used_E["nuclear"]["kg_cotton"];
				data "Solar" value: tick_sub_resources_used_E["solar"]["kg_cotton"];
				data "Wind" value: tick_sub_resources_used_E["wind"]["kg_cotton"];
				data "Hydro" value: tick_sub_resources_used_E["hydro"]["kg_cotton"];
			}
			
			/* =-=-=-=-=-=
			 * ROW 3
			 =-=-=-=-=-=-= */
			
			chart "Number of nuclear reactors" type: series size: {0.20, 0.20} position: {0, 0.40} {
				data "Total" value: tick_sub_nb_installations["nuclear"];
				data "Available" value: tick_sub_nb_operational_sites["nuclear"];
				data "Unavailable" value: tick_sub_nb_unavailable_sites["nuclear"];
			}
			
			chart "Number of solar park" type: series size: {0.20, 0.20} position: {0.20, 0.40} {
				data "Total" value: tick_sub_nb_installations["solar"];
				data "Available" value: tick_sub_nb_operational_sites["solar"];
				data "Unavailable" value: tick_sub_nb_unavailable_sites["solar"];
			}
			
			chart "Number of wind farm" type: series size: {0.20, 0.20} position: {0.40, 0.40} {
				data "Total" value: tick_sub_nb_installations["wind"];
				data "Available" value: tick_sub_nb_operational_sites["wind"];
				data "Unavailable" value: tick_sub_nb_unavailable_sites["wind"];
			}
			
			chart "Number of hydropower plant" type: series size: {0.20, 0.20} position: {0.60, 0.40} {
				data "Total" value: tick_sub_nb_installations["hydro"];
				data "Available" value: tick_sub_nb_operational_sites["hydro"];
				data "Unavailable" value: tick_sub_nb_unavailable_sites["hydro"];
			}
			
			chart "Energy mix (share)" type: series size: {0.20, 0.20} position: {0.80, 0.40} {
				data "Nuclear" value: (tick_production_E["kWh energy"] > 0) ? (tick_sub_production_E["nuclear"]["kWh energy"] / tick_production_E["kWh energy"]) : 0.0;
				data "Solar" value: (tick_production_E["kWh energy"] > 0) ? (tick_sub_production_E["solar"]["kWh energy"] / tick_production_E["kWh energy"]) : 0.0;
				data "Wind" value: (tick_production_E["kWh energy"] > 0) ? (tick_sub_production_E["wind"]["kWh energy"] / tick_production_E["kWh energy"]) : 0.0;
				data "Hydro" value: (tick_production_E["kWh energy"] > 0) ? (tick_sub_production_E["hydro"]["kWh energy"] / tick_production_E["kWh energy"]) : 0.0;
			}
			
			/* =-=-=-=-=-=
			 * ROW 4
			 =-=-=-=-=-=-= */
			
			chart "Population direct consumption (kWh)" type: series size: {0.20, 0.20} position: {0, 0.60} y_log_scale: true {
			    data "Population direct consumption (kWh)" value: tick_pop_consumption_E["kWh energy"];
			}
			
			chart "Demand multiplier" type: series size: {0.20, 0.20} position: {0.20, 0.60} {
			    data "Demand multiplier" value: current_demand_multiplier;
			}
			
			chart "Network losses (kWh)" type: series size: {0.20, 0.20} position: {0.40, 0.60} y_log_scale: true {
			    data "Losses (kWh)" value: tick_losses_E["kWh energy"];
			}
			
			chart "Hydro availability" type: series size: {0.20, 0.20} position: {0.60, 0.60} {
			    data "Availability" value: availability_factor_by_source["hydro"];
			}
			
			chart "Remaining capacity per tick (kWh)" type: series size: {0.20, 0.20} position: {0.80, 0.60} y_log_scale: true {
				data "Remaining capacity" value: tick_total_remaining_capacity_kwh;
			}
			
			/* =-=-=-=-=-=
			 * ROW 5
			 =-=-=-=-=-=-= */
				
			chart "Capacity: installed vs available (kWh)" type: series size: {0.20, 0.20} position: {0, 0.80} {
				data "Installed capacity" value: tick_total_installed_capacity_kwh;
				data "Available capacity" value: tick_total_available_capacity_kwh;
			}
			
			chart "Live - Energy mix (share)" type: histogram size: {0.20,0.20} position: {0.20, 0.80} {
			    data "Nuclear" value: (tick_production_E["kWh energy"] > 0) ? (tick_sub_production_E["nuclear"]["kWh energy"] / tick_production_E["kWh energy"]) : 0.0 color:#red;
			    data "Solar" value: (tick_production_E["kWh energy"] > 0) ? (tick_sub_production_E["solar"]["kWh energy"] / tick_production_E["kWh energy"]) : 0.0 color:#orange;
			    data "Wind" value: (tick_production_E["kWh energy"] > 0) ? (tick_sub_production_E["wind"]["kWh energy"] / tick_production_E["kWh energy"]) : 0.0 color:#green;
			    data "Hydro" value: (tick_production_E["kWh energy"] > 0) ? (tick_sub_production_E["hydro"]["kWh energy"] / tick_production_E["kWh energy"]) : 0.0 color:#blue;
			}
			
			chart "Live - Land usage mix (share)" type: histogram size: {0.20,0.20} position: {0.40, 0.80} {
			    data "Nuclear" value: (tick_resources_used_E["m² land"] > 0) ? (tick_sub_resources_used_E["nuclear"]["m² land"] / tick_resources_used_E["m² land"]) : 0.0 color:#red;
			    data "Solar" value: (tick_resources_used_E["m² land"] > 0) ? (tick_sub_resources_used_E["solar"]["m² land"] / tick_resources_used_E["m² land"]) : 0.0 color:#orange;
			    data "Wind" value: (tick_resources_used_E["m² land"] > 0) ? (tick_sub_resources_used_E["wind"]["m² land"] / tick_resources_used_E["m² land"]) : 0.0 color:#green;
				data "Hydro" value: (tick_resources_used_E["m² land"] > 0) ? (tick_sub_resources_used_E["hydro"]["m² land"] / tick_resources_used_E["m² land"]) : 0.0 color:#blue;
			}

			chart "Live - Water withdrawn mix (share)" type: histogram size: {0.20,0.20} position: {0.60, 0.80} {
			    data "Nuclear" value: (tick_resources_used_E["L water"] > 0) ? (tick_sub_resources_used_E["nuclear"]["L water"] / tick_resources_used_E["L water"]) : 0.0 color:#red;
			    data "Solar" value: (tick_resources_used_E["L water"] > 0) ? (tick_sub_resources_used_E["solar"]["L water"] / tick_resources_used_E["L water"]) : 0.0 color:#orange;
			    data "Wind" value: (tick_resources_used_E["L water"] > 0) ? (tick_sub_resources_used_E["wind"]["L water"] / tick_resources_used_E["L water"]) : 0.0 color:#green;
			    data "Hydro" value: (tick_resources_used_E["L water"] > 0) ? (tick_sub_resources_used_E["hydro"]["L water"] / tick_resources_used_E["L water"]) : 0.0 color:#blue;
			}

			chart "Live - Cotton usage mix (share)" type: histogram size: {0.20,0.20} position: {0.80, 0.80} {
			    data "Nuclear" value: (tick_resources_used_E["kg_cotton"] > 0) ? (tick_sub_resources_used_E["nuclear"]["kg_cotton"] / tick_resources_used_E["kg_cotton"]) : 0.0 color:#red;
			    data "Solar" value: (tick_resources_used_E["kg_cotton"] > 0) ? (tick_sub_resources_used_E["solar"]["kg_cotton"] / tick_resources_used_E["kg_cotton"]) : 0.0 color:#orange;
			    data "Wind" value: (tick_resources_used_E["kg_cotton"] > 0) ? (tick_sub_resources_used_E["wind"]["kg_cotton"] / tick_resources_used_E["kg_cotton"]) : 0.0 color:#green;
			    data "Hydro" value: (tick_resources_used_E["kg_cotton"] > 0) ? (tick_sub_resources_used_E["hydro"]["kg_cotton"] / tick_resources_used_E["kg_cotton"]) : 0.0 color:#blue;
			}
	    }
	    
	    
	    
	    
	    /* ====================================================================================================================================
		 * NORMAL SCALE
		 ==================================================================================================================================== */	
	    
	    
	    display Energy_information_normal_scale type:2d {
			
			/* =-=-=-=-=-=
			 * ROW 1
			 =-=-=-=-=-=-= */

			chart "Total production (kWh)" type: series size: {0.20, 0.20} position: {0, 0} {
		    	data "Total production (kWh)" value: tick_production_E["kWh energy"];
			}
			
			chart "Emissions (gCO2e)" type: series size: {0.20, 0.20} position: {0.20, 0.0} {
		    	data "Emissions (gCO2e)" value: tick_emissions_E["gCO2e emissions"];
			}
			
			chart "Total land usage (m²)" type: series size: {0.20, 0.20} position: {0.40, 0} {
		    	data "Total land usage (m²)" value: tick_resources_used_E["m² land"];
			}
			
			chart "Total water withdrawn (L)" type: series size: {0.20, 0.20} position: {0.60, 0} {
		    	data "Total water withdrawn (L)" value: tick_resources_used_E["L water"];
			}
			
			chart "Total cotton usage (kg)" type: series size: {0.20, 0.20} position: {0.80, 0} {
				data "Total cotton (kg)" value: tick_resources_used_E["kg_cotton"];
			}
			
			/* =-=-=-=-=-=
			 * ROW 2
			 =-=-=-=-=-=-= */
			
			chart "Production by source (kWh)" type: series size: {0.20, 0.20} position: {0, 0.20} {
				data "Nuclear" value: tick_sub_production_E["nuclear"]["kWh energy"];
				data "Solar" value: tick_sub_production_E["solar"]["kWh energy"];
				data "Wind" value: tick_sub_production_E["wind"]["kWh energy"];
				data "Hydro" value: tick_sub_production_E["hydro"]["kWh energy"];
			}
			
			chart "Emissions by source (gCO2e)" type: series size: {0.20, 0.20} position: {0.20, 0.20} {
				data "Nuclear" value: tick_sub_emissions_E["nuclear"]["gCO2e emissions"];
				data "Solar" value: tick_sub_emissions_E["solar"]["gCO2e emissions"];
				data "Wind" value: tick_sub_emissions_E["wind"]["gCO2e emissions"];
				data "Hydro" value: tick_sub_emissions_E["hydro"]["gCO2e emissions"];
			}
			
			chart "Land usage by source (m²)" type: series size: {0.20, 0.20} position: {0.40, 0.20} {
				data "Nuclear" value: tick_sub_resources_used_E["nuclear"]["m² land"];
				data "Solar" value: tick_sub_resources_used_E["solar"]["m² land"];
				data "Wind" value: tick_sub_resources_used_E["wind"]["m² land"];
				data "Hydro" value: tick_sub_resources_used_E["hydro"]["m² land"];
			}
			
			chart "Water withdrawn by source (L)" type: series size: {0.20, 0.20} position: {0.60, 0.20} {
				data "Nuclear" value: tick_sub_resources_used_E["nuclear"]["L water"];
				data "Solar" value: tick_sub_resources_used_E["solar"]["L water"];
				data "Wind" value: tick_sub_resources_used_E["wind"]["L water"];
				data "Hydro" value: tick_sub_resources_used_E["hydro"]["L water"];
			}
			
			chart "Cotton usage by source (kg)" type: series size: {0.20, 0.20} position: {0.80, 0.20} {
				data "Nuclear" value: tick_sub_resources_used_E["nuclear"]["kg_cotton"];
				data "Solar" value: tick_sub_resources_used_E["solar"]["kg_cotton"];
				data "Wind" value: tick_sub_resources_used_E["wind"]["kg_cotton"];
				data "Hydro" value: tick_sub_resources_used_E["hydro"]["kg_cotton"];
			}
			
			/* =-=-=-=-=-=
			 * ROW 3
			 =-=-=-=-=-=-= */
			
			chart "Number of nuclear reactors" type: series size: {0.20, 0.20} position: {0, 0.40} {
				data "Total" value: tick_sub_nb_installations["nuclear"];
				data "Available" value: tick_sub_nb_operational_sites["nuclear"];
				data "Unavailable" value: tick_sub_nb_unavailable_sites["nuclear"];
			}
			
			chart "Number of solar park" type: series size: {0.20, 0.20} position: {0.20, 0.40} {
				data "Total" value: tick_sub_nb_installations["solar"];
				data "Available" value: tick_sub_nb_operational_sites["solar"];
				data "Unavailable" value: tick_sub_nb_unavailable_sites["solar"];
			}
			
			chart "Number of wind farm" type: series size: {0.20, 0.20} position: {0.40, 0.40} {
				data "Total" value: tick_sub_nb_installations["wind"];
				data "Available" value: tick_sub_nb_operational_sites["wind"];
				data "Unavailable" value: tick_sub_nb_unavailable_sites["wind"];
			}
			
			chart "Number of hydropower plant" type: series size: {0.20, 0.20} position: {0.60, 0.40} {
				data "Total" value: tick_sub_nb_installations["hydro"];
				data "Available" value: tick_sub_nb_operational_sites["hydro"];
				data "Unavailable" value: tick_sub_nb_unavailable_sites["hydro"];
			}
			
			chart "Energy mix (share)" type: series size: {0.20, 0.20} position: {0.80, 0.40} {
				data "Nuclear" value: (tick_production_E["kWh energy"] > 0) ? (tick_sub_production_E["nuclear"]["kWh energy"] / tick_production_E["kWh energy"]) : 0.0;
				data "Solar" value: (tick_production_E["kWh energy"] > 0) ? (tick_sub_production_E["solar"]["kWh energy"] / tick_production_E["kWh energy"]) : 0.0;
				data "Wind" value: (tick_production_E["kWh energy"] > 0) ? (tick_sub_production_E["wind"]["kWh energy"] / tick_production_E["kWh energy"]) : 0.0;
				data "Hydro" value: (tick_production_E["kWh energy"] > 0) ? (tick_sub_production_E["hydro"]["kWh energy"] / tick_production_E["kWh energy"]) : 0.0;
			}
			
			/* =-=-=-=-=-=
			 * ROW 4
			 =-=-=-=-=-=-= */
			
			chart "Population direct consumption (kWh)" type: series size: {0.20, 0.20} position: {0, 0.60} {
			    data "Population direct consumption (kWh)" value: tick_pop_consumption_E["kWh energy"];
			}
			
			chart "Demand multiplier" type: series size: {0.20, 0.20} position: {0.20, 0.60} {
			    data "Demand multiplier" value: current_demand_multiplier;
			}
			
			chart "Network losses (kWh)" type: series size: {0.20, 0.20} position: {0.40, 0.60} {
			    data "Losses (kWh)" value: tick_losses_E["kWh energy"];
			}
			
			chart "Hydro availability" type: series size: {0.20, 0.20} position: {0.60, 0.60} {
			    data "Availability" value: availability_factor_by_source["hydro"];
			}
			
			chart "Remaining capacity per tick (kWh)" type: series size: {0.20, 0.20} position: {0.80, 0.60} {
				data "Remaining capacity" value: tick_total_remaining_capacity_kwh;
			}
			
			/* =-=-=-=-=-=
			 * ROW 5
			 =-=-=-=-=-=-= */
				
			chart "Capacity: installed vs available (kWh)" type: series size: {0.20, 0.20} position: {0, 0.80} {
				data "Installed capacity" value: tick_total_installed_capacity_kwh;
				data "Available capacity" value: tick_total_available_capacity_kwh;
			}
			
			chart "Live - Energy mix (share)" type: histogram size: {0.20,0.20} position: {0.20, 0.80} {
			    data "Nuclear" value: (tick_production_E["kWh energy"] > 0) ? (tick_sub_production_E["nuclear"]["kWh energy"] / tick_production_E["kWh energy"]) : 0.0 color:#red;
			    data "Solar" value: (tick_production_E["kWh energy"] > 0) ? (tick_sub_production_E["solar"]["kWh energy"] / tick_production_E["kWh energy"]) : 0.0 color:#orange;
			    data "Wind" value: (tick_production_E["kWh energy"] > 0) ? (tick_sub_production_E["wind"]["kWh energy"] / tick_production_E["kWh energy"]) : 0.0 color:#green;
			    data "Hydro" value: (tick_production_E["kWh energy"] > 0) ? (tick_sub_production_E["hydro"]["kWh energy"] / tick_production_E["kWh energy"]) : 0.0 color:#blue;
			}
			
			chart "Live - Land usage mix (share)" type: histogram size: {0.20,0.20} position: {0.40, 0.80} {
			    data "Nuclear" value: (tick_resources_used_E["m² land"] > 0) ? (tick_sub_resources_used_E["nuclear"]["m² land"] / tick_resources_used_E["m² land"]) : 0.0 color:#red;
			    data "Solar" value: (tick_resources_used_E["m² land"] > 0) ? (tick_sub_resources_used_E["solar"]["m² land"] / tick_resources_used_E["m² land"]) : 0.0 color:#orange;
			    data "Wind" value: (tick_resources_used_E["m² land"] > 0) ? (tick_sub_resources_used_E["wind"]["m² land"] / tick_resources_used_E["m² land"]) : 0.0 color:#green;
				data "Hydro" value: (tick_resources_used_E["m² land"] > 0) ? (tick_sub_resources_used_E["hydro"]["m² land"] / tick_resources_used_E["m² land"]) : 0.0 color:#blue;
			}

			chart "Live - Water withdrawn mix (share)" type: histogram size: {0.20,0.20} position: {0.60, 0.80} {
			    data "Nuclear" value: (tick_resources_used_E["L water"] > 0) ? (tick_sub_resources_used_E["nuclear"]["L water"] / tick_resources_used_E["L water"]) : 0.0 color:#red;
			    data "Solar" value: (tick_resources_used_E["L water"] > 0) ? (tick_sub_resources_used_E["solar"]["L water"] / tick_resources_used_E["L water"]) : 0.0 color:#orange;
			    data "Wind" value: (tick_resources_used_E["L water"] > 0) ? (tick_sub_resources_used_E["wind"]["L water"] / tick_resources_used_E["L water"]) : 0.0 color:#green;
			    data "Hydro" value: (tick_resources_used_E["L water"] > 0) ? (tick_sub_resources_used_E["hydro"]["L water"] / tick_resources_used_E["L water"]) : 0.0 color:#blue;
			}

			chart "Live - Cotton usage mix (share)" type: histogram size: {0.20,0.20} position: {0.80, 0.80} {
			    data "Nuclear" value: (tick_resources_used_E["kg_cotton"] > 0) ? (tick_sub_resources_used_E["nuclear"]["kg_cotton"] / tick_resources_used_E["kg_cotton"]) : 0.0 color:#red;
			    data "Solar" value: (tick_resources_used_E["kg_cotton"] > 0) ? (tick_sub_resources_used_E["solar"]["kg_cotton"] / tick_resources_used_E["kg_cotton"]) : 0.0 color:#orange;
			    data "Wind" value: (tick_resources_used_E["kg_cotton"] > 0) ? (tick_sub_resources_used_E["wind"]["kg_cotton"] / tick_resources_used_E["kg_cotton"]) : 0.0 color:#green;
			    data "Hydro" value: (tick_resources_used_E["kg_cotton"] > 0) ? (tick_sub_resources_used_E["hydro"]["kg_cotton"] / tick_resources_used_E["kg_cotton"]) : 0.0 color:#blue;
			}
	    }
	}
}
