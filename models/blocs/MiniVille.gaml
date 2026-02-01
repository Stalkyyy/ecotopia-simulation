/**
* Name: Mini-villes
* Shared core entity used by all blocs.
*/

model MiniVille

global{
	// Mini-ville initialization (v1: fixed number, no creation/destruction)
	int mini_ville_count <- 550;
	float total_area_per_ville <- 2e6; // m2 per mini-ville
	float buildable_ratio <- 0.4;
	float green_ratio <- 0.4;
	float infrastructure_ratio <- 0.2;
	float area_per_unit_default <- 70.0; // m2 per housing unit (avg footprint)
	float initial_fill_ratio <- 0.2; // share of buildable area already used at init

	// Housing capacity per unit (shared baseline)
	map<string, float> capacity_per_unit <- ["wood"::3.0, "modular"::2.5]; // persons per unit
}

/**
 * Mini-ville (v1): fixed set, aggregate land-use budgets and housing stock.
 * No explicit building agents in this version.
 */
species mini_ville {
	float buildable_area <- total_area_per_ville * buildable_ratio;
	float used_buildable_area <- 0.0;
	float area_per_unit <- area_per_unit_default;
	int wood_housing_units <- 0;
	int modular_housing_units <- 0;
	float housing_capacity <- 0.0;
	float remaining_buildable_area <- buildable_area;

	int population_count <- 10000;	// <<< Added by the TRANSPORT BLOC because we will need to know the population count.
	// message to POPULATION/URBANISM BLOC : I don't know how you will initialize and update this value so I just put a simple 10k population count by default (based on the cahier des charges value)
	
	// vvv TRANSPORT BLOC VEHICLES vvv
	// DATA :
	list<string> vehicles <- ["taxi", "minibus", "bicycle"];
	map<string, map<string, float>> vehicle_data <- [
		// initial quantity
		// lifetime for each vehicle
		// number of km used with this vehicle during a tick
		// TODO: find the correct starting quantities for 10k people cities
		"walk"::[
			"km_per_tick_per_person"::5	//TODO : obtained from the Scale3 simulation
		],
		"taxi"::[
			"quantity"::5,	// TODO : obtained from the Scale3 simulation
			"lifetime"::138,
			"km_per_tick_per_person"::3	//TODO : obtained from the Scale3 simulation
		],
		"minibus"::[
			"quantity"::5,	// TODO : obtained from the Scale3 simulation
			"lifetime"::98,
			"km_per_tick_per_person"::20	//TODO : obtained from the Scale3 simulation
		],
		"bicycle"::[
			"quantity"::5,	// TODO : obtained from the Scale3 simulation
			"lifetime"::84,
			"km_per_tick_per_person"::20	//TODO : obtained from the Scale3 simulation
		]
	];
	
	
	// number of vehicules in the city
	// this number decreases when vehicles reach their end of lifetime, it increases when a new vehicle is created
	map<string, int> number_of_vehicles <- []; // initialized in setup_vehicles()
	// ages (in ticks) for each vehicles
	map<string, list<int>> vehicles_age <- [];
	
	
	// function to setup the original amounts of vehicles of the mini_ville and their age
	action setup_vehicles {
		loop v over:vehicles{
			// initializing the number of each vehicle type in the mini_ville : TODO: values from vehicle_data will be based on a 10k citizens, so the number of vehicles will probably need to be the ratio (eg : 8k citizens city => quantity*0.8)
			number_of_vehicles[v] <- int(vehicle_data[v]["quantity"]);
			
			// initializing lifespan (uniform distribution of age)
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
	}
	
	// function to increment the age of vehicles (removes the oldest vehicles)
//	action update_vehicles {
//		loop v over:vehicles{
//			// NOTE : removed the variation in aging at each tick because it would be super computationally heavy to loop through all lifetime ticks for every single city (went back to the original code where we just remove the last (oldest) entry and add a new entry with 0 vehicles (O(1)))
//			// get the number of vehicles removed this tick
//			int vehicles_removed <- last(vehicles_age[v]);
//			// reduce the total amount of vehicles known
//			number_of_vehicles[v] <- number_of_vehicles[v] - vehicles_removed;
//			// remove the oldest vehicles from the lifespan list
//			remove from:vehicles_age[v] index:length(vehicles_age[v])-1;
//			// add 0 new vehicles at tick 0 age
//			add item:0 to: vehicles_age[v] at: 0;
//		}
//		// should now look for whether it should create new vehicles or not to answer the pic consumption of this tick (based on population_count)
//		// and therefore create a request to the transport Bloc to make vehicles for him
//		// not sure how to give access to this class to the transport bloc to make the request (without making a Circular dependency)
//		// So maybe we should move all theses from the reflex to the Transport, but that's the opposite of what I talked with the teacher last time...
//	}
	
	// function to request transport ressources from transport bloc
	action make_population_transport_demand {
		// should make a request to transport Bloc to create transport ressources for its population
		// not sure how to give access to this class to the transport bloc to make the request (without making a Circular dependency)
		// So maybe we should move all theses from the reflex to the Transport, but that's the opposite of what I talked with the teacher last time...
	}
	
	// ^^^ TRANSPORT BLOC VEHICLES ^^^

	init{
		// initialize with partial usage of buildable area
		used_buildable_area <- buildable_area * initial_fill_ratio;
		remaining_buildable_area <- max(0.0, buildable_area - used_buildable_area);
		
		int total_units <- int(floor(used_buildable_area / area_per_unit));
		wood_housing_units <- int(floor(total_units * 0.6));
		modular_housing_units <- total_units - wood_housing_units;
		
		housing_capacity <- (wood_housing_units * capacity_per_unit["wood"])
			+ (modular_housing_units * capacity_per_unit["modular"]);
		
		// debug log
		write "mini_ville " + string(index) + " buildable_area=" + string(buildable_area);
		
		do setup_vehicles;	// <<< TRANSPORT BLOC VEHICLES
	}
}
