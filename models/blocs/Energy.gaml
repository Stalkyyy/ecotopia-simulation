/**
* Name: Energy bloc (MOSIMA)
* Authors: Maël Franceschetti, Cédric Herpson, Jean-Daniel Kant
* Mail: firstname.lastname@lip6.fr
*/

model Energy

import "../API/API.gaml"

/**
 * We define here the global variables of the bloc. Some are needed for the displays (charts, series...).
 * We define the input data used by the bloc.
 */
global{

	/* Setup */
	list resources_E <- ["L water", "m² land", "gCO2e emissions"];
	list behaviors_E <- ["kWh energy"];
	int min_kWh_conso <- 1; // Note : this is fake data (not the real energy consumption)
	int max_kWh_conso <- 120; // Note : this is fake data (not the real energy consumption)
	
	/* Counters & Stats */
	map<string, int> tick_behaviors_E <- [];
	map<string,int> tick_impacts_E <- [];
	
	/* Input data */
	map behavior_input_output_E <- [
		"kWh energy"::["L water"::80.0, "m² land"::25.0, "gCO2e emissions"::120.0]
	]; // Note : this is fake data (not the real amound of resources used and emitted).
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
	
	production_agent get_producer{
		write "producer inside target bloc : "+producer;
		return producer;
	}

	list<string> get_possible_behaviors{
		return behaviors_E;
	}
	
	list<string> get_possible_resources_used{
		return resources_E;
	}
	
	map<string, float> get_tick_resources_used{
		map<string, float> conso <- [];
		conso <- producer.get_tick_consumptions();
		return conso;
	}
	
	map<string, float> get_tick_behaviors{
		map<string, float> behaviors <- [];
		behaviors <- consumer.get_tick_behaviors();
		return behaviors;
	}
	
	action set_external_producer(string product, bloc bloc_agent){
		// do nothing
	}

	/**
	 * We define here the production agent of the energy bloc as a micro-species (equivalent of nested class in Java).
	 * We implement the methods of the API.
	 * The production is minimalistic here : we apply an average resource consumption and emissions for the energy production.
	 */
	species energy_producer parent:production_agent{
		map<string, float> tick_consumption <- [];
		
		map<string, float> get_tick_consumptions{
			return tick_consumption;
		}
	
		action new_tick{ // reset impact counters
			loop u over: resources_E{
				tick_consumption[u] <- 0.0; // reset resources usage
			}
		}
		
		bool produce(map<string,float> demand){ // apply the inpu
			loop c over: demand.keys{
				loop u over: resources_E{  // quantify the resources consumed/emitted by this demand
					tick_consumption[u] <- tick_consumption[u] + behavior_input_output_E[c][u] * demand[c];
				}
			}
			return true; // always return 'ok' signal
		}
		
		action set_external_producer(string product, bloc bloc_agent){
			// do nothing
		}
	}
	
	/**
	 * We define here the conumption agent of the energy bloc as a micro-species (equivalent of nested class in Java).
	 * We implement the methods of the API.
	 * The consumption is minimalistic here : we apply a random energy consumption (same behavior for everyone).
	 */
	species energy_consumer parent:consumption_agent{
	
		map<string, int> consumed <- [];
		
		map<string, float> get_tick_behaviors{
			return copy(consumed);
		}
		
		init{
			loop c over: behaviors_E{
				consumed[c] <- 0;
			}
		}
		
		action new_tick{ // reset choices counters
    		loop c over: consumed.keys{
    			consumed[c] <- 0;
    		}
		}
		
		action consume(human h){
		    string choice <- one_of(behaviors_E);
			consumed[choice] <- consumed[choice]+rnd(min_kWh_conso, max_kWh_conso); // monthly consume a random amount of energy 
		}
	}
	
	action setup{
		list<energy_producer> producers <- [];
		list<energy_consumer> consumers <- [];
		create energy_producer number:1 returns:producers; // instanciate the agricultural production handler
		create energy_consumer number:1 returns:consumers; // instanciate the agricultural consumption handler
		producer <- first(producers);
		consumer <- first(consumers);
	}
	
	action new_tick{
		if(cycle > 0){ // skip it the first tick
	    	ask energy_consumer{ // prepare next tick on consumer side
	    		do new_tick;
	    	}
	    	
	    	ask energy_producer{ // prepare next tick on producer side
	    		do new_tick;
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
    
    action end_tick{
    	tick_behaviors_E <- get_tick_behaviors(); // collect consumption behaviors
    	tick_impacts_E <- get_tick_resources_used(); // collect resources used
   	}
    
}

/**
 * We define here the experiment and the displays related to energy. 
 * We will then be able to run this experiment from the Main code of the simulation, with all the blocs connected.
 * 
 * Note : experiment car inherit another experiment, bu we can't combine displays from multiple experiments at the same time. 
 * If needed, a new experiment combining all those displays should be added, for example in the Main code of the simulation.
 */
experiment run_energy type: gui {
	output {
		display Energy_information {
			chart "Population consumption" type: series  size: {1,0.5} position: {0, 0} {
			    loop c over: behaviors_E{
			    	data c value: tick_behaviors_E[c]; // note : energy consumed by other blocs NOT included here (only population direct consumption)
			    }
			}
			chart "Resources usage" type: series size: {1,0.5} position: {0, 0.5} {
			    loop r over: resources_E{
			    	data r value: tick_impacts_E[r]; // note : energy consumed by other blocs included here
			    }
			}
	    }
	}
}