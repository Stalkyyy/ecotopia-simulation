/**
* Name: API (MOSIMA)
* Authors: Maël Franceschetti, Cédric Herpson, Jean-Daniel Kant
* Mail: firstname.lastname@lip6.fr
*/


model API

species bloc{
	string name; // the name of the bloc
	production_agent producer; // the production agent of the bloc
	
	/* Initialize the bloc */
	action setup virtual:true;
	
	/* Move to the next tick */
	action new_tick virtual:true;
	
	/* End to the current tick */
	action end_tick virtual:true;
	
	/* Execute the consumption behavior of the population (cf consumption_agent) */
	action population_activity(list<human> pop) virtual:true;
	
	/* Returns the possible consumptions/behaviors of the population for this bloc */
	action get_possible_consumptions virtual:true type:list<string>;
	
	/* Returns the resources that can be used (consumed of emitted) by this bloc */
	action get_possible_resources_used virtual:true type:list<string>;
	
}

species production_agent{

	/* Move to the next tick */
	action new_tick virtual:true;
	
	/* Produce the given resources in the requested quantities */
	action produce(map<string, float> demand) virtual:true type:bool;
	
	/* Returns all the resources used for the production this tick */
	action get_tick_resources_used virtual:true type: map<string, float>;
	
	/* Returns the amounts produced this tick */
	action get_tick_production virtual:true type: map<string, float>;
	
	/* Defines an external producer for a resource */
	action set_external_producer(string product, bloc bloc_agent) virtual:true; 
}

species consumption_agent{
	
	/* Move to the next tick */
	action new_tick virtual:true;
	
	/* Apply the consumption behavior of a given human */
	action consume(human h) virtual:true;
	
	/* Returns all the consumptions/behaviors applied this tick */
	action get_tick_consumptions virtual:true type: map<string, float>;
}
	
species human{
	int age <- 0; // age (in years)
	string gender <- ""; // gender
	map<string,string> additional_attributes <- [];														
}


species coordinator{
	map<string, bloc> registered_blocs <- []; // the blocs handled by the coordinator
	map<string, bloc> producers <-[]; // the producer registered for each resource
	bool started <- false; // the current state of the coordinator (started or waiting)

	/* Returns all the agents of a given species and its subspecies */
	list<agent> get_all_instances(species<agent> spec) {
	    return spec.population +  spec.subspecies accumulate (get_all_instances(each));
	}
	
	/* Register a bloc : it will be handled by the coordinator */
	action register_bloc(string name, bloc b){
		list<string> products <- [];
		ask b{
			do setup; // setup the bloc
			products <- get_possible_consumptions();
		}
		registered_blocs[name] <- b;
		loop p over: products{ // register this bloc as producer of product p
			producers[p] <- b;
		}
	}
	
	/* Affects the external producers (when a bloc needs the production of another bloc, this one is its exernal producer) */
	action affect_external_producers{
		loop b over: registered_blocs.values{
			list<string> resources_used <- b.get_possible_resources_used();
			loop r over: resources_used{
				if(producers.keys contains r){ // there is a known producer for this resource/good
					ask b.producer {
						do set_external_producer(r, myself.producers[r]); // link the external producer to the bloc needing it
					}
				}
			}
		}
	}
	
	/* Register all the blocs */
	action register_all_blocs{
		list<bloc> blocs <- get_all_instances(bloc);
		loop b over: blocs{
			do register_bloc(b.name, b); //register the bloc
		}
		write "registered blocs : "+registered_blocs;
		do affect_external_producers();
	}
	
	/* Start the simulation */
	action start{
		started <- true;
	}
	
	/* Stop the simulation */
	action stop{
		started <- false;
	}
	
	/* Reflex : move to the next tick of the simulation */
	reflex new_tick when: started{
		loop bloc_agent over:registered_blocs.values{ // move to next tick for all blocs
			ask bloc_agent{
				do new_tick;
			}
		}
	
		list<human> pop <- get_all_instances(human);
		loop bloc_agent over:registered_blocs.values{
			ask bloc_agent{
				do population_activity(pop); // execute population activity for the current tick
			}
		}
		
		loop bloc_agent over:registered_blocs.values{
			ask bloc_agent{
				do end_tick; // end the tick for all blocs
			}
		}

	}

}

/* Territory species */

species fronteers {
	string type; 
	rgb color <- #whitesmoke;
	rgb border_color <- #dimgray;
	aspect base {
		draw shape color: color border: border_color;
	}
}

species mountain {
	string type; 
	rgb color <- #silver;
	
	aspect base {
		draw shape color: color ;
	}
}

species forest {
	string type; 
	rgb color <- #mediumseagreen;
	
	aspect base {
		draw shape color: color ;
	}
}

species water_source {
	string type; 
	rgb color <- #royalblue;
	
	aspect base {
		draw shape color: color ;
	}
}

species city {
	string type; 
	rgb color <- #black;
	
	aspect base {
		draw circle(2.0#px) color: color ;
	}
}



