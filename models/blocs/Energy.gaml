/**
* Name: Energy
* Based on the internal empty template. 
* Author: Enzo Pinho Fernandes
* Tags: 
*/

model Energy
import "../API/API.gaml"


/*
 * WARNING : Still must verify data !
 */
global {
	
	/* 
	 * Setup
	 */

	list<string> production_inputs_E <- ["L water", "m² land"];
	list<string> production_outputs_E <- ["kWh energy"];
	list<string> production_emissions_E <- ["gCO2e emissions"];
	
	
	/* 
	 * Energy Mix parameters
	 */
	float nuclear_mix <- 0.40;
	float solar_mix <- 0.25;
	float hydro_mix <- 0.15;
	float wind_mix <- 0.20;
	
	
	/* 
	 * Production Data
	 * Resources needed per MWh produced + emissions
	 */
	 
	// Nuclear : needs cooling water and surface land
	float nuclear_water_per_mwh <- 175.0; 		// liters per MWh
	float nuclear_land_per_mwh <- 0.01;			// m² per MWh
	float nuclear_emissions_per_mwh <- 7.0;		// gCO2e per MWh
	
	// Solar: needs land for panels
	float solar_water_per_mwh <- 5.0; 			// liters per MWh (panel cleaning)
	float solar_land_per_mwh <- 6.0; 			// m² per MWh (solar panels require significant area)
	float solar_emissions_per_mwh <- 43.0; 		// gCO2e per MWh (lifecycle emissions)

	// Wind: needs surface land
	float wind_water_per_mwh <- 0.0; 			// liters per MWh
	float wind_land_per_mwh <- 2.0; 				// m² per MWh
	float wind_emissions_per_mwh <- 16.0; 		// gCO2e per MWh
	
	// Hydro: needs water and surface land for reservoirs
	float hydro_water_per_mwh <- 0.0; 			// liters per MWh
	float hydro_land_per_mwh <- 3.0; 			// m² per MWh
	float hydro_emissions_per_mwh <- 6.0;		// gCO2e per MWh


	/*
	 * Consumption data
	 * Average residential consumption
	 */
	 
	float avg_monthly_kwh_per_person <- 185.0;	// kWh per month
	float std_montly_kwh_per_person <- 30.0;		// kWh per month
	float min_kwh_conso <- 150.0;				// kWh per month
	float max_kwh_conso <- 220.0;				// kWh per month
	float humans_per_agent <- 6700.0; 			// One agent "human" represents how much humans... 
	 
	
	/*
	 * Counters and stats
	 */
	 
	map<string, float> tick_production_E <- [];
	map<string, float> tick_pop_consumption_E <- [];
	map<string, float> tick_resources_used_E <- [];
	map<string, float> tick_emissions_E <- [];
	
	
	/*
	 * Per-source stats
	 */
	 
	map<string, float> tick_production_by_source_E <- [
		"nuclear"::0.0,
		"solar"::0.0,
		"wind"::0.0,
		"hydro"::0.0
	];
	
	
	// A security added to avoid launching an experiment without the other blocs
	init{ 
		if (length(coordinator) = 0){
			error "Coordinator agent not found. Ensure you launched the experiment from the Main model";
			// If you see this error when trying to run an experiment, this means the coordinator agent does not exist.
			// Ensure you launched the experiment from the Main model (and not from the bloc model containing the experiment).
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
		list<energy_producer> producers <- [];
		list<energy_consumer> consumers <- [];
		create energy_producer number:1 returns:producers; // instanciate the agricultural production handler
		create energy_consumer number:1 returns:consumers; // instanciate the agricultural consumption handler
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
		if(cycle > 0){ // skip it the first tick
			tick_pop_consumption_E <- consumer.get_tick_consumption(); 	// collect consumption behaviors
    		tick_resources_used_E <- producer.get_tick_inputs_used(); 			// collect resources used
	    	tick_production_E <- producer.get_tick_outputs_produced(); 		// collect production
	    	tick_emissions_E <- producer.get_tick_emissions(); 						// collect emissions
	    		    	
	    	// Collect per-source statistics
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

    
    
    
    
	species energy_producer parent:production_agent {
		map<string, bloc> external_producers; // Ecosysteme Bloc
		
		map<string, float> tick_resources_used <- [];
		map<string, float> tick_production <- [];
		map<string, float> tick_emissions <- [];
		
		// Sub-producer references
		nuclear_producer nuclear_gen <- nil;
		solar_producer solar_gen <- nil;
		wind_producer wind_gen <- nil;
		hydro_producer hydro_gen <- nil;
		
		map<string, float> get_tick_inputs_used{
			return tick_resources_used;
		}
		
		map<string, float> get_tick_outputs_produced{
			return tick_production;
		}
		
		map<string, float> get_tick_emissions{
			return tick_emissions;
		}
	
		action reset_tick_counters{ // reset impact counters
			loop u over: production_inputs_E{
				tick_resources_used[u] <- 0.0;
			}
			loop p over: production_outputs_E{
				tick_production[p] <- 0.0;
			}
			loop e over: production_emissions_E{
				tick_emissions[e] <- 0.0;
			}
			
			// Reset per-source stats
			tick_production_by_source_E["nuclear"] <- 0.0;
			tick_production_by_source_E["solar"] <- 0.0;
			tick_production_by_source_E["wind"] <- 0.0;
			tick_production_by_source_E["hydro"] <- 0.0;
		}
		
		
		
		/**
		 * Create the 4 national energy source managers
		 */
		action create_energy_sources{
			list<nuclear_producer> nuc <- [];
			list<solar_producer> sol <- [];
			list<wind_producer> wnd <- [];
			list<hydro_producer> hyd <- [];
			
			create nuclear_producer number:1 returns:nuc;
			create solar_producer number:1 returns:sol;
			create wind_producer number:1 returns:wnd;
			create hydro_producer number:1 returns:hyd;
			
			nuclear_gen <- first(nuc);
			solar_gen <- first(sol);
			wind_gen <- first(wnd);
			hydro_gen <- first(hyd);
		}
		
		
		
		
		
		bool produce(map<string, float> demand) {
			float total_energy_demanded <- 0.0;
			
			if ("kWh energy" in demand.keys) {
				total_energy_demanded <- demand["kWh energy"];
			}
			
			// Distribute production among sources according to mix
			float nuclear_prod <- total_energy_demanded * nuclear_mix;
			float solar_prod <- total_energy_demanded * solar_mix;
			float wind_prod <- total_energy_demanded * wind_mix;
			float hydro_prod <- total_energy_demanded * hydro_mix;
			
			// Execute production from each source (only if source exists and mix > 0)
			if(nuclear_gen != nil and nuclear_mix > 0){
				ask nuclear_gen {
					do produce(["kWh energy"::nuclear_prod]);
				}
			}
			if(solar_gen != nil and solar_mix > 0){
				ask solar_gen {
					do produce(["kWh energy"::solar_prod]);
				}
			}
			if(wind_gen != nil and wind_mix > 0){
				ask wind_gen {
					do produce(["kWh energy"::wind_prod]);
				}
			}
			if(hydro_gen != nil and hydro_mix > 0){
				ask hydro_gen {
					do produce(["kWh energy"::hydro_prod]);
				}
			}
			
			
			// Aggregate results
			if(nuclear_gen != nil){
				map<string, float> nuc_inputs <- nuclear_gen.get_tick_inputs_used();
				map<string, float> nuc_emissions <- nuclear_gen.get_tick_emissions();
				loop key over: nuc_inputs.keys{
					tick_resources_used[key] <- tick_resources_used[key] + nuc_inputs[key];
				}
				loop key over: nuc_emissions.keys{
					tick_emissions[key] <- tick_emissions[key] + nuc_emissions[key];
				}
				tick_production_by_source_E["nuclear"] <- tick_production_by_source_E["nuclear"]  + nuclear_gen.tick_production["kWh energy"];
			}
			
			if(solar_gen != nil){
				map<string, float> sol_inputs <- solar_gen.get_tick_inputs_used();
				map<string, float> sol_emissions <- solar_gen.get_tick_emissions();
				loop key over: sol_inputs.keys{
					tick_resources_used[key] <- tick_resources_used[key] + sol_inputs[key];
				}
				loop key over: sol_emissions.keys{
					tick_emissions[key] <- tick_emissions[key] + sol_emissions[key];
				}
				tick_production_by_source_E["solar"] <- tick_production_by_source_E["solar"] + solar_gen.tick_production["kWh energy"];
			}
			
			if(wind_gen != nil){
				map<string, float> wnd_inputs <- wind_gen.get_tick_inputs_used();
				map<string, float> wnd_emissions <- wind_gen.get_tick_emissions();
				loop key over: wnd_inputs.keys{
					tick_resources_used[key] <- tick_resources_used[key] + wnd_inputs[key];
				}
				loop key over: wnd_emissions.keys{
					tick_emissions[key] <- tick_emissions[key] + wnd_emissions[key];
				}
				tick_production_by_source_E["wind"] <- tick_production_by_source_E["wind"]  +  wind_gen.tick_production["kWh energy"];
			}
			
			if(hydro_gen != nil){
				map<string, float> hyd_inputs <- hydro_gen.get_tick_inputs_used();
				map<string, float> hyd_emissions <- hydro_gen.get_tick_emissions();
				loop key over: hyd_inputs.keys{
					tick_resources_used[key] <- tick_resources_used[key] + hyd_inputs[key];
				}
				loop key over: hyd_emissions.keys{
					tick_emissions[key] <- tick_emissions[key] + hyd_emissions[key];
				}
				tick_production_by_source_E["hydro"] <- tick_production_by_source_E["hydro"]  + hydro_gen.tick_production["kWh energy"];
			}
			
			// Record total production
			tick_production["kWh energy"] <- tick_production_by_source_E["nuclear"] 
									                                 + tick_production_by_source_E["solar"]
									                                 + tick_production_by_source_E["wind"]
									                                 + tick_production_by_source_E["hydro"];
			               
			write "DEMAND [Cycle " + cycle + "]: " + demand["kWh energy"] + " kWh";                  			
			return true;
		}
		
		action set_supplier(string product, bloc bloc_agent){
			if(nuclear_gen != nil){
				ask nuclear_gen {
					do set_supplier(product, bloc_agent);
				}
			}
			if(solar_gen != nil){
				ask solar_gen {
					do set_supplier(product, bloc_agent);
				}
			}
			if(wind_gen != nil){
				ask wind_gen {
					do set_supplier(product, bloc_agent);
				}
			}
			if(hydro_gen != nil){
				ask hydro_gen {
					do set_supplier(product, bloc_agent);
				}
			}
		}
	}
	
	
	
	species nuclear_producer parent:production_agent {
		map<string, bloc> external_producers; // Ecosysteme Bloc
		
		map<string, float> tick_resources_used <- [];
		map<string, float> tick_production <- [];
		map<string, float> tick_emissions <- [];
		
		map<string, float> get_tick_inputs_used		{ return tick_resources_used; }
		map<string, float> get_tick_outputs_produced	{ return tick_production; }
		map<string, float> get_tick_emissions		{ return tick_emissions; }
		
		action reset_tick_counters{
			tick_resources_used <- ["L water"::0.0, "m² land"::0.0];
			tick_production <- ["kWh energy"::0.0];
			tick_emissions <- ["gCO2e emissions"::0.0];
		}
		
		bool produce(map<string,float> demand){
			bool ok <- true;
			if("kWh energy" in demand.keys){
				float energy_to_produce <- demand["kWh energy"];
				
				// Resources needed
				float water_needed <- energy_to_produce * nuclear_water_per_mwh / 1000.0;
				float land_needed <- energy_to_produce * nuclear_land_per_mwh / 1000.0;
				
		        // Ask water to Ecosystem Bloc
		        if("L water" in external_producers.keys){
		            bool water_available <- external_producers["L water"].producer.produce(["L water"::water_needed]);
		            if not water_available{
		                ok <- false;
		            }
		        }
		        
		        // Ask land to Ecosystem Bloc
		        if("m² land" in external_producers.keys){
		            bool land_available <- external_producers["m² land"].producer.produce(["m² land"::land_needed]);
		            if not land_available{
		                ok <- false;
		            }
		        }
				
				// Need to find a proper way to have only what ecosystem gave us...
				tick_resources_used["L water"] <- water_needed;
				tick_resources_used["m² land"] <- land_needed;
				tick_production["kWh energy"] <- energy_to_produce;
				tick_emissions["gCO2e emissions"] <- energy_to_produce * nuclear_emissions_per_mwh / 1000.0;
			}
			return ok;
		}
		
		action set_supplier(string product, bloc bloc_agent){
			write name+": external producer "+bloc_agent+" set for"+product;
			external_producers[product] <- bloc_agent;
		}
	}
	
	
	
	species solar_producer parent:production_agent{
		map<string, bloc> external_producers; // Ecosysteme Bloc
		
		map<string, float> tick_resources_used <- [];
		map<string, float> tick_production <- [];
		map<string, float> tick_emissions <- [];
		
		map<string, float> get_tick_inputs_used{ return tick_resources_used; }
		map<string, float> get_tick_outputs_produced{ return tick_production; }
		map<string, float> get_tick_emissions{ return tick_emissions; }
		
		action reset_tick_counters{
			tick_resources_used <- ["L water"::0.0, "m² land"::0.0];
			tick_production <- ["kWh energy"::0.0];
			tick_emissions <- ["gCO2e emissions"::0.0];
		}
		
		bool produce(map<string,float> demand){
			bool ok <- true;
			if("kWh energy" in demand.keys){
				float energy_to_produce <- demand["kWh energy"];
				
				// Resources needed
				float water_needed <- energy_to_produce * solar_water_per_mwh / 1000.0;
				float land_needed <- energy_to_produce * solar_land_per_mwh / 1000.0;
				
		        // Ask water to Ecosystem Bloc
		        if("L water" in external_producers.keys){
		            bool water_available <- external_producers["L water"].producer.produce(["L water"::water_needed]);
		            if not water_available{
		                ok <- false;
		            }
		        }
		        
		        // Ask land to Ecosystem Bloc
		        if("m² land" in external_producers.keys){
		            bool land_available <- external_producers["m² land"].producer.produce(["m² land"::land_needed]);
		            if not land_available{
		                ok <- false;
		            }
		        }
		        
				// Need to find a proper way to have only what ecosystem gave us...
				tick_resources_used["L water"] <- water_needed;
				tick_resources_used["m² land"] <- land_needed;
				tick_production["kWh energy"] <- energy_to_produce;
				tick_emissions["gCO2e emissions"] <- energy_to_produce * solar_emissions_per_mwh / 1000.0;
			}
			return ok;
		}
		
		action set_supplier(string product, bloc bloc_agent){
			write name+": external producer "+bloc_agent+" set for"+product;
			external_producers[product] <- bloc_agent;
		}
	}
	
	
	
	species wind_producer parent:production_agent{
		map<string, bloc> external_producers; // Ecosysteme Bloc
		
		map<string, float> tick_resources_used <- [];
		map<string, float> tick_production <- [];
		map<string, float> tick_emissions <- [];
		
		map<string, float> get_tick_inputs_used{ return tick_resources_used; }
		map<string, float> get_tick_outputs_produced{ return tick_production; }
		map<string, float> get_tick_emissions{ return tick_emissions; }
		
		action reset_tick_counters{
			tick_resources_used <- ["L water"::0.0, "m² land"::0.0];
			tick_production <- ["kWh energy"::0.0];
			tick_emissions <- ["gCO2e emissions"::0.0];
		}
		
		bool produce(map<string,float> demand){
			bool ok <- true;
			if("kWh energy" in demand.keys){
				float energy_to_produce <- demand["kWh energy"];
				
				// Resources needed
				float water_needed <- energy_to_produce * wind_water_per_mwh / 1000.0;
				float land_needed <- energy_to_produce * wind_land_per_mwh / 1000.0;
				
		        // Ask water to Ecosystem Bloc
		        if("L water" in external_producers.keys){
		            bool water_available <- external_producers["L water"].producer.produce(["L water"::water_needed]);
		            if not water_available{
		                ok <- false;
		            }
		        }
		        
		        // Ask land to Ecosystem Bloc
		        if("m² land" in external_producers.keys){
		            bool land_available <- external_producers["m² land"].producer.produce(["m² land"::land_needed]);
		            if not land_available{
		                ok <- false;
		            }
		        }
		        
				// Need to find a proper way to have only what ecosystem gave us...
				tick_resources_used["L water"] <- water_needed;
				tick_resources_used["m² land"] <- land_needed;
				tick_production["kWh energy"] <- energy_to_produce;
				tick_emissions["gCO2e emissions"] <- energy_to_produce * wind_emissions_per_mwh / 1000.0;
			}
			return ok;
		}
		
		action set_supplier(string product, bloc bloc_agent){
			write name+": external producer "+bloc_agent+" set for"+product;
			external_producers[product] <- bloc_agent;
		}
	}
	
	
	
	species hydro_producer parent:production_agent{
		map<string, bloc> external_producers; // Ecosysteme Bloc

		map<string, float> tick_resources_used <- [];
		map<string, float> tick_production <- [];
		map<string, float> tick_emissions <- [];
		
		map<string, float> get_tick_inputs_used{ return tick_resources_used; }
		map<string, float> get_tick_outputs_produced{ return tick_production; }
		map<string, float> get_tick_emissions{ return tick_emissions; }
		
		action reset_tick_counters{
			tick_resources_used <- ["L water"::0.0, "m² land"::0.0];
			tick_production <- ["kWh energy"::0.0];
			tick_emissions <- ["gCO2e emissions"::0.0];
		}
		
		bool produce(map<string,float> demand){
			bool ok <- true;
			if("kWh energy" in demand.keys){
				float energy_to_produce <- demand["kWh energy"];
				
				// Resources needed
				float water_needed <- energy_to_produce * hydro_water_per_mwh / 1000.0;
				float land_needed <- energy_to_produce * hydro_land_per_mwh / 1000.0;
				
		        // Ask water to Ecosystem Bloc
		        if("L water" in external_producers.keys){
		            bool water_available <- external_producers["L water"].producer.produce(["L water"::water_needed]);
		            if not water_available{
		                ok <- false;
		            }
		        }
		        
		        // Ask land to Ecosystem Bloc
		        if("m² land" in external_producers.keys){
		            bool land_available <- external_producers["m² land"].producer.produce(["m² land"::land_needed]);
		            if not land_available{
		                ok <- false;
		            }
		        }
		        
				// Need to find a proper way to have only what ecosystem gave us...
				tick_resources_used["L water"] <- water_needed;
				tick_resources_used["m² land"] <- land_needed;
				tick_production["kWh energy"] <- energy_to_produce;
				tick_emissions["gCO2e emissions"] <- energy_to_produce * hydro_emissions_per_mwh / 1000.0;
			}
			return ok;
		}
		
		action set_supplier(string product, bloc bloc_agent){
			write name+": external producer "+bloc_agent+" set for"+product;
			external_producers[product] <- bloc_agent;
		}
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
			float monthly_kwh <- gauss(avg_monthly_kwh_per_person, std_montly_kwh_per_person);
			// Base consumption per individual (Ecotopia efficient lifestyle)
			float individual_kwh <- max(min_kwh_conso, min(monthly_kwh, max_kwh_conso));
			
			// Add to total consumption
			consumed["kWh energy"] <- consumed["kWh energy"] + individual_kwh * humans_per_agent;
		}
	}
}





/**
 * Energy bloc experiments and displays
 * Visualizes aggregated national energy production and consumption
 * Shows breakdown by source (nuclear, solar, wind, hydro)
 */
experiment run_energy type: gui {
	parameter "Nuclear mix" var:nuclear_mix min:0.0 max:1.0;
	parameter "Solar mix" var:solar_mix min:0.0 max:1.0;
	parameter "Wind mix" var:wind_mix min:0.0 max:1.0;
	parameter "Hydro mix" var:hydro_mix min:0.0 max:1.0;
	
	
	output {
		display Energy_information {
			// Population energy consumption
			chart "Population direct consumption" type: series size: {0.5,0.5} position: {0, 0} {
			    loop c over: production_outputs_E{
			    	data c value: tick_pop_consumption_E[c];
			    }
			}
			
			// Total production from all sources
			chart "Total production (aggregated)" type: series size: {0.5,0.5} position: {0.5, 0} {
			    loop c over: production_outputs_E{
			    	data c value: tick_production_E[c];
			    }
			}
			
			// Production breakdown by source
			chart "Production by source (kWh)" type: series size: {0.5,0.5} position: {0, 0.5} {
				data "Nuclear" value: tick_production_by_source_E["nuclear"];
				data "Solar" value: tick_production_by_source_E["solar"];
				data "Wind" value: tick_production_by_source_E["wind"];
				data "Hydro" value: tick_production_by_source_E["hydro"];
				data "Total" value: tick_production_E["kWh energy"];
			}
			
			// Resources usage
			chart "Resources usage" type: series size: {0.5,0.5} position: {0.5, 0.5} {
			    loop r over: production_inputs_E{
			    	data r value: tick_resources_used_E[r];
			    }
			}
			
			// Production emissions
			chart "Production emissions (gCO2e)" type: series size: {1.0,0.5} position: {0, 1} {
			    loop e over: production_emissions_E{
			    	data e value: tick_emissions_E[e];
			    }
			}
	    }
	}
}
