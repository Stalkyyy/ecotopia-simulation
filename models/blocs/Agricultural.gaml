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
	list behaviors_A <- ["INCA3", "flexitarian", "vegetarian"];
	list resources_A <- ["L water", "kWh energy", "m² land", "gCO2e emissions"];
	
	/* Parameters */
	list behavior_prop <- [0.75, 0.20, 0.05]; // distribution of the behaviors in the population
	int update_distrib_every_x_cycles <- 6; // delay between two updates of the distribution of the behaviors
	float update_distrib_change <- 0.01; // the amount of change in the distribution of the behaviors at each update
	
	/* Input data */
	map behavior_input_output_A <- [
		"INCA3"::["L water"::1500.0, "kWh energy"::250.0, "m² land"::300.0, "gCO2e emissions"::1800.0],
		"flexitarian"::["L water"::1100.0, "kWh energy"::200.0, "m² land"::240.0, "gCO2e emissions"::1300.0],
		"vegetarian"::["L water"::900.0, "kWh energy"::175.0, "m² land"::200.0, "gCO2e emissions"::1050.0]
	]; // Note : this is fake data (not the real amound of resources used and emitted).
	
	/* Counters & Stats */
	map<string, int> tick_behaviors_A <- [];
	map<string,int> tick_impacts_A <- [];
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

	list<string> get_possible_behaviors{
		return behaviors_A;
	}
	
	/* Reflex : update the distribution of the behaviors to allow a certain amount change */
	reflex update_behavior_prop when:(cycle mod update_distrib_every_x_cycles = 0){ // update distribution every x cycles
		list<float> tmp_prop <- copy(behavior_prop);
		loop i from:0 to:length(tmp_prop)-1{ // a part of the population will keep its actual behavior
			tmp_prop[i] <- tmp_prop[i] * (1.0 - update_distrib_change); 
		}
		list<float> rep_change <- [];
		float tot <- 0.0;
		loop i from:0 to:length(tmp_prop)-1{ // the others will change their behavior
			rep_change <- rep_change + [rnd(1.0)]; // randomly distribute the change on the different behaviors
			tot <- tot + rep_change[i];
		}
		rep_change <- shuffle(rep_change);
		loop i from:0 to:length(rep_change)-1{
			tmp_prop[i] <- tmp_prop[i] + (rep_change[i]/tot) * update_distrib_change ; 
		}
		behavior_prop <- tmp_prop; // update behavior distribution
	}
	
	list<string> get_possible_resources_used{
		return resources_A;
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
	
	/**
	 * We define here the production agent of the agricultural bloc as a micro-species (equivalent of nested class in Java).
	 * We implement the methods of the API.
	 * The production is very simple here : for each behavior, we apply an average resource consumption and emissions.
	 * Some of those resources can be provided by other blocs (external producers).
	 */
	species agri_producer parent:production_agent{
		map<string, bloc> external_producers; // external producers that provide the needed resources
		map<string, float> tick_consumption;
		
		init{
			external_producers <- []; // external producers that provide the needed resources
			tick_consumption <- [];
		}
		
		map<string, float> get_tick_consumptions{
			return tick_consumption;
		}
		
		action set_external_producer(string product, bloc bloc_agent){
			write name+": external producer "+bloc_agent+" set for "+product;
			external_producers[product] <- bloc_agent;
		}
	
		action new_tick{ // reset impact counters
			loop u over: resources_A{
				tick_consumption[u] <- 0.0; // reset resources usage
			}
		}
		
		bool produce(map<string,float> demand){
			bool ok <- true;
			loop c over: demand.keys{
				loop u over: resources_A{
					float quantity_needed <- behavior_input_output_A[c][u] * demand[c]; // quantify the resources consumed/emitted by this demand
					tick_consumption[u] <- tick_consumption[u] + quantity_needed;
					if(external_producers.keys contains u){ // if there is a known external producer for this product/good
						bool av <- external_producers[u].producer.produce([u::quantity_needed]); // ask the external producer to product the required quantity
						if not av{
							ok <- false;
						}
					}
				}
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
		
		map<string, float> get_tick_behaviors{
			return copy(consumed);
		}
		
		init{
			loop c over: behaviors_A{
				consumed[c] <- 0;
			}
		}
		
		action new_tick{ 
    		loop c over: consumed.keys{ // reset choices counters
    			consumed[c] <- 0;
    		}
		}
		
		action consume(human h){ 
		    string choice <- behaviors_A[rnd_choice(behavior_prop)]; // draw a behavior following the given distribution
			consumed[choice] <- consumed[choice]+1;
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
    	tick_behaviors_A <- get_tick_behaviors(); // collect consumption behaviors
    	tick_impacts_A <- get_tick_resources_used(); // collect resources used
   	}
    
}


/**
 * We define here the experiment and the displays related to agricultural. 
 * We will then be able to run this experiment from the Main code of the simulation, with all the blocs connected.
 * 
 * Note : experiment car inherit another experiment, bu we can't combine displays from multiple experiments at the same time. 
 * If needed, a new experiment combining all those displays should be added, for example in the Main code of the simulation.
 */
experiment run_agricultural type: gui {
	output {
		display Agricultural_information {
			chart "Population consumption" type: series  size: {1,0.5} position: {0, 0} {
			    loop c over: behaviors_A{
			    	data c value: tick_behaviors_A[c];
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