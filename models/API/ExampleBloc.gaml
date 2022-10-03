/**
* Name: Example bloc (MOSIMA)
* Authors: Maël Franceschetti, Cédric Herpson, Jean-Daniel Kant
* Mail: firstname.lastname@lip6.fr
*/
model ExampleBloc

import "API.gaml"


global{

	map<string, int> tick_behaviors <- [];
	list behaviors <- ["A", "B", "C"];
	list resources <- ["R1", "R2", "R3", "R4"];
	map<string,int> tick_impacts <- [];
	map behavior_impacts <- [
		"A"::["R1"::1500.0, "R2"::2500.0, "R3"::3000.0, "R4"::1500.0],
		"B"::["R1"::1100.0, "R2"::2000.0, "R3"::2400.0, "R4"::1100.0],
		"C"::["R1"::900.0, "R2"::1750.0, "R3"::2000.0, "R4"::950.0]
	];

}

species example_bloc parent:bloc{
	string name <- "generic";
	list behavior_prop <- [0.2, 0.5, 0.3];
	production_agent producer <- nil;

	list<string> get_possible_behaviors{
		return behaviors;
	}
	
	list<string> get_possible_resources_used{
		return resources;
	}
	
	production_agent get_producer{
		return producer;
	}
	
	map<string, float> get_tick_resources_used{
		map<string, float> conso <- [];
		ask example_producer{
			conso <- self get_tick_consumptions [];
		}
		return conso;
	}
	
	map<string, float> get_tick_behaviors{
		map<string, float> behaviors <- [];
		ask example_consumer{
			behaviors <- self get_tick_behaviors [];
		}
		return behaviors;
	}
	
	action set_external_producer(string product, bloc bloc_agent){
		// do nothing 
	}
	
	action end_tick{
		// do nothing
	}


	species example_producer parent:production_agent{
		map<string, float> tick_consumption <- [];
		
		map<string, float> get_tick_consumptions{
			return tick_consumption;
		}
	
		action new_tick{ // reset impact counters
			loop u over: resources{
				tick_consumption[u] <- 0.0; // reset resources usage
			}
		}
		
		bool produce(map<string,float> demand){ // quantify the impact of the choice of the individuals
			loop c over: demand.keys{
				loop u over: resources{
					tick_consumption[u] <- tick_consumption[u] + behavior_impacts[c][u] * demand[c];
				}
			}
			return true; // for this example, production always returns OK signal
		}
		
		action set_external_producer(string product, bloc bloc_agent){
			// do nothing
		}
	}
	
	species example_consumer parent:consumption_agent{
	
		map<string,int> consumed <- [];
		
		map<string, float> get_tick_behaviors{
			return copy(consumed);
		}
		
		init{
			loop c over: behaviors{
				consumed[c] <- 0;
			}
		}
		
		action new_tick{ // reset choices counters
    		loop c over: consumed.keys{
    			consumed[c] <- 0;
    		}
		}
		
		action consume(human h){ // apply the consumption pattern to each individual
		    string choice <- behaviors[rnd_choice(behavior_prop)];
			consumed[choice] <- consumed[choice]+1;
		}
	}
	
	action setup{
		list<example_producer> producers <- [];
		create example_producer number:1 returns: producers; // instanciate the production handler
		create example_consumer number:1; // instanciate the consumption handler
		producer <- first(producers); // assuming there is only one producer per bloc here, take the first
	}
	
	action new_tick{
		if(cycle > 0){ // skip it the first tick
	    	ask example_consumer{ // prepare next tick on consumer side
	    		do new_tick;
	    	}
	    	
	    	ask example_producer{ // prepare next tick on producer side
	    		do new_tick;
	    	}
    	}
	}
	
	action population_activity(list<human> pop) {
    	ask pop{ // execute the consumption behavior of the population
    		ask myself.example_consumer{
    			do consume(myself); // individuals consume goods
    		}
    	}
    	
    	ask example_consumer{
    		ask example_producer{
    			loop c over: myself.consumed.keys{
		    		do produce([c::myself.consumed[c]]); // produce the required quantities
		    	}
		    } // individuals consume goods
    	}
    	tick_behaviors <- self get_tick_behaviors []; // collect consumption behaviors
    	tick_impacts <- self get_tick_resources_used []; // collect resources used
    }
    
}

experiment run_generic type: gui {

	output {
		display General_information {
			chart "Behavior evolution (number users per tick)" type: series  size: {1,0.5} position: {0, 0} {
			    loop c over: behaviors{
			    	data c value: tick_behaviors[c];
			    }
			}
			chart "Resources usage (resources consumption per tick)" type: series size: {1,0.5} position: {0, 0.5} {
			    loop r over: resources{
			    	data r value: tick_impacts[r];
			    }
			}
	    }
	}
}