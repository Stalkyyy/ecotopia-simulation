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
	float completion <- 1.0;
	bool verbose_shortage <- false;
	
	// CSV values from the simulations
	map<string, float> sim_csv_values_transport <- [
		
		// From FranceTransportSimulation: Scale 1 / 2
		"trains_required"::50960,
		"train_km_month_scale1"::53338799,
		"train_km_month_scale2"::7557975,
		
		// From CitySimulation: Scale 3
		"taxis_required"::53,
		"minibuses_required"::50,
		"bicycles_required"::3425
	];


	/* Setup */
	list<string> production_inputs_T <- ["kWh energy", "kg_cotton"];
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
	
	map<string, map<string, float>> vehicle_data <- [
		"truck"::[
			"quantity"::6500, // number of vehicles available in france
			"capacity"::12000, // on average, not always full (kg)
			"capacity_std"::500, // varies slightly between months, there can be more trucks on high demand seasons (christmas)
			"consumption"::1, // (kWh/km)
			"lifetime"::116, // based on average age on french roads (months
			"emissions"::1000, // GES (g per km)
			"creation_energy"::4596.0, // (kWh)
			"plastic_weight"::7700, // (kg)
			"distance_max_per_tick"::3508 // reasonable max distance traveled per month (km)
		],
		"train"::[
			"quantity"::sim_csv_values_transport["trains_required"],	// from simulation at scale 1/2
			"capacity"::258, // (people)
			"capacity_std"::30, // varies between months (vacations, ...)
			"consumption"::15.0,
			"lifetime"::324,
			"emissions"::7200,
			"creation_energy"::375000.0,
			"plastic_weight"::146200,
			"distance_max_per_tick"::80000
		],
		"taxi"::[
//			"quantity"::250000,
			"capacity"::2, // on average, not always full, not counting driver if there is one (people)
			"capacity_std"::0.1, // mostly similar between months, can slightly vary with weather/season
			"consumption"::0.1,
			"lifetime"::138,
			"emissions"::100,
			"creation_energy"::1532.0,
			"plastic_weight"::1600,
			"distance_max_per_tick"::8300
		],
		"minibus"::[
//			"quantity"::94000,
			"capacity"::6, // (people)
			"capacity_std"::0.5, // varies slightly between months
			"consumption"::0.33,
			"lifetime"::98,
			"emissions"::500,
			"creation_energy"::4596.0,
			"plastic_weight"::2000,
			"distance_max_per_tick"::5000
		],
		"bicycle"::[
//			"quantity"::31464000,
			"capacity"::1, // (people)
			"capacity_std"::0.05, // mostly similar between months (there can be multiple people riding)
			"consumption"::0.001,
			"lifetime"::84,
			"emissions"::23,
			"creation_energy"::6.7,
			"plastic_weight"::20,
			"distance_max_per_tick"::900
		],
		"walk"::[
//			"quantity"::500000000, // large ceiling
			"capacity"::1,
			"capacity_std"::0,
			"consumption"::0,
			"lifetime"::1,
			"emissions"::0,
			"creation_energy"::0.0,
			"plastic_weight":: 0,
			"distance_max_per_tick"::90
		]
	];
	
	map<string, map<string, float>> modal_split <- [
		"km/person_scale_1" :: ["train"::1.0],
		"km/kg_scale_1"     :: ["truck"::1.0],
		
		"km/person_scale_2" :: ["train"::0.95, "taxi"::0.04, "walk"::0.0],
		"km/kg_scale_2"     :: ["truck"::1.0], 
		
		"km/person_scale_3" :: ["walk"::0.20, "taxi"::0.05, "bicycle"::0.40, "minibus"::0.35],
		"km/kg_scale_3"     :: ["truck"::1.0]
	];
	
	/* Consumption data */
	map<string, float> individual_consumption_T <- [
		// used in Macro, in Micro we no longer use these consumptions automatically
//		"km/person_scale_1"::1636.0,
//		"km/person_scale_2"::1520.0
//		"km/person_scale_3"::47.2
		//"km/kg_scale_1"::0, none since it's the population consumption
		//"km/kg_scale_2"::0,
		//"km/kg_scale_3"::0
	]; // monthly consumption per individual of the population.
	
	/* Counters & Stats */
	map<string, float> tick_production_T <- [];
	map<string, float> tick_pop_consumption_T <- [];
	map<string, float> tick_resources_used_T <- [];
	map<string, float> tick_emissions_T <- [];
	map<string, float> tick_vehicle_usage_T <- []; // usage of each vehicle this tick in km/kg or km/pers
	map<string, int> tick_vehicle_available_T <- [];
	map<string, float> tick_vehicle_available_left_T <- [];
	map<string, float> tick_vehicles_created_T <- [];
	map<string, float> tick_unfufilled_ressources_T <- []; // track unfufilled demands/productions	

	init{ // a security added to avoid launching an experiment without the other blocs
		if (length(coordinator) = 0){
			error "Coordinator agent not found. Ensure you launched the experiment from the Main model";
			// If you see this error when trying to run an experiment, this means the coordinator agent does not exist.
			// Ensure you launched the experiment from the Main model (and not from the bloc model containing the experiment).
		}
	}
	
	float kWh_per_kg_plastic <- 19.4;
	int nb_humans_per_agent <- 19500;
	// float humans_per_agent <- 6700.0;
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
	map<string, int> number_of_vehicles_cities <- []; // separated from the main one because we recount the available stock from each city at each tick


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
	
	
	// track unfufilled demands/productions	
	map<string, float> tick_unfufilled_ressources <- [
		// transport ressources that were not produced, either because we didn't get enough energy, or because there were not enough vehicles
		"km/person_scale_1"::0.0,
		"km/person_scale_2"::0.0,
		"km/person_scale_3"::0.0,
		"km/kg_scale_1"::0.0,
		"km/kg_scale_2"::0.0,
		"km/kg_scale_3"::0.0,
		// ressources the bloc needed but didn't received
		"kWh energy"::0.0,
		"kg_cotton"::0.0,
		// vehicles the bloc was meant to create but could not due to energy/cotton not received
		"truck"::0.0,
		"train"::0.0,
		"taxi"::0.0,
		"minibus"::0.0,
		"bicycle"::0.0,
		"walk"::0.0
	];
	
	
	// sets up the values of variables
	// sets up the bloc by creating the producers and consumers of the bloc
	// (NB : these are not the other blocs but the production_agent and consumption_agent)
	action setup{
		loop v over:vehicles{
			number_of_vehicles[v] <- int(vehicle_data[v]["quantity"]);
			number_of_vehicles_cities[v] <- 0;
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

		do update_city_vehicles(cities);
		do city_population_activity(cities);
		
		do france_train_population_activity(pop);
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
//	    	tick_vehicle_available_T <- number_of_vehicles;                // total number of vehicles
	    	loop v over: ["bicycle", "taxi", "minibus"] {
	    		// cities vehicles are stored in each city, so we recount them all every tick to keep track
	    		tick_vehicle_available_T[v] <- number_of_vehicles[v] + number_of_vehicles_cities[v];
	    		number_of_vehicles_cities[v] <- 0;
	    	}
	    	tick_vehicle_available_T["truck"] <- number_of_vehicles["truck"];
	    	tick_vehicle_available_T["train"] <- number_of_vehicles["train"];
	    	tick_vehicle_available_left_T <- number_of_vehicles_available; // total number of vehicles left available
	    	tick_vehicles_created_T <- vehicles_created;                   // number of vehicles created this tick 
	    	tick_unfufilled_ressources_T <- tick_unfufilled_ressources;		// all ressources missing/unproduced
	    	
	    	
	    	float transport_completed <- 0.0;
	    	float transport_penury <- 0.0;
	    	loop r over: production_outputs_T{
	    		transport_completed <- transport_completed + tick_production_T[r];
	    		transport_penury <- transport_penury + tick_unfufilled_ressources_T[r];
	    	}
	    	completion <- transport_completed / (transport_completed+transport_penury);
	    	ask transport_producer {
		    	do send_transport_completion(completion);
	    	}
	    	
	    	loop ressource over: tick_unfufilled_ressources.keys{
	    		tick_unfufilled_ressources[ressource] <- 0.0;
	    	}
	    	
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
	
	int create_new_vehicles(string type, int quantity){
		bool success <- true;
		int new_quantity <- quantity;
		if not(type in vehicles){
			warn("(TRANSPORT) : attempted creation of unrecognized vehicle");
			return;
		}
		
//		float required_energy <- quantity * vehicle_data[type]["creation_energy"] + required_cotton * kWh_per_kg_plastic;
		float total_energy_per_vehicle <- (vehicle_data[type]["creation_energy"] + vehicle_data[type]["plastic_weight"] * kWh_per_kg_plastic);
		float required_energy <- quantity * total_energy_per_vehicle;
		float energy_received <- 0.0;
		// ask for energy
		ask transport_producer{
			
			map<string, unknown> infoEner <- external_producers["kWh energy"].producer.produce("transport", ["kWh energy"::required_energy]);
			if not bool(infoEner["ok"]) {
				if verbose_shortage {
					write("[TRANSPORT] Tried to create " + quantity + " " + type + ", asked Energy for " + required_energy + " energy (kWh), but got a \"False\" return");
				}
				// check how much energy we received and work with that
				energy_received <- float(infoEner["transmitted_kwh"]);
				float energy_penury <- required_energy - energy_received;
//				float energy_received_ratio <- max(min((energy_received/required_energy),1.0),0.0);
				new_quantity <- int(floor(energy_received / total_energy_per_vehicle));
				
				// penury :
				tick_unfufilled_ressources["kWh energy"] <- tick_unfufilled_ressources["kWh energy"] + energy_penury;
			} else {
				energy_received <- required_energy;
			}
			// ask for cotton
			float required_cotton <- new_quantity * vehicle_data[type]["plastic_weight"];
			float cotton_received <- 0.0;
			map<string, unknown> infoAgri <- external_producers["kg_cotton"].producer.produce("transport", ["kg_cotton"::required_cotton]);
			if not bool(infoAgri["ok"]) {
				if verbose_shortage {
					write("[TRANSPORT] Tried to create " + new_quantity + " " + type + ", asked Agriculture for " + required_cotton + " cotton (kg), but got a \"False\" return");
				}
				// check how much cotton we received and work with that
				cotton_received <- float(infoAgri["transmitted_cotton"]);
				float cotton_penury <- required_cotton - cotton_received;
				new_quantity <- int(floor(cotton_received / required_cotton));
				// penury :
				tick_unfufilled_ressources["kg_cotton"] <- tick_unfufilled_ressources["kg_cotton"] + cotton_penury;
//				success <- false;
			}
			if success {
				tick_resources_used["kWh energy"] <- tick_resources_used["kWh energy"] + (energy_received);
				tick_resources_used["kg_cotton"] <- producer.tick_resources_used["kg_cotton"] + required_cotton;
				// tracking vehicles created
				vehicles_created[type] <- vehicles_created[type] + new_quantity;
				// penury :
				tick_unfufilled_ressources[type] <- tick_unfufilled_ressources[type] + (quantity - new_quantity);
			} else {
				// penury :
				tick_unfufilled_ressources["kWh energy"] <- tick_unfufilled_ressources["kWh energy"] + energy_received;
				tick_unfufilled_ressources[type] <- tick_unfufilled_ressources[type] + quantity;
				return 0;
			}
		}

		number_of_vehicles[type] <- number_of_vehicles[type] + new_quantity;
		number_of_vehicles_available[type] <- number_of_vehicles_available[type] + new_quantity;
		vehicles_age[type][0] <- vehicles_age[type][0] + new_quantity;
		return new_quantity;
	}
	
	// calculates the consumption in transports for the population
	action population_activity(list<human> pop) {
    	// TODO: how exactly did this work again ? (ie why are there 2 ?)
    	ask pop{ // execute the consumption behavior of the population
    		ask myself.transport_consumer{
    			do consume(myself); // individuals consume transport goods
    		}
    	}
    	 
    	ask transport_consumer{ // produce the required quantities
    		ask transport_producer{
    			loop c over: myself.consumed.keys{
		    		map<string, unknown> info <- produce("transport", [c::myself.consumed[c]]); // send the demands to the producer
		    		// note : in this example, we do not take into account the 'ok' signal.
		    	}
		    }
    	}
    }
    
    
    
    
    
	// vvv CITY CODE vvv
    map<string, int> required_vehicles_per_tick_for_10k_citizens <-  [
		// number of vehicles required for 10k people cities
		"taxi"::sim_csv_values_transport["taxis_required"],		// value obtained from the Scale3 simulation
		"minibus"::sim_csv_values_transport["minibuses_required"],	// value obtained from the Scale3 simulation
		"bicycle"::sim_csv_values_transport["bicycles_required"]	// value obtained from the Scale3 simulation
	];
	
    
    map<string, int> get_required_vehicles_per_tick(int population) {
    	map<string, int> required_vehicles_this_tick <- [];
    	float ratio <- population / 10000;
    	required_vehicles_this_tick["taxi"] <- int(ceil(required_vehicles_per_tick_for_10k_citizens["taxi"] * ratio));
    	required_vehicles_this_tick["minibus"] <- int(ceil(required_vehicles_per_tick_for_10k_citizens["minibus"] * ratio));
    	required_vehicles_this_tick["bicycle"] <- int(ceil(required_vehicles_per_tick_for_10k_citizens["bicycle"] * ratio));
    	return required_vehicles_this_tick;
    }
    
    int create_new_vehicles_city(string type, int quantity){
		// similar to the old one, but for cities, so it only returns if it's success or not, it doesn't create them directly
		if not(type in vehicles){
			warn("(TRANSPORT) : attempted creation of unrecognized vehicle");
			return 0;
		}
		
		int new_quantity <- quantity;
		bool success <- true;
//		float required_energy <- quantity * vehicle_data[type]["creation_energy"] + required_cotton * kWh_per_kg_plastic;
		float total_energy_per_vehicle <- (vehicle_data[type]["creation_energy"] + vehicle_data[type]["plastic_weight"] * kWh_per_kg_plastic);
		float required_energy <- quantity * total_energy_per_vehicle;
		float energy_received <- 0.0;
		// ask for energy
		ask transport_producer{			
			map<string, unknown> infoEner <- external_producers["kWh energy"].producer.produce("transport", ["kWh energy"::required_energy]);
			if not bool(infoEner["ok"]) {
				if verbose_shortage {
					write("[TRANSPORT] Tried to create " + quantity + " " + type + ", asked Energy for " + required_energy + " energy (kWh), but got a \"False\" return");
				}
				energy_received <- float(infoEner["transmitted_kwh"]);
				float energy_penury <- required_energy - energy_received;
				new_quantity <- int(floor(energy_received / total_energy_per_vehicle));
				
				
				
				// penury :
				tick_unfufilled_ressources["kWh energy"] <- tick_unfufilled_ressources["kWh energy"] + energy_penury;
			} else {
				energy_received <- required_energy;
			}
			
			// ask for cotton
			float required_cotton <- new_quantity * vehicle_data[type]["plastic_weight"];
			float cotton_received <- 0.0;
			map<string, unknown> infoAgri <- external_producers["kg_cotton"].producer.produce("transport", ["kg_cotton"::required_cotton]);
			if not bool(infoAgri["ok"]) {
				if verbose_shortage {
					write("[TRANSPORT] Tried to create " + quantity + " " + type + ", asked Agriculture for " + required_cotton + " cotton (kg), but only received "+float(infoAgri["transmitted_cotton"])+", but got a \"False\" return");
				}
				// check how much cotton we received and work with that
				cotton_received <- float(infoAgri["transmitted_cotton"]);
				float cotton_penury <- required_cotton - cotton_received;
				new_quantity <- int(floor(cotton_received / required_cotton));
				// penury :
				tick_unfufilled_ressources["kg_cotton"] <- tick_unfufilled_ressources["kg_cotton"] + cotton_penury;
//				success <- false;
			}
			if success {
				tick_resources_used["kWh energy"] <- tick_resources_used["kWh energy"] + energy_received;
				tick_resources_used["kg_cotton"] <- producer.tick_resources_used["kg_cotton"] + required_cotton;
				// tracking vehicles created
				vehicles_created[type] <- vehicles_created[type] + new_quantity;
				// penury :
				tick_unfufilled_ressources[type] <- tick_unfufilled_ressources[type] + (quantity - new_quantity);
			} else {
				// penury :
				tick_unfufilled_ressources["kWh energy"] <- tick_unfufilled_ressources["kWh energy"] + energy_received;
				tick_unfufilled_ressources[type] <- tick_unfufilled_ressources[type] + quantity;
				return 0;
			}
		}
		
		return new_quantity;
	}
    
	action update_city_vehicles(list<mini_ville> cities) {
		list<string> city_vehicles <- ["taxi", "minibus", "bicycle"];
		loop c over: cities {
			// update the age of the city vehicles
    		loop v over:city_vehicles{
				// NOTE : removed the variation in aging at each tick because it would be super computationally heavy to loop through all lifetime ticks for every single city (went back to the original code where we just remove the last (oldest) entry and add a new entry with 0 vehicles (O(1)))
				// get the number of vehicles removed this tick
				int vehicles_removed <- last(c.vehicles_age[v]);
				// reduce the total amount of vehicles known
				c.number_of_vehicles[v] <- c.number_of_vehicles[v] - vehicles_removed;
				// remove the oldest vehicles from the lifespan list
				remove from:c.vehicles_age[v] index:length(c.vehicles_age[v])-1;
				// add 0 new vehicles at tick 0 age
				add item:0 to: c.vehicles_age[v] at: 0;
			}
			// check if there are enough vehicles for the amount of population of the city
			map<string, int> required_vehicles_this_tick <- get_required_vehicles_per_tick(c.population_count);
			loop v over:city_vehicles{
				int required_vehicles <- required_vehicles_this_tick[v] - c.number_of_vehicles[v];
				if required_vehicles > 0 {
					int number_of_vehicles_created <- create_new_vehicles_city(v, required_vehicles);

					// update the city's vehicles
					if number_of_vehicles_created > 0 {
						c.vehicles_age[v][0] <- c.vehicles_age[v][0] + number_of_vehicles_created;
						c.number_of_vehicles[v] <- c.number_of_vehicles[v] + number_of_vehicles_created;
					}
				}
			}
			// update the number of vehicles total in france tracker
			loop v over:city_vehicles{
				number_of_vehicles_cities[v] <- number_of_vehicles_cities[v] + c.number_of_vehicles[v];
			}
		}
	}
	
	action city_population_activity(list<mini_ville> cities) {
		// do the population demands for the tick (ideally should be in MiniVille but we would have to solve dependency issues)

		
	   	list<string> city_vehicles <- ["walk", "taxi", "minibus", "bicycle"];
		loop c over: cities {
			// create/use population transport ressources based on the number of people in the city and the use per tick of each vehicle per citizen
			int population <- c.population_count;
			map<string, int> required_vehicles_this_tick <- get_required_vehicles_per_tick(population);
			loop v over: city_vehicles {
				// for each vehicle type create the corresponding transport amount

				// check if the city has enough vehicles for the
				int required_vehicles <- required_vehicles_this_tick[v];
				if v = "walk" {
					// for walk accept it here directly, (division by 0 later otherwise)
					float km_per_tick_per_10k_person <- c.vehicle_data[v]["km_per_tick_per_10k_person"];
					float ratio <- population / 10000;
					float distance_travelled <- km_per_tick_per_10k_person * ratio;
					ask transport_producer{
						tick_production["km/person_scale_3"] <- tick_production["km/person_scale_3"] + distance_travelled;
						tick_vehicle_usage[v] <- tick_vehicle_usage[v] + distance_travelled;
					}
					continue;
				}
				if required_vehicles <= 0 {
					continue;
				}
				int vehicles_available <- c.number_of_vehicles[v];
				// vehicles_available_ratio is the ratio of vehicles available to required vehicles (bounded to [0,1])
				float vehicles_available_ratio <- max(min((vehicles_available/required_vehicles),1.0),0.0);
				
				map<string, float> specs <- vehicle_data[v];
				float km_per_tick_per_10k_person <- c.vehicle_data[v]["km_per_tick_per_10k_person"];
				float ratio <- population / 10000;
				float distance_travelled <- km_per_tick_per_10k_person * ratio;

				// distance_travelled_penury = how much SHOULD have been traveled but lost due to insufficient vehicles
				float distance_travelled_penury <- distance_travelled - (distance_travelled * vehicles_available_ratio);
				tick_unfufilled_ressources["km/person_scale_3"] <- tick_unfufilled_ressources["km/person_scale_3"] + distance_travelled_penury;
				distance_travelled <- distance_travelled * vehicles_available_ratio;	// distance travelled after we take into account missing vehicles

				float energy_needed <- (distance_travelled * specs["consumption"]);
				float energy_received <- 0.0;

				// ask for energy
				ask transport_producer{
					map<string, unknown> infoEner <- external_producers["kWh energy"].producer.produce("transport", ["kWh energy"::energy_needed]);
					if not bool(infoEner["ok"]) {
						if verbose_shortage {
							write("[TRANSPORT] Tried to ask Energy Bloc for " + energy_needed + " energy (kWh), but got a \"False\" return");
						}
						// check how much energy we received and work with that
						energy_received <- float(infoEner["transmitted_kwh"]);
						float energy_penury <- energy_needed - energy_received;
						float energy_received_ratio <- max(min((energy_received/energy_needed),1.0),0.0);
//						new_quantity <- sub_quantity * energy_received_ratio;
						distance_travelled_penury <- distance_travelled - (distance_travelled * energy_received_ratio);
						distance_travelled <- distance_travelled * energy_received_ratio;
						
						// penury :
						tick_unfufilled_ressources["kWh energy"] <- tick_unfufilled_ressources["kWh energy"] + energy_penury;
						// track missing transport ressources that needed to be created
						tick_unfufilled_ressources["km/person_scale_3"] <- tick_unfufilled_ressources["km/person_scale_3"] + distance_travelled_penury;
					} else {
						energy_received <- energy_needed;
					}
					if energy_received > 0 {
						// track production and usage
						tick_production["km/person_scale_3"] <- tick_production["km/person_scale_3"] + distance_travelled;
						tick_vehicle_usage[v] <- tick_vehicle_usage[v] + distance_travelled;
						
						tick_resources_used["kWh energy"] <- tick_resources_used["kWh energy"] + energy_received;
						// GES
						float emissions <- distance_travelled * specs["emissions"];
						producer.tick_emissions["gCO2e emissions"] <- producer.tick_emissions["gCO2e emissions"] + emissions;
						do send_ges_to_ecosystem("transport", emissions);
					}
				}
			}
		}
	}
    	
	// ^^^ CITY CODE ^^^

    int required_trains_per_tick_for_65m_citizens <- int(sim_csv_values_transport["trains_required"]);		// value from simulation at scale 1/2;
    //int required_trains_per_tick_for_65m_citizens <- 50960;		// value from simulation at scale 1/2;
    int train_km_per_tick_per_65m_person <- sim_csv_values_transport["train_km_month_scale1"]+sim_csv_values_transport["train_km_month_scale2"];		// value from simulation at scale 1/2

	action france_train_population_activity(list<human> pop) {
		// age/number of trains already updated by update_vehicle_numbers()
		string t <- "train";
		int population <- length(pop) * nb_humans_per_agent;
		float ratio_population_to_65m <- population / 68250000;
		// check if we need to create more trains for the current population :
		float trains_required_this_tick <- required_trains_per_tick_for_65m_citizens * ratio_population_to_65m;
		
		int additional_trains_needed <- int(ceil(trains_required_this_tick - number_of_vehicles_available[t]));
		int number_of_vehicles_created <- 0;
		if additional_trains_needed > 0 {
			// need to create more vehicles
			int number_of_trains_created <- create_new_vehicles_city(t, additional_trains_needed);	// create_new_vehicles_city works well with trains too
//			update the number of trains
			number_of_vehicles_available[t] <- number_of_vehicles_available[t] + number_of_trains_created;
			number_of_vehicles[t] <- number_of_vehicles[t] + number_of_trains_created;
			vehicles_age[t][0] <- vehicles_age[t][0] + number_of_trains_created;
		}
		// trains_available_ratio is the ratio of trains available to required vehicles (bounded to [0,1])
		float trains_available_ratio <- max(min((number_of_vehicles_available[t] / trains_required_this_tick),1.0),0.0);
		
		float km_per_tick_per_65m_person <- train_km_per_tick_per_65m_person;
		float distance_travelled_ideal <- km_per_tick_per_65m_person * ratio_population_to_65m;
		float distance_travelled <- distance_travelled_ideal * trains_available_ratio;	// distance travelled after we take into account missing vehicles
		// distance_travelled_penury = how much SHOULD have been traveled but lost due to insufficient vehicles
		float distance_travelled_penury <- distance_travelled_ideal - distance_travelled;
		tick_unfufilled_ressources["km/person_scale_1"] <- tick_unfufilled_ressources["km/person_scale_1"] + distance_travelled_penury;
		float trains_used_in_total <- trains_required_this_tick * trains_available_ratio;

		map<string, float> specs <- vehicle_data[t];
		float energy_needed <- (distance_travelled * specs["consumption"]);
		float energy_received <- 0.0;

		// ask for energy
		ask transport_producer{
			map<string, unknown> infoEner <- external_producers["kWh energy"].producer.produce("transport", ["kWh energy"::energy_needed]);
			if not bool(infoEner["ok"]) {
				if verbose_shortage {
					write("[TRANSPORT] Tried to ask Energy Bloc for " + energy_needed + " energy (kWh), but got a \"False\" return");
				}
				// check how much energy we received and work with that
				energy_received <- float(infoEner["transmitted_kwh"]);
				float energy_penury <- energy_needed - energy_received;
				float energy_received_ratio <- max(min((energy_received/energy_needed),1.0),0.0);
				distance_travelled_penury <- distance_travelled - (distance_travelled * energy_received_ratio);
				distance_travelled <- distance_travelled * energy_received_ratio;
				trains_used_in_total <- trains_used_in_total  * energy_received_ratio;
				
				// penury :
				tick_unfufilled_ressources["kWh energy"] <- tick_unfufilled_ressources["kWh energy"] + energy_penury;
				// track missing transport ressources that needed to be created
				tick_unfufilled_ressources["km/person_scale_1"] <- tick_unfufilled_ressources["km/person_scale_1"] + distance_travelled_penury;
			} else {
				energy_received <- energy_needed;
			}
			if energy_received > 0 {
				// track production and usage
				float trains_remaining <- number_of_vehicles_available[t] - trains_used_in_total;
				number_of_vehicles_available[t] <- max(trains_remaining , 1.0);	// left a minimum of 1 because it might completely crash the simulation if it goes at or below 0
				// track production and usage
				tick_production["km/person_scale_1"] <- tick_production["km/person_scale_1"] + distance_travelled;
				tick_vehicle_usage[t] <- tick_vehicle_usage[t] + distance_travelled;
				
				tick_resources_used["kWh energy"] <- tick_resources_used["kWh energy"] + energy_received;
				// GES
				float emissions <- distance_travelled * specs["emissions"];
				producer.tick_emissions["gCO2e emissions"] <- producer.tick_emissions["gCO2e emissions"] + emissions;
				do send_ges_to_ecosystem("transport", emissions);
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
		
		/* Defines an external producer for a resource (Energy / Agriculture Bloc) */
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
		map<string, unknown> produce(string bloc_name, map<string,float> demand){
			bool global_success <- true;
			float quantity_sent <- 0.0;
						
			loop service over: demand.keys{
				float quantity_asked <- demand[service]; // already in km*pers or km*kg
				
				map<string, float> split <- modal_split[service]; // get vehicle mix for this service
				
				if (split != nil) {
					loop v over: split.keys {
						float share <- split[v];
						float sub_quantity <- quantity_asked * share;
						
						map<string, float> specs <- vehicle_data[v];

						map<string, unknown> ressources_needed <- [];
						
						// (Total charge * Distance) / Avg Capacity = Cumulated vehicule distances
						float capacity <- max(1, gauss(specs["capacity"], specs["capacity_std"])); 
						float vehicle_km <- sub_quantity / capacity;
						
						float vehicles_needed <- (vehicle_km / specs["distance_max_per_tick"]);
						float vehicles_remaining <- number_of_vehicles_available[v] - vehicles_needed;
						if vehicles_needed = 0 {
							continue;
						}
						int number_of_vehicles_created <- 0;
						if (vehicles_remaining < 0) {
							ask transport{
								number_of_vehicles_created <- create_new_vehicles(v, int(-vehicles_remaining) + 1);
							}
						}
						if number_of_vehicles_created < -vehicles_remaining {
							// we don't have enough vehicles -> produce partially with what we have
							float ratio_available <- number_of_vehicles_available[v] / vehicles_needed;
							float og_needed <- sub_quantity;
							sub_quantity <- sub_quantity * ratio_available;
							vehicle_km <- vehicle_km * ratio_available;
							// track missing transport ressources that needed to be created
							tick_unfufilled_ressources[service] <- tick_unfufilled_ressources[service] + (og_needed - sub_quantity);
							global_success <- false;
						}
						
						
						// ask energy for the vehicles consumption
						float energy_needed <- (vehicle_km * specs["consumption"]);
						float energy_received <- 0.0;
						float new_quantity <- sub_quantity;
						map<string, unknown> infoEner <- external_producers["kWh energy"].producer.produce("transport", ["kWh energy"::energy_needed]);
						if not bool(infoEner["ok"]) {
							if verbose_shortage {
								write("[TRANSPORT] Asked Energy Bloc for " + energy_needed + " energy (kWh), but got a \"False\" return");
							}
							// check how much energy we received and work with that
							energy_received <- float(infoEner["transmitted_kwh"]);
							float energy_penury <- energy_needed - energy_received;
							float energy_received_ratio <- max(min((energy_received/energy_needed),1.0),0.0);
							new_quantity <- sub_quantity * energy_received_ratio;
							vehicle_km <- vehicle_km * energy_received_ratio;
							
							// penury :
							tick_unfufilled_ressources["kWh energy"] <- tick_unfufilled_ressources["kWh energy"] + energy_penury;
							// track missing transport ressources that needed to be created
							tick_unfufilled_ressources[service] <- tick_unfufilled_ressources[service] + (sub_quantity - new_quantity);
							global_success <- false;
						} else {
							energy_received <- energy_needed;
						}
						if energy_received > 0 {
							vehicles_needed <- (vehicle_km / specs["distance_max_per_tick"]);
							vehicles_remaining <- number_of_vehicles_available[v] - vehicles_needed;
							tick_resources_used["kWh energy"] <- tick_resources_used["kWh energy"] + energy_received;
							number_of_vehicles_available[v] <- max(vehicles_remaining, 1.0);	// left a minimum of 1 otherwise it will completely crash the simulation for some reason
							tick_vehicle_usage[v] <- tick_vehicle_usage[v] + vehicle_km;
							tick_production[service] <- tick_production[service] + new_quantity;
							float emissions <- vehicle_km * specs["emissions"];
							tick_emissions["gCO2e emissions"] <- tick_emissions["gCO2e emissions"] + emissions;
							do send_ges_to_ecosystem("transport", emissions);
							
							quantity_sent <- new_quantity;
						}
					}
				}
			}
			
			map<string, unknown> prod_info <- [
        		"ok"::global_success,
        		"transmitted_transport_km"::quantity_sent
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
		    	consumed[c] <- consumed[c] + individual_consumption_T[c] * nb_humans_per_agent;
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
		    	data "km/person_scale_1/2" value: tick_production_T["km/person_scale_1"]; 
		    	data "km/person_scale_3" value: tick_production_T["km/person_scale_3"]; 
			}
			chart "Production (km/kg)" type: series size: {0.5,0.5} position: {0, -0.25}  y_log_scale:true {
			    loop c over: ["km/kg_scale_2"] {
			    	data c value: tick_production_T[c];
			    }
			}
			chart "Transport ressources shortage" type: series size: {0.5, 0.5} position: {0.5, -0.25} y_log_scale:true {
			    loop v over: (production_outputs_T) {
			    	data v value: tick_unfufilled_ressources_T[v];
			    }
			}
			chart "Used ressources shortage" type: series size: {0.5, 0.5} position: {1, -0.25} y_log_scale:true {
			    loop v over: production_inputs_T {
			    	data v value: tick_unfufilled_ressources_T[v];
			    }
			}
//			chart "Taxis age remaining" type: series size: {0.5, 0.5} position: {0.5, -0.25}  y_log_scale:true {
//		        transport t_agent <- first(transport);
//		        if (t_agent != nil) {
//		            list<int> distrib <- t_agent.vehicles_age["taxi"];
//		            if (distrib != nil) { data "Taxis" value: reverse(distrib) style: bar color: #green; }
//		        }
//		    }
//		    chart "Minibuses and Trucks age remaining" type: series size: {0.5, 0.5} position: {1, -0.25}  y_log_scale:true {
//		        transport t_agent <- first(transport);
//		        if (t_agent != nil) {
//		        	list<int> m_distrib <- t_agent.vehicles_age["minibus"];
//		            list<int> t_distrib <- t_agent.vehicles_age["truck"];
//		            if (m_distrib != nil) { data "Minibuses" value: reverse(m_distrib) style: bar color: #yellow; }
//		            if (t_distrib != nil) { data "Trucks" value: reverse(t_distrib) style: bar color: #red; }
//		        }
//		    }
			
			
			// ROW 2
			chart "Energy and Cotton used" type: series size: {0.5,0.5} position: {-0.5, 0.25} y_log_scale: true {
			    loop r over: production_inputs_T {
			    	data r value: tick_resources_used_T[r];
			    }
			}
			chart "Production emissions (CO2)" type: series size: {0.5,0.5} position: {0, 0.25}  y_log_scale:true {
			    loop e over: production_emissions_T {
			    	data e value: tick_emissions_T[e] color: #black;
			    }
			}
			chart "Vehicles Shortage" type: series size: {0.5, 0.5} position: {0.5, 0.25} y_log_scale:true {
			    loop v over: (vehicles) {
			    	data v value: tick_unfufilled_ressources_T[v];
			    }
			}
			
		    chart "completion" type: series size: {0.5, 0.5} position: {1, 0.25}  y_log_scale:true {
		        transport t_agent <- first(transport);
		        data "completion" value: completion;
		    }

//			chart "Trains age remaining" type: series size: {0.5, 0.5} position: {0.5, 0.25}  y_log_scale:true {
//		        transport t_agent <- first(transport);
//		        if (t_agent != nil) {
//		            list<int> distrib <- t_agent.vehicles_age["train"];
//		            if (distrib != nil) { data "Trains" value: reverse(distrib) style: bar color: #blue; }
//		        }
//		    }
//		    chart "Bicycles age remaining" type: series size: {0.5, 0.5} position: {1, 0.25}  y_log_scale:true {
//		        transport t_agent <- first(transport);
//		        if (t_agent != nil) {
//		            
//		            list<int> distrib <- t_agent.vehicles_age["bicycle"];
//		            if (distrib != nil) { data "Bicycles" value: reverse(distrib) style: bar color: #pink; }
//		        }
//		    }
			
			
			// ROW 3
			chart "Total Vehicles" type: series size: {0.5,0.5} position: {-0.5, 0.75} y_log_scale:true {
			    loop v over: (vehicles) {
			    	if (v = "walk") {
			    		continue;
			    	}
			    	data v value: tick_vehicle_available_T[v];
			    }
			}
			chart "Vehicle Usage (Km)" type: series size: {0.5,0.5} position: {0, 0.75}  y_log_scale:true {
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
			    	if (v = "walk") or (v = "bicycle") or (v = "minibus") or (v = "taxi") {
			    		continue;
			    	}
			    	data v value: tick_vehicle_available_left_T[v];
			    }
			}
			
			// ROW 4
//			chart "Transport ressources Penury" type: series size: {0.5,0.5} position: {-0.5, 1.25} y_log_scale:true {
//			    loop v over: (production_outputs_T) {
//			    	data v value: tick_unfufilled_ressources_T[v];
//			    }
//			}
//			chart "Used ressources Penury" type: series size: {0.5,0.5} position: {0, 1.25} y_log_scale:true {
//			    loop v over: production_inputs_T {
//			    	data v value: tick_unfufilled_ressources_T[v];
//			    }
//			}
//			chart "Vehicles Penury" type: series size: {0.5,0.5} position: {0.5, 1.25} y_log_scale:true {
//			    loop v over: (vehicles) {
//			    	data v value: tick_unfufilled_ressources_T[v];
//			    }
//			}
	    }
	}
}
