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
	list<string> production_outputs_T <- [
		"km/person_scale_1",
		"km/person_scale_2",
		"km/person_scale_3",
		"km/kg_scale_1",
		"km/kg_scale_2",
		"km/kg_scale_3"
	];
	list<string> production_emissions_T <- ["gCO2e emissions"];
	
	/* DATA */
	list<string> vehicles <- ["truck", "train", "taxi", "minibus", "bicycle", "walk"];
	
	// TODO: not real values -> change to the real values
	// TODO: also maybe read them from a csv or something
	map<string, map<string, float>> vehicle_data <- [
		"truck"::[
			"quantity"::600000, // number of vehicles available in france
			"capacity"::13000, // in kg (on average, not always full)
			"consumption"::1, // in kWh per km
			"lifetime"::180, // in months
			"emissions"::2, // GES per km
			"distance_max_per_tick"::5000 // distance max traveled per month
		],
		"train"::[
			"quantity"::5000, // number of vehicles available in france
			"capacity"::300, // in persons (on average, not always full)
			"consumption"::15, // in kWh per km
			"lifetime"::480, // in months
			"emissions"::10, // GES per km
			"distance_max_per_tick"::10000 // distance max traveled per month
		],
		"taxi"::[
			"quantity"::63000, // number of vehicles available in france
			"capacity"::3, // in persons (on average, not always full, not counting driver if there is one)
			"consumption"::0.1, // in kWh per km
			"lifetime"::60, // in months
			"emissions"::1, // GES per km
			"distance_max_per_tick"::2000 // distance max traveled per month
		],
		"minibus"::[
			"quantity"::50000, // number of vehicles available in france
			"capacity"::10, // in persons (on average, not always full)
			"consumption"::1, // in kWh per km
			"lifetime"::120, // in months
			"emissions"::2, // GES per km
			"distance_max_per_tick"::1000 // distance max traveled per month
		],
		"bicycle"::[
			"quantity"::36000000, // number of vehicles available in france
			"capacity"::1, // in persons (on average, not always full)
			"consumption"::0.001, // in kWh per km (electric bike 0.01?)
			"lifetime"::180, // in months
			"emissions"::0, // GES per km
			"distance_max_per_tick"::100 // distance max traveled per month
		],
		"walk"::[
			"quantity"::500000000, // 500M seems like a good ceiling
			"capacity"::1, // in person ?
			"consumption"::0, // in kWh per km
			"lifetime"::1, // in months // no lifetime
			"emissions"::0, // GES per km
			"distance_max_per_tick"::20 // distance max traveled per month
		]
	];
	
	map<string, map<string, float>> modal_split <- [
		"km/person_scale_1" :: ["train"::0.95, "taxi"::0.05], // no taxi if we follow slides
		"km/kg_scale_1"     :: ["truck"::1.0],
		
		"km/person_scale_2" :: ["train"::0.90, "taxi"::0.10],
		"km/kg_scale_2"     :: ["truck"::1.0], 
		
		"km/person_scale_3" :: ["walk"::0.50, "taxi"::0.10, "bicycle"::0.30, "minibus"::0.10],
		"km/kg_scale_3"     :: ["truck"::1.0]
		// TODO values are kinda random, find good parameters, and maybe change by distance too
	];
	
	/* Consumption data *///TODO: remove, although useful for fake simulation without block connections
	map<string, float> indivudual_consumption_T <- [
	"km/person_scale_1"::500.0,
	"km/person_scale_2"::100.0,
	"km/person_scale_3"::20.0,
	"km/kg_scale_1"::5000.0,
	"km/kg_scale_2"::5000.0,
	"km/kg_scale_3"::1000.0
	]; // monthly consumption per individual of the population. Note : this is fake data.
	
	/* Counters & Stats *///TODO: change to the right metrics
	map<string, float> tick_production_T <- [];
	map<string, float> tick_pop_consumption_T <- [];
	map<string, float> tick_resources_used_T <- [];
	map<string, float> tick_emissions_T <- [];
	map<string, float> tick_vehicle_usage_T <- []; // usage of each vehicle this tick in km/kg or km/pers
	map<string, int> tick_vehicle_available_T <- [];
	map<string, float> tick_vehicle_available_left_T <- [];

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

	// true for method 1, false for method 2 (cf explanations for lifespan methods)
	bool vehicle_lifespan_method <- true;
	// method 1 for lifespan
	// ages (in ticks) for each vehicles
	map<string, list<int>> vehicles_age <- [];


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
			
			if vehicle_lifespan_method{
				// initializing the lifespan of vehicles in method 1 : uniform distribution of age
				if (v = "walk"){
					continue;
				}
				vehicles_age[v] <- [];
				int number_of_ticks <- int(vehicle_data[v]["lifetime"]);
				int number_of_vehicles_per_tick <- number_of_vehicles[v] div number_of_ticks;
				int remainder <- number_of_vehicles[v] mod number_of_ticks;
				list<int> first_half <- [];
				list<int> second_half <- [];
				loop times: remainder{
					add (number_of_vehicles_per_tick + 1) to: first_half ;
				}
				loop times: number_of_ticks - remainder{
					add (number_of_vehicles_per_tick) to: second_half ;
				}
				vehicles_age[v] <- first_half + second_half;
				
//					if (tick < remainder) {
//						vehicles_age[v][tick] <- number_of_vehicles_per_tick + 1;
//					}
//					else {
//						vehicles_age[v][tick] <- number_of_vehicles_per_tick;
//					}
				
			}
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
		do update_vehicle_numbers();
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
	    	tick_vehicle_usage_T <- producer.get_tick_vehicle_usage(); // collect vehicle usage
	    	tick_vehicle_available_T <- number_of_vehicles; // collect total number of vehicles
	    	tick_vehicle_available_left_T <- number_of_vehicles_available; // collect total number of vehicles left available
	    	
	    	
	    	ask transport_consumer{ // prepare new tick on consumer side
	    		do reset_tick_counters;
	    	}
	    	
	    	ask transport_producer{ // prepare new tick on producer side
	    		do reset_tick_counters;
	    	}
    	}
	}
	
	// reset the amount of vehicles available for this tick
	// updates the lifespan of vehicles
	// 2 structures proposed :
	// 1) storing for each vehicle a map with the number of vehicles from a given tick up to the lifespan
	// 2) removing a certain percentage of vehicles each tick
	action update_vehicle_numbers{
		// reset the amount of vehicles available for this tick to the total
		loop v over: vehicles{
			number_of_vehicles_available[v] <- number_of_vehicles[v];
		}
		
		if vehicle_lifespan_method {
			// Method 1 :
			loop v over:vehicles{
				if (v = "walk"){
					continue;
				}
				// get the number of vehicles removed this tick
				int vehicles_removed <- last(vehicles_age[v]);
				// reduce the total amount of vehicles known
				number_of_vehicles[v] <- number_of_vehicles[v] - vehicles_removed;
				// remove the oldest vehicles from the lifespan list
				remove from:vehicles_age[v] index:length(vehicles_age[v])-1;
				// add 0 new vehicles at tick 0 age
				add item:0 to: vehicles_age[v] at: 0;
			}
		}
		else {
			// Method 2 :
			loop v over:vehicles{
				if (v = "walk"){
					continue;
				}
				// get the number of vehicles removed this tick
				int vehicles_removed <- int(number_of_vehicles[v] * (1/vehicle_data[v]["lifetime"]));
				// reduce the total amount of vehicles known
				number_of_vehicles[v] <- number_of_vehicles[v] - vehicles_removed;
			}
		}
	}
	
	// creates new vehicles, for now no ressources used //TODO: in MICRO
	action create_new_vehicles(string type, int quantity){
		if not(type in vehicles){
			warn("(TRANSPORT) : attempted creation of unrecognized vehicle");
			return;
		}
		number_of_vehicles[type] <- number_of_vehicles[type] + quantity;
		number_of_vehicles_available[type] <- number_of_vehicles_available[type] + quantity; 
		// if using method 1 for lifespan, add it to the lifespan list
		if vehicle_lifespan_method {
			vehicles_age[type][0] <- vehicles_age[type][0] + quantity; 
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
		map<string, float> tick_vehicle_usage <- []; // vehicle usage this tick in km/kg or km/person
		
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
		
		/* Returns the  */
		map<string, float> get_tick_vehicle_usage{
			return tick_vehicle_usage;
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
			loop v over: vehicles{
				tick_vehicle_usage[v] <- 0.0;
			}
		}
		
		// produce ressources to answer a demand in transport 
		bool produce(map<string,float> demand){
			bool global_success <- true;
			
			// Temp variable to accumulate needs of this tick
			float total_energy_needed <- 0.0;
			
			loop service over: demand.keys{
				float quantity_asked <- demand[service]; // already in km*pers or km*kg
				
				tick_production[service] <- tick_production[service] + quantity_asked; // "we have produced this service"
				
				map<string, float> split <- modal_split[service]; // get vehicle mix for this service
				
				if (split != nil) {
					loop vehicle_name over: split.keys {
						float share <- split[vehicle_name];
						float sub_quantity <- quantity_asked * share;
						
						map<string, float> specs <- vehicle_data[vehicle_name];
						
						// (Total charge * Distance) / Avg Capacity = Cumulated vehicule distances
						float vehicle_km <- sub_quantity / specs["capacity"];
						tick_vehicle_usage[vehicle_name] <- tick_vehicle_usage[vehicle_name] + vehicle_km;
						number_of_vehicles_available[vehicle_name] <- number_of_vehicles_available[vehicle_name] - (vehicle_km / specs["distance_max_per_tick"]);
						if (number_of_vehicles_available[vehicle_name] < 0) {
							ask transport{
								do create_new_vehicles(vehicle_name, int(-number_of_vehicles_available[vehicle_name]) + 1);
							}
						}
						
						total_energy_needed <- total_energy_needed + (vehicle_km * specs["consumption"]);
						float emissions <- vehicle_km * specs["emissions"];
						tick_emissions["gCO2e emissions"] <- tick_emissions["gCO2e emissions"] + emissions;
					}
				}
			}
			tick_resources_used["kWh energy"] <- tick_resources_used["kWh energy"] + total_energy_needed;
			
			if (total_energy_needed > 0 and external_producers contains_key "kWh energy"){
				// Here we ask Energy for electricity. I don't know if this will be how we do it in the end.
				bool energy_ok <- external_producers["kWh energy"].producer.produce(["kWh energy"::total_energy_needed]);
				if (!energy_ok) {
					global_success <- false;
					// BAD not enough energy !! or smth
				}
			}
			
			return global_success;
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
			chart "Population direct consumption (Demand)" type: series size: {0.5,0.5} position: {-0.25, 0} {
			    loop c over: production_outputs_T {
			    	// show km per scale
			    	data c value: tick_pop_consumption_T[c]; 
			    }
			}
			
			chart "Total production (Service realized)" type: series size: {0.5,0.5} position: {0.25, 0} {
			    loop c over: production_outputs_T {
			    	data c value: tick_production_T[c];
			    }
			}
			
			chart "Resources usage (Energy)" type: series size: {0.5,0.5} position: {-0.25, 0.5} {
			    loop r over: production_inputs_T {
			    	// Affiche les kWh consommés
			    	data r value: tick_resources_used_T[r] color: #red;
			    }
			}
			
			chart "Production emissions (CO2)" type: series size: {0.5,0.5} position: {0.25, 0.5} {
			    loop e over: production_emissions_T {
			    	data e value: tick_emissions_T[e] color: #black;
			    }
			}
			chart "Vehicle Usage (Km)" type: series size: {0.5,0.5} position: {0.75, 0} {
			    loop v over: vehicles {
			    	data v value: tick_vehicle_usage_T[v];
			    }
			}
			chart "Vehicles total" type: series size: {0.5,0.5} position: {0.75, 0.5} y_log_scale:true {
			    loop v over: (vehicles) {
			    	data v value: tick_vehicle_available_T[v];
			    	string new_label <- v + "_left";
			    	data new_label value: tick_vehicle_available_left_T[v];
			    }
			}
	    }
	}
}
