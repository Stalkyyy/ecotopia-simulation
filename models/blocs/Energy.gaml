/**
* Name: Energy bloc (MOSIMA)
* Authors: Maël Franceschetti, Cédric Herpson, Jean-Daniel Kant
* Mail: firstname.lastname@lip6.fr
*/

model Energy

import "../API/API.gaml"

/**
 * We define here the global variables and data of the bloc. Some are needed for the displays (charts, series...).
 */
global{

	/* Setup */
	list<string> production_inputs_E <- ["L water", "m² land"];
	list<string> production_outputs_E <- ["kWh energy"];
	list<string> production_emissions_E <- ["gCO2e emissions"];
	
	/* Production data */
	map<string, map<string, float>> production_output_inputs_E <- [
		"kWh energy"::["L water"::80.0, "m² land"::25.0]
	]; // Note : this is fake data (not the real amound of resources used and emitted).
	map<string, map<string, float>> production_output_emissions_E <- [
		"kWh energy"::["gCO2e emissions"::120.0]
	];
	
	/* Consumption data */
	int min_kWh_conso <- 1; // Note : this is fake data (not the real energy consumption)
	int max_kWh_conso <- 120; // Note : this is fake data (not the real energy consumption)
	
	/* Counters & Stats */
	map<string, float> tick_production_E <- [];
	map<string, float> tick_pop_consumption_E <- [];
	map<string, float> tick_resources_used_E <- [];
	map<string, float> tick_emissions_E <- [];
	
	init{ // a security added to avoid launching an experiment without the other blocs
		if (length(coordinator) = 0){
			error "Coordinator agent not found. Ensure you launched the experiment from the Main model";
			// If you see this error when trying to run an experiment, this means the coordinator agent does not exist.
			// Ensure you launched the experiment from the Main model (and not from the bloc model containing the experiment).
		}
	}
}

/**
 * We define here the agricultural bloc as a species.
 * We implement the methods of the API.
 * This bloc is very minimalistic : it only apply an average consumption for the population, and provide energy to other blocs.
 */
species energy parent:bloc{
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
	}
	
	action tick(list<human> pop){
		do collect_last_tick_data();
		do population_activity(pop);
	}
	
	production_agent get_producer{
		write "producer inside target bloc : "+producer;
		return producer;
	}

	list<string> get_output_resources_labels{
		return production_outputs_E;
	}
	
	list<string> get_input_resources_labels{
		return production_inputs_E;
	}

	
	action set_external_producer(string product, bloc bloc_agent){
		// do nothing
	}
	
	action collect_last_tick_data{
		if(cycle > 0){ // skip it the first tick
			tick_pop_consumption_E <- consumer.get_tick_consumption(); // collect consumption behaviors
    		tick_resources_used_E <- producer.get_tick_inputs_used(); // collect resources used
	    	tick_production_E <- producer.get_tick_outputs_produced(); // collect production
	    	tick_emissions_E <- producer.get_tick_emissions(); // collect emissions
    	
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
    			do consume(myself); // individuals consume agricultural goods
    		}
    	}
    	 
    	ask energy_consumer{ // produce the resuired quantities
    		ask energy_producer{
    			loop c over: myself.consumed.keys{
		    		do produce([c::myself.consumed[c]]);
		    	}
		    } 
    	}
    }

	/**
	 * We define here the production agent of the energy bloc as a micro-species (equivalent of nested class in Java).
	 * We implement the methods of the API.
	 * The production is minimalistic here : we apply an average resource consumption and emissions for the energy production.
	 */
	species energy_producer parent:production_agent{
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
	
		action reset_tick_counters{ // reset impact counters
			loop u over: production_inputs_E{
				tick_resources_used[u] <- 0.0; // reset resources usage
			}
			loop p over: production_outputs_E{
				tick_production[p] <- 0.0; // reset productions
			}
			loop e over: production_emissions_E{
				tick_emissions[e] <- 0.0;
			}
		}
		
		bool produce(map<string,float> demand){ // apply the input
			loop c over: demand.keys{
				loop u over: production_inputs_E{  // needs (resources consumed/emitted) for this demand
					tick_resources_used[u] <- tick_resources_used[u] + production_output_inputs_E[c][u] * demand[c];
				}
				loop e over: production_emissions_E{ // apply emissions
					float quantity_emitted <- production_output_emissions_E[c][e] * demand[c];
					tick_emissions[e] <- tick_emissions[e] + quantity_emitted;
				}
				tick_production[c] <- tick_production[c] + demand[c];
			}
			return true; // always return 'ok' signal
		}
		
		action set_supplier(string product, bloc bloc_agent){
			// do nothing
		}
	}
	
	/**
	 * We define here the conumption agent of the energy bloc as a micro-species (equivalent of nested class in Java).
	 * We implement the methods of the API.
	 * The consumption is minimalistic here : we apply a random energy consumption for everyone.
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
		
		action reset_tick_counters{ // reset choices counters
    		loop c over: consumed.keys{
    			consumed[c] <- 0;
    		}
		}
		
		action consume(human h){
		    string choice <- one_of(production_outputs_E); // note : here, there is only one production, energy
			consumed[choice] <- consumed[choice]+rnd(min_kWh_conso, max_kWh_conso); // monthly consume a random amount of energy 
		}
	}
}

/**
 * We define here the experiment and the displays related to energy. 
 * We will then be able to run this experiment from the Main code of the simulation, with all the blocs connected.
 * 
 * Note : experiment car inherit another experiment, but we can't combine displays from multiple experiments at the same time. 
 * If needed, a new experiment combining all those displays should be added, for example in the Main code of the simulation.
 */
experiment run_energy type: gui {
	output {
		display Energy_information {
			chart "Population direct consumption" type: series  size: {0.5,0.5} position: {0, 0} {
			    loop c over: production_outputs_E{
			    	data c value: tick_pop_consumption_E[c]; // note : products consumed by other blocs NOT included here (only population direct consumption)
			    }
			}
			chart "Total production" type: series  size: {0.5,0.5} position: {0.5, 0} {
			    loop c over: production_outputs_E{
			    	data c value: tick_production_E[c];
			    }
			}
			chart "Resources usage" type: series size: {0.5,0.5} position: {0, 0.5} {
			    loop r over: production_inputs_E{
			    	data r value: tick_resources_used_E[r];
			    }
			}
			chart "Production emissions" type: series size: {0.5,0.5} position: {0.5, 0.5} {
			    loop e over: production_emissions_E{
			    	data e value: tick_emissions_E[e];
			    }
			}
	    }
	}
}