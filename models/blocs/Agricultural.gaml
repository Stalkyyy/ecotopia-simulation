/**
* Name: Agricultural bloc (MOSIMA)
* Authors: Maël Franceschetti, Cédric Herpson, Jean-Daniel Kant
* Mail: firstname.lastname@lip6.fr
*/

model Agricultural

import "../API/API.gaml"

/**
 * We define here the global variables of the bloc. Some are needed for the displays (charts, series...).
 * We define the input data used by the bloc.
 */
global{

	/* Setup */
	list productions_A <- ["kg_meat", "kg_vegetables"];
	list resources_A <- ["L water", "kWh energy", "m² land", "gCO2e emissions"];
	
	/* Parameters */
	map consumption_qt <- ["kg_meat"::5.2, "kg_vegetables"::12.5]; // monthly consumption per individual of the population. Note : this is fake data.
	
	/* Input data */
	map production_input_output_A <- [
		"kg_meat"::["L water"::2500.0, "kWh energy"::450.0, "m² land"::500.0, "gCO2e emissions"::3500.0],
		"kg_vegetables"::["L water"::900.0, "kWh energy"::175.0, "m² land"::100.0, "gCO2e emissions"::1000.0]
	]; // Note : this is fake data (not the real amound of resources used and emitted)
	
	/* Counters & Stats */
	map<string, float> tick_production_A <- [];
	map<string, float> tick_pop_consumption_A <- [];
	map<string, float> tick_impacts_A <- [];
}

/**
 * We define here the agricultural bloc as a species.
 * We implement the methods of the API.
 * We also add methods specific to this bloc to consumption behavior of the population.
 */
species agricultural parent:bloc{
	string name <- "agricultural";
	
	agri_producer producer <- nil;
	agri_consumer consumer <- nil;
	
	action set_external_producer(string product, bloc bloc_agent){
		ask producer{
			do set_external_producer(product, bloc_agent);
		}
	}
	
	production_agent get_producer{
		return producer;
	}

	list<string> get_possible_consumptions{
		return productions_A;
	}
	
	list<string> get_possible_resources_used{
		return resources_A;
	}
	
	map<string, float> get_tick_resources_used{
		return producer.get_tick_resources_used();
	}
	
	map<string, float> get_tick_consumptions{
		return consumer.get_tick_consumptions();
	}
	
	map<string, float> get_tick_production{
		return producer.get_tick_production();
	}
	
	
	/**
	 * We define here the production agent of the agricultural bloc as a micro-species (equivalent of nested class in Java).
	 * We implement the methods of the API.
	 * The production is very simple here : for each behavior, we apply an average resource consumption and emissions.
	 * Some of those resources can be provided by other blocs (external producers).
	 */
	species agri_producer parent:production_agent{
		map<string, bloc> external_producers; // external producers that provide the needed resources
		map<string, float> tick_resources_used <- [];
		map<string, float> tick_production <- [];
		
		init{
			external_producers <- []; // external producers that provide the needed resources
		}
		
		map<string, float> get_tick_resources_used{
			return tick_resources_used;
		}
		
		map<string, float> get_tick_production{
			return tick_production;
		}
		
		action set_external_producer(string product, bloc bloc_agent){
			write name+": external producer "+bloc_agent+" set for "+product;
			external_producers[product] <- bloc_agent;
		}
	
		action new_tick{ // reset impact counters
			loop u over: resources_A{
				tick_resources_used[u] <- 0.0; // reset resources usage
			}
			loop p over: productions_A{
				tick_production[p] <- 0.0; // reset productions
			}
		}
		
		bool produce(map<string,float> demand){
			bool ok <- true;
			loop c over: demand.keys{
				loop u over: resources_A{
					float quantity_needed <- production_input_output_A[c][u] * demand[c]; // quantify the resources consumed/emitted by this demand
					tick_resources_used[u] <- tick_resources_used[u] + quantity_needed;
					if(external_producers.keys contains u){ // if there is a known external producer for this product/good
						bool av <- external_producers[u].producer.produce([u::quantity_needed]); // ask the external producer to product the required quantity
						if not av{
							ok <- false;
						}
					}
				}
				tick_production[c] <- tick_production[c] + demand[c];
			}
			return ok;
		}
	}
	
	/**
	 * We define here the consumption agent of the agricultural bloc as a micro-species (equivalent of nested class in Java).
	 * We implement the methods of the API.
	 * The consumption is very simple here : each behavior as a certain probability to be selected.
	 */
	species agri_consumer parent:consumption_agent{
	
		map<string,int> consumed <- [];
		
		map<string, float> get_tick_consumptions{
			return copy(consumed);
		}
		
		init{
			loop c over: productions_A{
				consumed[c] <- 0;
			}
		}
		
		action new_tick{ 
    		loop c over: consumed.keys{ // reset choices counters
    			consumed[c] <- 0;
    		}
		}
		
		action consume(human h){ 
		    loop c over: consumption_qt.keys{
		    	consumed[c] <- consumed[c]+consumption_qt[c];
		    }
		}
	}
	
	action setup{
		list<agri_producer> producers <- [];
		list<agri_consumer> consumers <- [];
		create agri_producer number:1 returns:producers; // instanciate the agricultural production handler
		create agri_consumer number:1 returns: consumers; // instanciate the agricultural consumption handler
		producer <- first(producers);
		consumer <- first(consumers);
	}
	
	action new_tick{
		if(cycle > 0){ // skip it the first tick
	    	ask agri_consumer{ // prepare next tick on consumer side
	    		do new_tick;
	    	}
	    	
	    	ask agri_producer{ // prepare next tick on producer side
	    		do new_tick;
	    	}
    	}
	}
	
	action population_activity(list<human> pop) {
    	ask pop{ // execute the consumption behavior of the population
    		ask myself.agri_consumer{
    			do consume(myself); // individuals consume agricultural goods
    		}
    	}
    	 
    	ask agri_consumer{ // produce the required quantities
    		ask agri_producer{
    			loop c over: myself.consumed.keys{
		    		bool ok <- produce([c::myself.consumed[c]]); // send the demands to the producer
		    		// note : in this example, we do not take into account the 'ok' signal.
		    	}
		    }
    	}
    }
    
    action end_tick{
    	tick_pop_consumption_A <- get_tick_consumptions(); // collect consumption behaviors
    	tick_impacts_A <- get_tick_resources_used(); // collect resources used
    	tick_production_A <- get_tick_production(); // collect production
   	}
    
}


/**
 * We define here the experiment and the displays related to agricultural. 
 * We will then be able to run this experiment from the Main code of the simulation, with all the blocs connected.
 * 
 * Note : experiment car inherit another experiment, but we can't combine displays from multiple experiments at the same time. 
 * If needed, a new experiment combining all those displays should be added, for example in the Main code of the simulation.
 */
experiment run_agricultural type: gui {
	output {
		display Agricultural_information {
			chart "Population direct consumption" type: series  size: {0.5,0.5} position: {0, 0} {
			    loop c over: productions_A{
			    	data c value: tick_pop_consumption_A[c]; // note : products consumed by other blocs NOT included here (only population direct consumption)
			    }
			}
			chart "Total production" type: series  size: {0.5,0.5} position: {0.5, 0} {
			    loop c over: productions_A{
			    	data c value: tick_production_A[c];
			    }
			}
			chart "Resources usage" type: series size: {1,0.5} position: {0, 0.5} {
			    loop r over: resources_A{
			    	data r value: tick_impacts_A[r];
			    }
			}
	    }
	}
}