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
		"km/person_scale_1", // km/person is not used by other blocs for now, we use them internally (see individual_consumption_T)
		"km/person_scale_2",
		"km/person_scale_3",
		"km/kg_scale_1",
		"km/kg_scale_2",
		"km/kg_scale_3"
	];
	list<string> production_emissions_T <- ["gCO2e emissions"];
	
	/* DATA */
	list<string> vehicles <- ["truck", "train", "taxi", "minibus", "bicycle", "walk"];
	
	map<string, map<string, float>> vehicle_data <- [
		"truck"::[
			"quantity"::625000, // number of vehicles available in france
			"capacity"::12000, // on average, not always full (kg)
			"capacity_std"::500, // varies slightly between months, there can be more trucks on high demand seasons (christmas)
			"consumption"::1, // (kWh/km)
			"lifetime"::116, // based on average age on french roads (months
			"emissions"::1000, // GES (g per km)
			"distance_max_per_tick"::3508 // reasonable max distance traveled per month (km)
		],
		"train"::[
			"quantity"::13000,
			"capacity"::258, // (people)
			"capacity_std"::30, // varies between months (vacations, ...)
			"consumption"::15.0,
			"lifetime"::324,
			"emissions"::7200,
			"distance_max_per_tick"::80000
		],
		"taxi"::[
			"quantity"::250000,
			"capacity"::2, // on average, not always full, not counting driver if there is one (people)
			"capacity_std"::0.1, // mostly similar between months, can slightly vary with weather/season
			"consumption"::0.1,
			"lifetime"::138,
			"emissions"::100,
			"distance_max_per_tick"::8300
		],
		"minibus"::[
			"quantity"::94000,
			"capacity"::6, // (people)
			"capacity_std"::0.5, // varies slightly between months
			"consumption"::0.33,
			"lifetime"::98,
			"emissions"::500,
			"distance_max_per_tick"::5000
		],
		"bicycle"::[
			"quantity"::31464000,
			"capacity"::1, // (people)
			"capacity_std"::0.05, // mostly similar between months (there can be multiple people riding)
			"consumption"::0.001,
			"lifetime"::84,
			"emissions"::23,
			"distance_max_per_tick"::900
		],
		"walk"::[
			"quantity"::500000000, // large ceiling
			"capacity"::1,
			"capacity_std"::0,
			"consumption"::0,
			"lifetime"::1,
			"emissions"::0,
			"distance_max_per_tick"::90
		]
	];
	
	map<string, map<string, float>> modal_split <- [
		"km/person_scale_1" :: ["train"::1.0],
		"km/kg_scale_1"     :: ["truck"::1.0],
		
		"km/person_scale_2" :: ["train"::0.95, "taxi"::0.04, "walk"::0.01],
		"km/kg_scale_2"     :: ["truck"::1.0], 
		
		"km/person_scale_3" :: ["walk"::0.20, "taxi"::0.05, "bicycle"::0.40, "minibus"::0.35],
		"km/kg_scale_3"     :: ["truck"::1.0]
	];
	
	/* Consumption data */
	map<string, float> individual_consumption_T <- [
		"km/person_scale_1"::1636.0,
		"km/person_scale_2"::1520.0,
		"km/person_scale_3"::47.2
		//"km/kg_scale_1"::0, none since it's the population consumption
		//"km/kg_scale_2"::0,
		//"km/kg_scale_3"::0
	]; // monthly consumption per individual of the population.
	
	/* Energy required for vehicles creation in kWh */
	map<string, float> vehicle_creation_energy_cost <- [
		"walk"::0.0,
		"bicycle"::6.7,
		"taxi"::1532.0,
		"minibus"::4596.0,
		"truck"::4596.0,
		"train"::375000.0
	];
	
	/* Counters & Stats */
	map<string, float> tick_production_T <- [];
	map<string, float> tick_pop_consumption_T <- [];
	map<string, float> tick_resources_used_T <- [];
	map<string, float> tick_emissions_T <- [];
	map<string, float> tick_vehicle_usage_T <- []; // usage of each vehicle this tick in km/kg or km/pers
	map<string, int> tick_vehicle_available_T <- [];
	map<string, float> tick_vehicle_available_left_T <- [];
	map<string, float> tick_vehicles_created_T <- [];

	init{ // a security added to avoid launching an experiment without the other blocs
		if (length(coordinator) = 0){
			error "Coordinator agent not found. Ensure you launched the experiment from the Main model";
			// If you see this error when trying to run an experiment, this means the coordinator agent does not exist.
			// Ensure you launched the experiment from the Main model (and not from the bloc model containing the experiment).
		}
	}
	
	float humans_per_agent <- 6700.0;
}


/**
 * We define here the transport bloc as a species.
 * We implement the methods of the API.
 */
species transport parent:bloc{
	// DATA :
	
	// number of vehicules in france (all scales for now)
	// this number decreases when vehicles reach their end of lifetime, it increases when a new vehicle is created
	map<string, int> number_of_vehicles <- []; // initialized in setup()


	// CODE :

	// number of vehicles in france (all scales for now)
	// still available for the current tick, this number resets at the start of the tick,
	// if it becomes negative -> new vehicles must be created to answer the demand
	map<string, float> number_of_vehicles_available <- []; // initialized in setup()
	
	// number of vehicles created this tick
	map<string, float> vehicles_created <- []; // initialized in setup()

	// ages (in ticks) for each vehicles
	map<string, list<int>> vehicles_age <- [];


	// name of the bloc :
	string name <- "transport";
	
	// production_agent and consumption_agent handling all production/consumption by this bloc
	transport_producer producer <- nil;
	transport_consumer consumer <- nil;
	
	// sets up the values of variables
	// sets up the bloc by creating the producers and consumers of the bloc
	// (NB : these are not the other blocs but the production_agent and consumption_agent)
	action setup{
		loop v over:vehicles{
			number_of_vehicles[v] <- int(vehicle_data[v]["quantity"]);
			number_of_vehicles_available[v] <- vehicle_data[v]["quantity"];
			vehicles_created[v] <- 0;
			
			// initializing lifespan (uniform distribution of age)
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
				first_half <+ number_of_vehicles_per_tick + 1;
			}
			loop times: number_of_ticks - remainder{
				second_half <+ number_of_vehicles_per_tick;
			}
			vehicles_age[v] <- first_half + second_half;
		}

		list<transport_producer> producers <- [];
		list<transport_consumer> consumers <- [];
		create transport_producer number:1 returns:producers; // instanciate the transport production handler
		create transport_consumer number:1 returns: consumers; // instanciate the transport consumption handler
		producer <- first(producers);
		consumer <- first(consumers);
	}

	// every tick : we collect/reset the data to display from the producer and consumer
	// then we calculate the consumption in transports for the population (we do it in this bloc)
	action tick(list<human> pop, list<mini_ville> cities){
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
			tick_pop_consumption_T <- consumer.get_tick_consumption();     // consumption behaviors
	    	tick_resources_used_T <- producer.get_tick_inputs_used();      // resources used
	    	tick_production_T <- producer.get_tick_outputs_produced();     // production
	    	tick_emissions_T <- producer.get_tick_emissions();             // emissions
	    	tick_vehicle_usage_T <- producer.get_tick_vehicle_usage();     // vehicle usage
	    	tick_vehicle_available_T <- number_of_vehicles;                // total number of vehicles
	    	tick_vehicle_available_left_T <- number_of_vehicles_available; // total number of vehicles left available
	    	tick_vehicles_created_T <- vehicles_created;                   // number of vehicles created this tick 
	    	
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
	// For each vehicle we store a map with the number of vehicles from a given tick up to the lifespan
	action update_vehicle_numbers{
		// reset the amount of vehicles available for this tick to the total
		loop v over: vehicles{
			number_of_vehicles_available[v] <- number_of_vehicles[v];
		}
		
		loop v over:vehicles{
			if (v = "walk"){
				continue;
			}
			list<int> current_ages <- vehicles_age[v];
			int max_lifespan <- length(current_ages);
			
			list<int> next_ages <- []; 
			loop times: max_lifespan { next_ages <+ 0; }
			
			int vehicles_removed_this_tick <- 0;
			
			loop i from: 0 to: max_lifespan - 1 {
				int count <- current_ages[i];
				if (count > 0) {
					int n_age0 <- int(count * 0.3);
					int n_age2 <- int(count * 0.3);
					int n_age1 <- count - n_age0 - n_age2;
					
					next_ages[i] <- next_ages[i] + n_age0; // no age
					
					if (i+1 < max_lifespan) { // normal
						next_ages[i+1] <- next_ages[i+1] + n_age1;
					} else {
						vehicles_removed_this_tick <- vehicles_removed_this_tick + n_age1;
					}
					
					if (i+2 < max_lifespan) { // fast age
						next_ages[i+2] <- next_ages[i+2] + n_age2;
					} else {
						vehicles_removed_this_tick <- vehicles_removed_this_tick + n_age2;
					}
				}
			}
			loop i from: 0 to: length(vehicles_age[v]) - 1 {
			    vehicles_age[v][i] <- next_ages[i];
			}
			number_of_vehicles[v] <- number_of_vehicles[v] - vehicles_removed_this_tick;
		}
	}
	
	// creates new vehicles, for now no resources used, just energy
	//TODO: resources in MICRO
	action create_new_vehicles(string type, int quantity){
		//write("new " + type+" : "+quantity);
		if not(type in vehicles){
			warn("(TRANSPORT) : attempted creation of unrecognized vehicle");
			return;
		}
		
		// TODO in MICRO
		// For macro, we do not check if we have enough energy
		number_of_vehicles[type] <- number_of_vehicles[type] + quantity;
		number_of_vehicles_available[type] <- number_of_vehicles_available[type] + quantity;
		vehicles_age[type][0] <- vehicles_age[type][0] + quantity;
		
		// ask for energy
		ask transport_producer{
			float required_energy <- quantity * vehicle_creation_energy_cost[type];
			// bool energy_ok <- external_producers["kWh energy"].producer.produce(["kWh energy"::required_energy]);
			// if (!energy_ok) {
					// write("[TRANSPORT] Tried to create " + quantity + " " + type + " vehicles, asked Energy for " + required_energy + " energy (kWh), but we got a \"False\" return");
					// BAD not enough energy !! or smth
			// }
			
			map<string, unknown> info <- external_producers["kWh energy"].producer.produce(["kWh energy"::required_energy]);
			if not bool(info["ok"]) {
				write("[TRANSPORT] Tried to create " + quantity + " " + type + " vehicles, asked Energy for " + required_energy + " energy (kWh), but we got a \"False\" return");
				// BAD not enough energy !! or smth
			}
		}
		// TODO in MICRO
		// For macro, we suppose we have enough energy
		// tracking vehicles created
		vehicles_created[type] <- vehicles_created[type] + quantity;
	}
	
	// calculates the consumption in transports for the population
	action population_activity(list<human> pop) {
		
    	ask pop{ // execute the consumption behavior of the population
    		ask myself.transport_consumer{
    			do consume(myself); // individuals consume transport goods
    		}
    	}
    	 
    	ask transport_consumer{ // produce the required quantities
    		ask transport_producer{
    			loop c over: myself.consumed.keys{
		    		map<string, unknown> info <- produce([c::myself.consumed[c]]); // send the demands to the producer
		    		// note : in this example, we do not take into account the 'ok' signal.
		    	}
		    }
    	}
    }
	
	
	/**
	 * Agent qui s'occupe de toutes les production du bloc
	 * (I don't know if in the future there will be multiple of this agent for each scale,
	 *  or if those will be sub agents of this agent)
	 */
	species transport_producer parent:production_agent{
		map<string, bloc> external_producers;         // Energy Bloc 
		map<string, float> tick_resources_used <- []; // ressources used during this tick to make transport ressources (energy)
		map<string, float> tick_production <- [];     // transport ressources created during this tick
		map<string, float> tick_emissions <- [];      // emissions produced during this tick 
		map<string, float> tick_vehicle_usage <- [];  // vehicle usage this tick in km/kg or km/person
		
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
		
		/* Returns the usage of vehicles this tick */
		map<string, float> get_tick_vehicle_usage{
			return tick_vehicle_usage;
		}
		
		/* Defines an external producer for a resource (Energy Bloc) */
		action set_supplier(string product, bloc bloc_agent){
			external_producers[product] <- bloc_agent;
		}
		
		// reset the values for the new tick to come
		action reset_tick_counters{ // reset impact counters
			loop u over: production_inputs_T{
				tick_resources_used[u] <- 0.0;
			}
			loop p over: production_outputs_T{
				tick_production[p] <- 0.0;
			}
			loop e over: production_emissions_T{
				tick_emissions[e] <- 0.0;
			}
			loop v over: vehicles{
				tick_vehicle_usage[v] <- 0.0;
				vehicles_created[v] <- 0.0;
			}
		}
		
		// produce ressources to answer a demand in transport 
		map<string, unknown> produce(map<string,float> demand){
			bool global_success <- true;
			
			// Temp variable to accumulate needs of this tick
			float total_energy_needed <- 0.0;
			
			loop service over: demand.keys{
				float quantity_asked <- demand[service]; // already in km*pers or km*kg
				
				// TODO in MICRO
				// For macro, we suppose we can create the service
				tick_production[service] <- tick_production[service] + quantity_asked; // "we have produced this service"
				
				map<string, float> split <- modal_split[service]; // get vehicle mix for this service
				
				if (split != nil) {
					loop v over: split.keys {
						float share <- split[v];
						float sub_quantity <- quantity_asked * share;
						
						map<string, float> specs <- vehicle_data[v];
						
						// (Total charge * Distance) / Avg Capacity = Cumulated vehicule distances
						float capacity <- max(1, gauss(specs["capacity"], specs["capacity_std"])); 
						float vehicle_km <- sub_quantity / capacity;
						
						// TODO in MICRO
						// For macro, we suppose we can do this
						tick_vehicle_usage[v] <- tick_vehicle_usage[v] + vehicle_km;
						number_of_vehicles_available[v] <- number_of_vehicles_available[v] - (vehicle_km / specs["distance_max_per_tick"]);
						if (number_of_vehicles_available[v] < 0) {
							ask transport{
								do create_new_vehicles(v, int(-number_of_vehicles_available[v]) + 1);
							}
						}
						
						total_energy_needed <- total_energy_needed + (vehicle_km * specs["consumption"]);
						
						// TODO in MICRO
						// For macro, we suppose we can do this so we emit directly
						float emissions <- vehicle_km * specs["emissions"];
						tick_emissions["gCO2e emissions"] <- tick_emissions["gCO2e emissions"] + emissions;
						do send_ges_to_ecosystem(emissions);
					}
				}
			}
			
			// TODO in MICRO
			// For macro, we suppose we can use all the energy needed
			tick_resources_used["kWh energy"] <- tick_resources_used["kWh energy"] + total_energy_needed;
			
			if (total_energy_needed > 0 and external_producers contains_key "kWh energy"){
				// Here we ask Energy for electricity. I don't know if this will be how we do it in the end.
				// bool energy_ok <- external_producers["kWh energy"].producer.produce(["kWh energy"::total_energy_needed]);
				// if (!energy_ok) {
				// 	 global_success <- false;
					 // write("TRANSPORT : warning, we asked the Energy bloc for " + total_energy_needed + " energy (kWh), but we got a \"False\" return");
					 // BAD not enough energy !! or smth
				// }
				
				map<string, unknown> info <- external_producers["kWh energy"].producer.produce(["kWh energy"::total_energy_needed]);
				if not bool(info["ok"]) {
					global_success <- false;
				}
			}
			
			map<string, unknown> prod_info <- [
        		"ok"::global_success
        	];
			
			return prod_info;
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
		    loop c over: individual_consumption_T.keys{
		    	consumed[c] <- consumed[c] + individual_consumption_T[c] * humans_per_agent;
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
 */
experiment run_transport type: gui {
	int graph_every_X_ticks <- 1;
	output {
		display Transport_information refresh:every(graph_every_X_ticks #cycles){
			
			// ROW 1
			chart "Population direct consumption (km/person)" type: series size: {0.5,0.5} position: {-0.5, -0.25} y_log_scale: true {
			    loop c over: individual_consumption_T.keys {
			    	// show km per scale
			    	data c value: tick_pop_consumption_T[c]; 
			    }
			}
			chart "Production (km/kg)" type: series size: {0.5,0.5} position: {0, -0.25} {
			    loop c over: (production_outputs_T - individual_consumption_T.keys) {
			    	data c value: tick_production_T[c];
			    }
			}
			chart "Taxis age remaining" type: series size: {0.5, 0.5} position: {0.5, -0.25} {
		        transport t_agent <- first(transport);
		        if (t_agent != nil) {
		            list<int> distrib <- t_agent.vehicles_age["taxi"];
		            if (distrib != nil) { data "Taxis" value: reverse(distrib) style: bar color: #green; }
		        }
		    }
		    chart "Minibuses and Trucks age remaining" type: series size: {0.5, 0.5} position: {1, -0.25} {
		        transport t_agent <- first(transport);
		        if (t_agent != nil) {
		        	list<int> m_distrib <- t_agent.vehicles_age["minibus"];
		            list<int> t_distrib <- t_agent.vehicles_age["truck"];
		            if (m_distrib != nil) { data "Minibuses" value: reverse(m_distrib) style: bar color: #yellow; }
		            if (t_distrib != nil) { data "Trucks" value: reverse(t_distrib) style: bar color: #red; }
		        }
		    }
			
			
			// ROW 2
			chart "Energy Used (kWh)" type: series size: {0.5,0.5} position: {-0.5, 0.25} {
			    loop r over: production_inputs_T {
			    	data r value: tick_resources_used_T[r] color: #red;
			    }
			}
			chart "Production emissions (CO2)" type: series size: {0.5,0.5} position: {0, 0.25} {
			    loop e over: production_emissions_T {
			    	data e value: tick_emissions_T[e] color: #black;
			    }
			}
			chart "Trains age remaining" type: series size: {0.5, 0.5} position: {0.5, 0.25} {
		        transport t_agent <- first(transport);
		        if (t_agent != nil) {
		            list<int> distrib <- t_agent.vehicles_age["train"];
		            if (distrib != nil) { data "Trains" value: reverse(distrib) style: bar color: #blue; }
		        }
		    }
		    chart "Bicycles age remaining" type: series size: {0.5, 0.5} position: {1, 0.25} {
		        transport t_agent <- first(transport);
		        if (t_agent != nil) {
		            
		            list<int> distrib <- t_agent.vehicles_age["bicycle"];
		            if (distrib != nil) { data "Bicycles" value: reverse(distrib) style: bar color: #pink; }
		        }
		    }
			
			
			// ROW 3
			chart "Total Vehicles" type: series size: {0.5,0.5} position: {-0.5, 0.75} y_log_scale:true {
			    loop v over: (vehicles) {
			    	if (v = "walk") {
			    		continue;
			    	}
			    	data v value: tick_vehicle_available_T[v];
			    }
			}
			chart "Vehicle Usage (Km)" type: series size: {0.5,0.5} position: {0, 0.75} {
			    loop v over: vehicles {
			    	data v value: tick_vehicle_usage_T[v];
			    }
			}
			chart "Vehicles Created (this tick)" type: series size: {0.5,0.5} position: {0.5, 0.75} y_log_scale:true{
			    loop v over: (vehicles) {
			    	if (v = "walk") {
			    		continue;
			    	}
			    	data v value: tick_vehicles_created_T[v];
			    }
			}
			chart "Unused Vehicles (this tick)" type: series size: {0.5,0.5} position: {1, 0.75} y_log_scale:true {
			    loop v over: (vehicles) {
			    	if (v = "walk") {
			    		continue;
			    	}
			    	data v value: tick_vehicle_available_left_T[v];
			    }
			}
	    }
	}
}
