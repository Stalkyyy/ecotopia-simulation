/**
* Name: API (MOSIMA)
* Authors: Maël Franceschetti, Cédric Herpson, Jean-Daniel Kant
* Mail: firstname.lastname@lip6.fr
*/


model API

/*
 * Species used to represent a bloc.
 */
species bloc{
	string name; // the name of the bloc
	production_agent producer; // the production agent of the bloc
	
	/* Initialize the bloc */
	action setup virtual:true;
	
	/* Execute the next tick */
	action tick(list<human> pop) virtual:true;
	
	/* Returns the labels of the resources used by this bloc for production (inputs) */
	action get_input_resources_labels virtual:true type:list<string>;
	
	/* Returns the labels of the resources produced by this bloc (outputs) */
	action get_output_resources_labels virtual:true type:list<string>;
	
}

/* 
 * Species used to represent all the production of a bloc.
 * Note : this species will be implemented as a micro-species of its bloc.
 */
species production_agent{
	
	/* Produce the given resources in the requested quantities */
	action produce(map<string, float> demand) virtual:true type:bool;
	
	/* Returns all the resources used for the production this tick */
	action get_tick_inputs_used virtual:true type: map<string, float>;
	
	/* Returns the amounts produced this tick */
	action get_tick_outputs_produced virtual:true type: map<string, float>;
	
	/* Returns the amounts emitted this tick */
	action get_tick_emissions virtual:true type: map<string, float>;
	
	/* Defines an external producer for a resource */
	action set_supplier(string product, bloc bloc_agent) virtual:true; 
}

/* 
 * Species used to represent all the consumption of the population related to a bloc.
 * Note : this species will be implemented as a micro-species of its bloc.
 */
species consumption_agent{
	
	/* Apply the consumption behavior of a given human */
	action consume(human h) virtual:true;
	
	/* Returns the amount of resources consumed by the population this tick */
	action get_tick_consumption virtual:true type: map<string, float>;
}
	
species human{
	int age <- 0; // age (in years)
	string gender <- ""; // gender
	map<string,string> additional_attributes <- [];														
}


species coordinator{
	map<string, bloc> registered_blocs <- []; // the blocs handled by the coordinator
	map<string, bloc> producers <-[]; // the producer registered for each resource
	list<string> scheduling <- []; // blocs execution order
	bool started <- false; // the current state of the coordinator (started or waiting)

	/* Returns all the agents of a given species and its subspecies */
	list<agent> get_all_instances(species<agent> spec) {
	    return spec.population +  spec.subspecies accumulate (get_all_instances(each));
	}
	
	/* Register a bloc : it will be handled by the coordinator */
	action register_bloc(bloc b){
		list<string> products <- [];
		ask b{
			do setup; // setup the bloc
			products <- get_output_resources_labels();
		}
		registered_blocs[b.name] <- b;
		loop p over: products{ // register this bloc as producer of product p
			producers[p] <- b;
		}
		if !(b.name in scheduling){
			scheduling <- scheduling + b.name;
		}
	}
	
	/* Affects the external producers (when a bloc needs the production of another bloc, this one is its exernal producer) */
	action affect_suppliers{
		loop b over: registered_blocs.values{
			list<string> resources_used <- b.get_input_resources_labels();
			loop r over: resources_used{
				if(producers.keys contains r){ // there is a known producer for this resource/good
					ask b.producer {
						do set_supplier(r, myself.producers[r]); // link the external producer to the bloc needing it
					}
				}
			}
		}
	}

	/* Defines the scheduling of the different blocs */
	action set_scheduling(list<string> scheduling_order){
		scheduling <- scheduling_order;
	}

	/* Register all the blocs */
	action register_all_blocs{
		list<bloc> blocs <- get_all_instances(bloc);
		
		loop b over: blocs{
			do register_bloc(b); //register the bloc
		}
		write "registered blocs : "+registered_blocs;
		if length(scheduling) = 0{
			scheduling <- blocs collect each.name; // set default scheduling order
		}
		do affect_suppliers();
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

		list<human> pop <- get_all_instances(human);	

		loop bloc_name over: scheduling{ // move to next tick for all blocs, following the defined scheduling
			if bloc_name in registered_blocs.keys{
				ask registered_blocs[bloc_name]{
					do tick(pop);
				}
			}else{
				write "warning : bloc "+bloc_name+" not found !";
				// if you have this warning, check that the name of the blocs in the scheduling are correct
			}
		}
	}
}

/* Territory species (used to represent GIS elements) */

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



