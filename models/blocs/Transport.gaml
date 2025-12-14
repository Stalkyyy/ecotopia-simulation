/**
* Name: Transport
* Based on the internal empty template. 
* Author: Victor Fleiser / Thomas Marchand
* Tags: 
*/

model Transport

import "../API/API.gaml"

/**
 * We define here the global variables and data of the bloc. Some are needed for the displays (charts, series...).
 */
global{

	/* Setup */
	list<string> production_inputs_T <- ["kWh energy"];
	list<string> production_outputs_T <- ["km/person_scale_1_transport", "km/person_scale_2_transport", "km/person_scale_3_transport","km/kg_scale_1_transport","km/kg_scale_2_transport","km/kg_scale_3_transport"];
	list<string> production_emissions_T <- ["gCO2e emissions"];
	
	/* DATA */
	list<string> vehicles <- ["truck", "train", "taxi", "minibus", "bicycle", "walk"];
	
	// TODO: not real values -> change to the real values
	// TODO: also maybe read them from a csv or something
	map<string, map<string, float>> vehicle_data <- [
		"truck"::[
			"quantity"::1000, // number of vehicles available in france
			"capacity"::5000, // in kg (on average, not always full)
			"consumption"::1000, // in kWh per km
			"lifetime"::600, // in months
			"emissions"::1000 // GES per km
		],
		"train"::[
			"quantity"::1000, // number of vehicles available in france
			"capacity"::100, // in persons (on average, not always full)
			"consumption"::1000, // in kWh per km
			"lifetime"::600, // in months
			"emissions"::1000 // GES per km
		],
		"taxi"::[
			"quantity"::1000, // number of vehicles available in france
			"capacity"::3, // in persons (on average, not always full)
			"consumption"::1000, // in kWh per km
			"lifetime"::600, // in months
			"emissions"::1000 // GES per km
		],
		"minibus"::[
			"quantity"::1000, // number of vehicles available in france
			"capacity"::10, // in persons (on average, not always full)
			"consumption"::1000, // in kWh per km
			"lifetime"::600, // in months
			"emissions"::1000 // GES per km
		],
		"bicycle"::[
			"quantity"::10000, // number of vehicles available in france
			"capacity"::1, // in persons (on average, not always full)
			"consumption"::1000, // in kWh per km
			"lifetime"::600, // in months
			"emissions"::10 // GES per km
		],
		"walk"::[
			"quantity"::1, // number of vehicles available in france
			"capacity"::1, // in persons (on average, not always full)
			"consumption"::0, // in kWh per km
			"lifetime"::0, // in months
			"emissions"::0 // GES per km
		]
	];
	
	
	/* Production data */ //TODO: remove
	map<string, map<string, float>> production_output_inputs_T <- [
		"km/person_scale_1_transport"::["kWh energy"::20.0],
		"km/person_scale_2_transport"::["kWh energy"::400.0],
		"km/person_scale_3_transport"::["kWh energy"::200.0],
		"km/kg_scale_1_transport"::["kWh energy"::10.0],
		"km/kg_scale_2_transport"::["kWh energy"::20.0],
		"km/kg_scale_3_transport"::["kWh energy"::15.0]
	]; // Note : this is fake data (not the real amound of resources used and emitted)
	map<string, map<string, float>> production_output_emissions_T <- [
		"km/person_scale_1_transport"::["gCO2e emissions"::100.0],
		"km/person_scale_2_transport"::["gCO2e emissions"::200.0],
		"km/person_scale_3_transport"::["gCO2e emissions"::150.0],
		"km/kg_scale_1_transport"::["gCO2e emissions"::1.0],
		"km/kg_scale_2_transport"::["gCO2e emissions"::2.0],
		"km/kg_scale_3_transport"::["gCO2e emissions"::1.5]
	]; // Note : this is fake data (not the real amound of resources used and emitted)
	
	/* Consumption data *///TODO: remove
	map<string, float> indivudual_consumption_T <- [
	"km/person_scale_1_transport"::10.0,
	"km/person_scale_2_transport"::50.0,
	"km/person_scale_3_transport"::500.0,
	"km/kg_scale_1_transport"::1000.0,
	"km/kg_scale_2_transport"::5000.0,
	"km/kg_scale_3_transport"::5000.0
	]; // monthly consumption per individual of the population. Note : this is fake data.
	
	/* Counters & Stats *///TODO: change to the right metrics
	map<string, float> tick_production_T <- [];
	map<string, float> tick_pop_consumption_T <- [];
	map<string, float> tick_resources_used_T <- [];
	map<string, float> tick_emissions_T <- [];

	init{ // a security added to avoid launching an experiment without the other blocs
		if (length(coordinator) = 0){
			error "Coordinator agent not found. Ensure you launched the experiment from the Main model";
			// If you see this error when trying to run an experiment, this means the coordinator agent does not exist.
			// Ensure you launched the experiment from the Main model (and not from the bloc model containing the experiment).
		}
	}
}


/**
 * We define here the transport bloc as a species.
 * We implement the methods of the API.
 */
species transport parent:bloc{
	// DATA :
	
	// number of vehicules in france (all scales for now?), this number decreases when vehicles reach their end of lifetime, it increases when a new vehicle is created
	// TODO: also handle the age of the vehicles
	map<string, int> number_of_vehicles <- []; // initialized in setup()



	// CODE :

	// number of vehicles in france (all scales for now?) still available for the current tick, this number resets at the start of the tick, if it becomes negative -> new vehicles must be created to answer the demand
	// TODO: implement all the logic for resetting at each tick, and for creating new vehicles when in the negatives
	map<string, float> number_of_vehicles_available <- []; // initialized in setup()


	// name of the bloc :
	string name <- "transport";
	
	// production_agent and consumption_agent handling all production/consumption by this bloc
	transport_producer producer <- nil;
	transport_consumer consumer <- nil;
	
	// sets up the values of vaiables
	// sets up the bloc by creating the producers and consumers of the bloc (NB : these are not the other blocs but the production_agent and consumption_agent)
	action setup{
		loop v over:vehicles{
			number_of_vehicles[v] <- int(vehicle_data[v]["quantity"]);
			number_of_vehicles_available[v] <- vehicle_data[v]["quantity"];
		}

		list<transport_producer> producers <- [];
		list<transport_consumer> consumers <- [];
		create transport_producer number:1 returns:producers; // instanciate the transport production handler
		create transport_consumer number:1 returns: consumers; // instanciate the transport consumption handler
		producer <- first(producers);
		consumer <- first(consumers);
	}

	// every tick : we collect/reset the data to display from the producer and consumer
	// then we calculate the consumption in transports for the population (TODO: see if this is done here or by the Population bloc?)
	action tick(list<human> pop){
		do collect_last_tick_data();
		do population_activity(pop);
	}
	
	// action to set an other bloc to produce ressources for us (Energy Bloc as our producer of energy)
	action set_external_producer(string product, bloc bloc_agent){
		ask producer{
			do set_supplier(product, bloc_agent);
		}
	}
	
	// return the producer agent of the bloc
	production_agent get_producer{
		return producer;
	}
	
	// returns the labels for the ressources we create
	list<string> get_output_resources_labels{
		return production_outputs_T;
	}
	
	// returns the labels for the ressources we need
	list<string> get_input_resources_labels{
		return production_inputs_T;
	}

	// returns the labels for the emissions we create
	list<string> get_emissions_labels{
		return production_emissions_T;
	}
	
	// collects the data to display from the producer and consumer, then resets the values for the new tick to come
	action collect_last_tick_data{
		if(cycle > 0){ // skip it the first tick
			tick_pop_consumption_T <- consumer.get_tick_consumption(); // collect consumption behaviors
	    	tick_resources_used_T <- producer.get_tick_inputs_used(); // collect resources used
	    	tick_production_T <- producer.get_tick_outputs_produced(); // collect production
	    	tick_emissions_T <- producer.get_tick_emissions(); // collect emissions
	    	
	    	ask transport_consumer{ // prepare new tick on consumer side
	    		do reset_tick_counters;
	    	}
	    	
	    	ask transport_producer{ // prepare new tick on producer side
	    		do reset_tick_counters;
	    	}
    	}
	}
	
	// calculates the consumption in transports for the population (TODO: see if this is done here or by the Population bloc?)
	action population_activity(list<human> pop) {
		// TODO: this might be removed
    	ask pop{ // execute the consumption behavior of the population
    		ask myself.transport_consumer{
    			do consume(myself); // individuals consume transport goods
    		}
    	}
    	 
    	ask transport_consumer{ // produce the required quantities
    		ask transport_producer{
    			loop c over: myself.consumed.keys{
		    		bool ok <- produce([c::myself.consumed[c]]); // send the demands to the producer
		    		// note : in this example, we do not take into account the 'ok' signal.
		    	}
		    }
    	}
    }
	
	
	/**
	 * Agent qui s'occupe de toutes les production du bloc
	 * (I don't know if in the future there will be multiple of this agent for each scale, or if those will be sub agents of this agent)
	 */
	species transport_producer parent:production_agent{
		map<string, bloc> external_producers; // Energy Bloc 
		map<string, float> tick_resources_used <- []; // ressources used during this tick to make transport ressources (energy)
		map<string, float> tick_production <- []; // transport ressources created during this tick
		map<string, float> tick_emissions <- []; // emissions produced during this tick
		
		init{
			external_producers <- []; // external producers that provide the needed resources
		}
		
		/* Returns all the resources (energy) used for the production this tick */
		map<string, float> get_tick_inputs_used{
			return tick_resources_used;
		}
		
		/* Returns the amounts produced this tick */
		map<string, float> get_tick_outputs_produced{
			return tick_production;
		}
		
		/* Returns the amounts emitted this tick */
		map<string, float> get_tick_emissions{
			return tick_emissions;
		}
		
		/* Defines an external producer for a resource (Energy Bloc) */
		action set_supplier(string product, bloc bloc_agent){
			write name+": external producer "+bloc_agent+" set for "+product;
			external_producers[product] <- bloc_agent;
		}
		
		// reset the values for the new tick to come
		action reset_tick_counters{ // reset impact counters
			loop u over: production_inputs_T{
				tick_resources_used[u] <- 0.0; // reset resources usage
			}
			loop p over: production_outputs_T{
				tick_production[p] <- 0.0; // reset productions
			}
			loop e over: production_emissions_T{
				tick_emissions[e] <- 0.0;
			}
		}
		
		// returns the vehicle used by a person based on the distance travelled
		// TODO: improve modelisation by using accurate numbers, maybe even take the quantity of people in parameter and return a proportion of the usage for each vehicle based on the distance 
		string get_vehicle_used(float distance){
			if (distance < 0.2) {
				return "walk";
			}
			else if (distance < 1.0){
				return "bicycle";
			}
			else if (distance < 4.0){
				return "minibus";
			}
			else if (distance < 50.0){
				return "taxi";
			}
			else {
				return "train";
			}
		}

		// returns the amount of energy used by a given vehicle type, quantity, and distance

		/** produce ressources to answer a demand in transport 
		 * parameters :
		 * - type : string ("material" ou "person")
		 * - quantity : float (in kg or number of people)
		 * - scale : int (1, 2, or 3) (1 : France, 2 : inter-regions or outside mini-cities, 3 : in mini-city)
		 * - distance : float (in km)
		 * 
		 * returns : true, unless an argument is invalid in which case it will return early false (will also generate a warning)  
		 */   
		bool produce_transport(string type, float quantity, int scale, float distance){
			// test inputs :
			if ((type != "material") and (type != "person")) {
				warn "Warning from " + self + " : the parameter 'type' is invalid, it should be 'material' or 'person', but '"+ type +"' was received instead";
				return false;
			}
			if (scale > 3 or scale < 1){
				warn "Warning from " + self + " : the parameter 'scale' is invalid, it should be 1, 2, or 3, but "+ scale +" was received instead";
				return false;
			}
			
			// for now we don't differenciate the scales, TODO: implement the 3 scales
			
			// vehicle used
			string vehicle_used <- "truck";
			if (type = "person"){
				 vehicle_used <- get_vehicle_used(distance);
			}
			
			// we calculate the number of vehicles used for this transport
			float number_of_vehicles_used <- quantity / vehicle_data[type]["capacity"];

			// update the number of vehicles left available, TODO: implement vehicle creation for when there is a negative number of vehicles left
			number_of_vehicles_available[type] <- number_of_vehicles_available[type] - number_of_vehicles_used;
			
			// calculate energy used
			float energy_used <- number_of_vehicles_used * vehicle_data[type]["consumption"] * distance;
			
			// make energy demand
			string energy_label <- "kWh energy";
			if(external_producers.keys contains energy_label){ // if there is a known external producer for energy
				bool av <- external_producers[energy_label].producer.produce([energy_label::energy_used]); // ask the external producer to product the required quantity
				if not av{
					write("[Transport] : we received false from the Energy Block when requesting for energy, is this normal ?");
				}
			}
			
			// make emissions
			string emission_label <- "gCO2e emissions";
			float quantity_emitted <- number_of_vehicles_used * vehicle_data[type]["emissions"] * distance;
			tick_emissions[emission_label] <- tick_emissions[emission_label] + quantity_emitted;
			
			return true;
		}
		
		// produce ressources to answer a demand in transport 
		// THIS IS THE OLD VERSION BASED ON THE OTHER BLOCKS INITIAL CODE, THIS WILL BE REMOVED/MODIFIED
		bool produce(map<string,float> demand){
			bool ok <- true;
			loop c over: demand.keys{
				loop u over: production_inputs_T{
					float quantity_needed <- production_output_inputs_T[c][u] * demand[c]; // quantify the resources consumed/emitted by this demand
					tick_resources_used[u] <- tick_resources_used[u] + quantity_needed;
					if(external_producers.keys contains u){ // if there is a known external producer for this product/good
						bool av <- external_producers[u].producer.produce([u::quantity_needed]); // ask the external producer to product the required quantity
						if not av{
							ok <- false;
						}
					}
				}
				loop e over: production_emissions_T{ // apply emissions
					float quantity_emitted <- production_output_emissions_T[c][e] * demand[c];
					tick_emissions[e] <- tick_emissions[e] + quantity_emitted;
				}
				tick_production[c] <- tick_production[c] + demand[c];
			}
			return ok;
		}
	}
	
	/**
	 * Species used to detail the consumption behavior of the population, related to the bloc.
	 * TODO: figure out what we should actually do here ?
	 */
	species transport_consumer parent:consumption_agent{
	
		map<string, float> consumed <- [];
		
		map<string, float> get_tick_consumption{
			return copy(consumed);
		}
		
		init{
			loop c over: production_outputs_T{
				consumed[c] <- 0;
			}
		}
		
		action reset_tick_counters{ // reset choices counters
			loop c over: consumed.keys{
				consumed[c] <- 0;
			}
		}
		
		action consume(human h){
		    loop c over: indivudual_consumption_T.keys{
		    	consumed[c] <- consumed[c]+indivudual_consumption_T[c];
		    }
	    }
	}
}

/**
 * We define here the experiment and the displays related to transport. 
 * We will then be able to run this experiment from the Main code of the simulation, with all the blocs connected.
 * 
 * Note : experiment car inherit another experiment, but we can't combine displays from multiple experiments at the same time. 
 * If needed, a new experiment combining all those displays should be added, for example in the Main code of the simulation.
 * TODO: modify it to display the data we actually want
 */
experiment run_transport type: gui {
	output {
		display Transport_information {
			chart "Population direct consumption" type: series  size: {0.5,0.5} position: {0, 0} {
			    loop c over: production_outputs_T{
			    	data c value: tick_pop_consumption_T[c]; // note : products consumed by other blocs NOT included here (only population direct consumption)
			    }
			}
			chart "Total production" type: series  size: {0.5,0.5} position: {0.5, 0} {
			    loop c over: production_outputs_T{
			    	data c value: tick_production_T[c];
			    }
			}
			chart "Resources usage" type: series size: {0.5,0.5} position: {0, 0.5} {
			    loop r over: production_inputs_T{
			    	data r value: tick_resources_used_T[r];
			    }
			}
			chart "Production emissions" type: series size: {0.5,0.5} position: {0.5, 0.5} {
			    loop e over: production_emissions_T{
			    	data e value: tick_emissions_T[e];
			    }
			}
	    }
	}
}
