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
	list<string> production_inputs_E <- ["L water", "m² land"];
	list<string> production_outputs_E <- ["kWh energy"];
	list<string> production_emissions_E <- ["gCO2e emissions"];
	 
	// Parameters
	float nuclear_mix <- 0.40;
	float solar_mix <- 0.25;
	float wind_mix <- 0.15;
	float hydro_mix <- 0.20;
	 
	// Config and data
	map<string, map<string, float>> energy_cfg <- [];
	map<string, float> human_cfg <- [];
		
	// Aggregated tick counters
	map<string, float> tick_production_E <- [];
	map<string, float> tick_resources_used_E <- [];
	map<string, float> tick_emissions_E <- [];
	map<string, float> tick_pop_consumption_E <- [];
	 
	// Per source tick counters
	map<string, map<string, float>> tick_sub_production_E <- [];
	map<string, map<string, float>> tick_sub_resources_used_E <- [];
	map<string, map<string, float>> tick_sub_emissions_E <- [];
	map<string, int> tick_sub_nb_installations <- [];

	init{ 
		if (length(coordinator) = 0){
			error "Coordinator agent not found. Ensure you launched the experiment from the Main model";
		}
		
		// Energy config and data
		file config_csv <- csv_file("../data/data_energy.csv", ",", true);
		matrix config_matrix <- matrix(config_csv);
		list<string> headers <- config_csv.attributes;
		loop i from:0 to:config_matrix.rows-1 {
			string source_name <- string(config_matrix[0,i]);
			tick_sub_production_E[source_name] <- [];
			tick_sub_resources_used_E[source_name] <- [];
			tick_sub_emissions_E[source_name] <- [];
			
			energy_cfg[source_name] <- [];	
			loop j from:1 to:length(headers) - 1 {
				energy_cfg[source_name][headers[j]] <- float(config_matrix[j,i]);
			}
		}
		
		// Human config and data
		config_csv <- csv_file("../data/data_human_energy.csv", ",", true);
		config_matrix <- matrix(config_csv);
		headers <- config_csv.attributes;
		loop j from:0 to:length(headers)-1 {
			human_cfg[headers[j]] <- float(config_matrix[j,0]);
		}
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
	
	action tick(list<human> pop) {
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
		if (cycle > 0) {
			tick_pop_consumption_E <- consumer.get_tick_consumption(); 		// collect consumption behaviors
			
			ask producer { do snapshot_sub_tick_data; }
			tick_resources_used_E <- producer.get_tick_inputs_used(); 		// collect resources used
	    	tick_production_E <- producer.get_tick_outputs_produced(); 		// collect production
	    	tick_emissions_E <- producer.get_tick_emissions(); 				// collect emissions	    	
	    	
	    	ask energy_consumer{ // prepare next tick on consumer side
	    		do reset_tick_counters;
	    	}
	    	
	    	ask energy_producer{ // prepare next tick on producer side
	    		do reset_tick_counters;
	    	}
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
		    		do produce([c::myself.consumed[c]]);
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
		}
		
		
		/**
		 * Orchestrate national energy production across all sources according to energy mix ratios
		 */
		bool produce(map<string, float> demand) {
			float total_energy_demanded <- 0.0;
			if ("kWh energy" in demand.keys) {
				total_energy_demanded <- demand["kWh energy"];
			}

			map<string, float> mix_ratios <- [
				"nuclear"::nuclear_mix,
				"solar"::solar_mix,
				"wind"::wind_mix,
				"hydro"::hydro_mix
			];
			
			// Execute production per energy source
			bool ok <- true;
			loop sub_producer over:sub_producers {	
				string source_name <- sub_producer.get_source_name();		
				float source_energy_requested <- total_energy_demanded * mix_ratios[source_name];
				ask sub_producer {
					if (not produce(["kWh energy"::source_energy_requested])) {
						ok <- false;
					}
				}				
			}
									       
			return ok;
		}
		
		// To update the finals values to print in experiments.
        action snapshot_sub_tick_data {
        	do not_sub_reset_tick();
        	
            loop sub_producer over:sub_producers {
                string source_name <- sub_producer.get_source_name();
                map<string, float> sub_prod <- sub_producer.get_tick_outputs_produced();
                map<string, float> sub_inputs <- sub_producer.get_tick_inputs_used();
                map<string, float> sub_emis <- sub_producer.get_tick_emissions();
                
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
		int nb_installations <- 0; 
		float remaining_capacity_kwh_this_tick <- 0.0;
		float land_occupied_m2 <- 0.0;
		map<string, float> tick_resources_used <- [];
		map<string, float> tick_production <- [];
		map<string, float> tick_emissions <- [];
		 
		string get_source_name {
			return source_name;
		}
		
		action update_tick_data {
			tick_sub_production_E[source_name] <- copy(tick_production);
			tick_sub_resources_used_E[source_name] <- copy(tick_resources_used);
			tick_sub_emissions_E[source_name] <- copy(tick_emissions);
		}
		 
		float get_total_capacity_kwh {
			return nb_installations * energy_cfg[source_name]["capacity_per_installation_kwh"];
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
			return nb_installations;
		}
		
		action set_supplier(string product, bloc bloc_agent){
			write name+": external producer "+bloc_agent+" set for"+product;
			external_producers[product] <- bloc_agent;
		}
		 
		action reset_tick_counters {
			loop u over: production_inputs_E{
				tick_resources_used[u] <- 0.0;
			}
			loop p over: production_outputs_E{
				tick_production[p] <- 0.0;
			}
			loop e over: production_emissions_E{
				tick_emissions[e] <- 0.0;
			}
			
			remaining_capacity_kwh_this_tick <- get_total_capacity_kwh();
			tick_resources_used["m² land"] <- land_occupied_m2;
		}
		 
		/**
		 * Dynamically construct energy installations to meet unmet demand. 
		 */
		action try_build_installations(float deficit_kwh) {
			int installations_needed <- int(ceil(deficit_kwh / energy_cfg[source_name]["capacity_per_installation_kwh"]));
			loop i from:1 to:installations_needed {
				if ("m² land" in external_producers.keys) {
					bool ok <- external_producers["m² land"].producer.produce(["m² land"::energy_cfg[source_name]["land_per_installation_m2"]]);
					if (ok) {
						nb_installations <- nb_installations + 1;
						land_occupied_m2 <- land_occupied_m2 + energy_cfg[source_name]["land_per_installation_m2"];
						remaining_capacity_kwh_this_tick <- remaining_capacity_kwh_this_tick + energy_cfg[source_name]["capacity_per_installation_kwh"];
					} else {
						break;
					}
				}
			}
		}
		
		
		/**
		 * Allocate available production capacity and resources to fulfill an energy demand request.
		 * - If there is not enough capacity left this tick, we try to build an installation.
		 * - For now, to not fight with the API file, we request water in 10% increments from Ecosystem Bloc, in case it has not enough water to share with us.
		 */
		map<string, float> allocate_resources(float requested_kwh) {
			map<string, float> result <- ["allocated_kwh"::0.0, "shortfall_kwh"::0.0];
			
			if(requested_kwh > remaining_capacity_kwh_this_tick){
				do try_build_installations(requested_kwh - remaining_capacity_kwh_this_tick);
			}
			
			float actual_alloc_kwh <- min(requested_kwh, remaining_capacity_kwh_this_tick);
			
			float water_needed <- actual_alloc_kwh * energy_cfg[source_name]["water_per_kwh_l"];
			float water_to_ask <- water_needed;
			float water_asked_per_loop <- water_needed * 0.10; // Every 10%
			if (water_to_ask > 0 and "L water" in external_producers.keys){
				loop while: water_to_ask > 0 {
					bool water_ok <- external_producers["L water"].producer.produce(["L water"::water_asked_per_loop]);
					if (water_ok) {
						water_to_ask <- water_to_ask - water_asked_per_loop;
					} else {
						break;
					}
				}
				
				actual_alloc_kwh <- actual_alloc_kwh * ((water_needed - water_to_ask) / water_needed);
			}
			
			float emissions_g <- actual_alloc_kwh * energy_cfg[source_name]["emissions_per_kwh"];
			do send_ges_to_ecosystem(emissions_g);
			
			result["allocated_kwh"] <- actual_alloc_kwh;
			result["shortfall_kwh"] <- requested_kwh - actual_alloc_kwh;
						
			tick_resources_used["L water"] <- tick_resources_used["L water"] + (water_needed - water_to_ask);
			tick_resources_used["m² land"] <- land_occupied_m2;
			tick_production["kWh energy"] <- tick_production["kWh energy"] + result["allocated_kwh"];
			tick_emissions["gCO2e emissions"] <- tick_emissions["gCO2e emissions"] + emissions_g;
					
			return result;
		}
		
		
		/**
		 * Execute energy production for this source to meet a specified demand. 
		 */
		bool produce(map<string, float> demand) {
			if("kWh energy" in demand.keys) {
				float req <- demand["kWh energy"];
				if (req <= 0) {
					return true;
				}
				
				map<string,float> res <- allocate_resources(req);
				return res["shortfall_kwh"] <= 0.0;
			}
			return true;
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
			// float monthly_kwh <- gauss(human_cfg["avg_kwh_per_person"], human_cfg["std_kwh_per_person"]);
			// float individual_kwh <- max(human_cfg["min_kwh_conso"], min(human_cfg["monthly_kwh"], human_cfg["max_kwh_conso"]));
			float individual_kwh <- human_cfg["avg_kwh_per_person"];
			
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
	parameter "Nuclear mix" category:"Mix ratio" var:nuclear_mix min:0.0 max:1.0;
	parameter "Solar mix" category:"Mix ratio" var:solar_mix min:0.0 max:1.0;
	parameter "Wind mix" category:"Mix ratio" var:wind_mix min:0.0 max:1.0;
	parameter "Hydro mix" category:"Mix ratio" var:hydro_mix min:0.0 max:1.0;
		
	
	output {
		display Energy_information type:2d {
			chart "Total production (kWh)" type: series size: {0.25,0.25} position: {0, 0} {
		    	data "Total production (kWh)" value: tick_production_E["kWh energy"];
			}
			
			chart "Emissions (gCO2e)" type: series size: {0.25,0.25} position: {0.25, 0.0} {
		    	data "Emissions (gCO2e)" value: tick_emissions_E["gCO2e emissions"];
			}
			
			chart "Total land usage (m²)" type: series size: {0.25,0.25} position: {0.5, 0} {
		    	data "Total land usage (m²)" value: tick_resources_used_E["m² land"];
			}
			
			chart "Total water usage (L)" type: series size: {0.25,0.25} position: {0.75, 0} {
		    	data "Total water usage (L)" value: tick_resources_used_E["L water"];
			}
			
			chart "Production by source (kWh)" type: series size: {0.25,0.25} position: {0, 0.25} {
				data "Nuclear" value: tick_sub_production_E["nuclear"]["kWh energy"];
				data "Solar" value: tick_sub_production_E["solar"]["kWh energy"];
				data "Wind" value: tick_sub_production_E["wind"]["kWh energy"];
				data "Hydro" value: tick_sub_production_E["hydro"]["kWh energy"];
			}
			
			chart "Emissions by source (gCO2e)" type: series size: {0.25,0.25} position: {0.25, 0.25} {
				data "Nuclear" value: tick_sub_emissions_E["nuclear"]["gCO2e emissions"];
				data "Solar" value: tick_sub_emissions_E["solar"]["gCO2e emissions"];
				data "Wind" value: tick_sub_emissions_E["wind"]["gCO2e emissions"];
				data "Hydro" value: tick_sub_emissions_E["hydro"]["gCO2e emissions"];
			}
			
			chart "Land usage by source (m²)" type: series size: {0.25,0.25} position: {0.5, 0.25} {
				data "Nuclear" value: tick_sub_resources_used_E["nuclear"]["m² land"];
				data "Solar" value: tick_sub_resources_used_E["solar"]["m² land"];
				data "Wind" value: tick_sub_resources_used_E["wind"]["m² land"];
				data "Hydro" value: tick_sub_resources_used_E["hydro"]["m² land"];
			}
			
			chart "Water usage by source (L)" type: series size: {0.25,0.25} position: {0.75, 0.25} {
				data "Nuclear" value: tick_sub_resources_used_E["nuclear"]["L water"];
				data "Solar" value: tick_sub_resources_used_E["solar"]["L water"];
				data "Wind" value: tick_sub_resources_used_E["wind"]["L water"];
				data "Hydro" value: tick_sub_resources_used_E["hydro"]["L water"];
			}
			
			chart "Number of nuclear reactors" type: series size: {0.25, 0.25} position: {0, 0.5} {
				data "nb_installations" value: tick_sub_nb_installations["nuclear"];
			}
			
			chart "Number of solar park" type: series size: {0.25, 0.25} position: {0.25, 0.5} {
				data "nb_installations" value: tick_sub_nb_installations["solar"];
			}
			
			chart "Number of wind farm" type: series size: {0.25, 0.25} position: {0.50, 0.5} {
				data "nb_installations" value: tick_sub_nb_installations["wind"];
			}
			
			chart "Number of hydropower plant" type: series size: {0.25, 0.25} position: {0.75, 0.5} {
				data "nb_installations" value: tick_sub_nb_installations["hydro"];
			}
			
			chart "Population direct consumption (kWh)" type: series size: {0.25,0.25} position: {0, 0.75} {
			    data "Population direct consumption (kWh)" value: tick_pop_consumption_E["kWh energy"];
			}
	    }
	}
}
