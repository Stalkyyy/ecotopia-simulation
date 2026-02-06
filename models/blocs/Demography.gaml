/**
* Name: Demography bloc (MOSIMA)
* Authors: Ege Eken
*/

model Demography

import "../API/API.gaml"

/**
 * We define here the global variables of the bloc. Some are needed for the displays (charts, series...).
 */
global{
	/* Setup */ 
	float total_pop <- 68250000.0;
	float nb_humans_per_agent <- 19500.0;
	int nb_init_individuals <- int(total_pop / nb_humans_per_agent);
	
	int nb_ticks_per_year <- 12; // here, one tick is one month
	string female_gender <- "F";
	string male_gender <- "M";
	
	/* Input data (data for 2018, source : INSEE) */ 
	map<string, map<int, float>>  init_age_distrib <- load_gender_data("../includes/data/init_age_distribution.csv"); // load initial ages distribution among the population for each gender
	map<string, map<int, float>> death_proba <- load_gender_data("../includes/data/death_probas.csv"); // load the probabilities to die in a year for each gender (per individual)
	map<string, map<int, float>> birth_proba <- load_gender_data("../includes/data/birth_probas.csv");
	map<string, float> init_gender_distrib <- [ // initial gender distribution in the population
		male_gender ::0.4839825904115131, 
		female_gender ::0.516017409588487
	];  // ne need to use a csv file here, just two values

	/* Parameters */ 
	float coeff_birth <- 1.0; // a parameter that can be used to increase or decrease the birth probability
	float coeff_death <- 1.0; // a parameter that can be used to increase or decrease the death probability
	// int nb_init_individuals <- 10000; // pop size
	// int pop_per_ind <- 6700;
	// int total_pop <- nb_init_individuals * pop_per_ind;
	
	/* Counters & Stats */
	int nb_inds -> {length(individual)};
	float births <- 0; // counter, accumulate the total number of births
	float deaths <- 0; // counter, accumulate the total number of deaths
	float birth_rate <- 0.0; // births per tick
	float death_rate <- 0.0; // deaths per tick

	/* Input data */
	list<string> production_inputs <- ["kg_meat", "kg_vegetables", "L water", "total_housing_capacity"];
	map<string, float> last_consumed <- ["kg_meat"::0.0, "kg_vegetables"::0.0, "L water"::0.0, "total_housing_capacity"::0.0];
	
	float kg_meat <- 0.0;
	float kg_vegetables <- 0.0;
	float kg_meat_per_capita <- 0.0;
	float kg_veg_per_capita <- 0.0;

	float L_water <- 0.0;
	float L_water_per_capita <- 0.0;
	float total_housing_capacity <- 0.0;

	/* Variables for mortality by calorie intake */
	float calorie_intake <- 0.0;
	float coeff_death_cal <- 1.0; // 1.0 = normal, >1.0 = increased mortality, <1.0 = decreased mortality

	/* Variables for mortality by water intake */
	float L_water_intake <- 0.0;
	float coeff_death_water <- 1.0;

	/* Variables for mortality and natality by available housing */
	int housing_deficit <- 0;
	float coeff_death_housing <- 1.0;
	float coeff_birth_housing <- 1.0; // 1.0 = normal, >1.0 = increased natality, <1.0 = decreased natality
	
	/* Variables for Global Happiness and Stability */
	float global_happiness_index <- 0.5; // Starts neutral. Range 0.0 (misery) to 1.0 (euphoria)
	float coeff_birth_happiness <- 1.0; // Gradually increases if happiness is high
	
	/* Seasonal mortality coefficient (higher in winter, lower in summer, averages to 1.0) */
	// Pre-calculated for 12 months: 0=Jan, 1=Feb, ..., 11=Dec
	// Peak in winter (~1.08), lowest in summer (~0.92), using cosine wave
	// I pre-calculated these to avoid computing each turn, not that a simple sin would be too costly, but still.
	list<float> seasonal_death_coeffs <- [1.08, 1.069, 1.04, 1.0, 0.96, 0.931, 0.92, 0.931, 0.96, 1.0, 1.04, 1.069];
	float coeff_death_seasonal <- 1.0;
	
	// Minivilles selected directly for display in charts (avoids changing random pick each step)
	list<mini_ville> monitored_minivilles <- [];

	geometry shape <- square(2000#m);
	
	init{  
		write "[Demography] Global Init. Coordinator: " + length(coordinator) + " | MVs: " + length(mini_ville);

		// Robust Initialization Check (Standalone Mode):
		// If running without Main/Urbanism (e.g. run_demography experiment), we need to create dummy MiniVilles
		if (length(coordinator) = 0 and empty(mini_ville)){
			write "[Demography] No MiniVilles found (Standalone Mode). Initializing dependencies...";
			
			// FIX: Manually initialize MiniVille global variables just in case
			if (area_per_unit_default = 0.0) { area_per_unit_default <- 70.0; }
			if (total_area_per_ville = 0.0) { total_area_per_ville <- 2e6; }
			if (buildable_ratio = 0.0) { buildable_ratio <- 0.4; }
			if (initial_fill_ratio = 0.0) { initial_fill_ratio <- 0.2; }
			
			write "[Demography] Creating 550 dummy mini_villes per configuration...";
			create mini_ville number: 550 with: [location::{0,0,0}]; 
		}
		
		// 2. Create and setup the residents agent (Manager) if it doesn't exist
		if (empty(residents)) {
			write "[Demography] Creating residents agent...";
			create residents number: 1 {
				do setup;
			}
		}
	}
	
	// Reflex to drive the simulation when there is no coordinator (Main model) to call us
	reflex standalone_driver when: empty(coordinator) {
		// Recovery: Ensure MiniVilles exist (fix for missing initialization)
		if (empty(mini_ville)) {
			write "[Demography] RECOVERY: Creating 550 MiniVilles in reflex loop.";
			create mini_ville number: 550 with: [location::{0,0,0}]; 
		}
		
		ask residents {
			// Pass all individuals and global mini_villes to the tick function
			do tick(list(individual), list(mini_ville));
		}
	}
	
	/* Load gender data (distribution, probabilities) per age category from a csv file */
	map<string, map<int, float>> load_gender_data(string filename){
		file input_file <- csv_file(filename, ","); // load the csv file and separate the columns
        matrix data_matrix <- matrix(input_file); // put the data in a matrix
        map<int, float> male_data <- create_map(data_matrix column_at 0, data_matrix column_at 1); // create a map from male data
        map<int, float> female_data <- create_map(data_matrix column_at 0, data_matrix column_at 2); // same for female data
        map<string, map<int, float>> data <- [male_gender::male_data, female_gender::female_data]; // zip it in a all-in-one map
        return data; // return it
	}
	
}


/**
 * We define here the content of the demography (or "resident") bloc as a species.
 * We implement the methods of the API. Some are empty (do nothing) because this bloc do not have consumption nor production.
 * We also add methods specific to this bloc to handle the births and deaths in the population.
 */
species residents parent:bloc{
	string name <- "residents";
	bool enabled <- true; // true to activate the demography (births, deaths), else false.
	
	residents_producer producer <- nil;
	residents_consumer consumer <- nil;
		
	/* setup the resident agent : initialize the population */
	action setup{
		do init_population;
		create residents_producer number:1 returns:producers;
		create residents_consumer number:1 returns:consumers;
		producer <- first(producers);
		consumer <- first(consumers);
	}
	
	/* updates the population every tick */
	action tick(list<human> pop, list<mini_ville> cities){ // Updated signature
		do population_activity(pop);
		do collect_last_tick_data;
		//map<string, float> demand <- ["kg_meat"::10.0, "kg_vegetables"::10.0, "L water"::10.0, "total_housing_capacity"::10.0];
		//map<string, unknown> info <- producer.produce(demand);
		if(enabled){
			// Reset coefficients to default before recalculating (prevents first-tick spikes)
			coeff_death_cal <- 1.0;
			coeff_death_water <- 1.0;
			coeff_death_housing <- 1.0;
			coeff_birth_housing <- 1.0;
			
			// Update seasonal mortality coefficient based on current month (0=Jan, 11=Dec)
			int current_month <- int(cycle mod 12);
			coeff_death_seasonal <- seasonal_death_coeffs[current_month];
				
				// Refresh mortality coefficients from actual consumption BEFORE happiness
				do recompute_resource_coeffs;
			
			do update_happiness_trend;
			do update_births;
			do update_deaths;
			do increment_age;
			do update_population;
			
			// Dynamic adjustment of food demand based on mortality/intake
			do update_food_demand;
			do update_water_demand;
			do update_housing_demand; // Enabled housing demand update
			
			// Initialize monitored minivilles for display (pick 5 random ones once)
			if (empty(monitored_minivilles) and not empty(cities)) {
				monitored_minivilles <- (length(cities) >= 5) ? (5 among cities) : cities;
			}
			
			do update_miniville_populations(cities);
			do debug_miniville_populations(cities);
		}
		// write "tick" + last_consumed;
	}
	
	list<string> get_input_resources_labels{ 
		return production_inputs;
	}
	
	list<string> get_output_resources_labels{
		return [];
	}
	
	production_agent get_producer{
		return producer; // no producer for demography component (function declared only to respect bloc API)
	}
	
	action collect_last_tick_data{	
		int nb_men <- individual count(not dead(each) and each.gender = male_gender);
		int nb_woman <-  individual count(not dead(each)) - nb_men;          
		ask consumer{
			// collect consumption data from last tick
			map<string, float> cons <- get_tick_consumption();
			last_consumed <- cons;
			//write "[DEMOGRAPHY CONSUMER] consumption collected: " + cons;
		}

		ask residents_consumer{ // prepare next tick on consumer side
			do reset_tick_counters;
		}
		
		ask residents_producer{ // prepare next tick on producer side
			do reset_tick_counters;
		}
    }
    
    action population_activity(list<human> pop) {
	    // 1) Build the demand side (what the population wants this tick)
	    ask pop{ // execute the consumption behavior of the population
	        ask myself.residents_consumer{
	            do consume(myself); // build per-capita demand based on age
	        }
	    }

	    // 2) Aggregate demand and request suppliers
	    map<string, float> demand <- [];
	    ask residents_consumer { demand <- copy(demanded); }

	    ask residents_producer {
	        do produce("population", demand);
	    }

	    // 3) Record what was REALLY delivered (may be lower than demand)
	    map<string, float> delivered <- [];
	    ask residents_producer { delivered <- copy(last_delivery); }
	    ask residents_consumer { do set_actual_consumption(delivered); }
    }
	
	action set_external_producer(string product, bloc bloc_agent){
        ask producer {
            do set_supplier(product, bloc_agent);
        }
    }
    
    action update_miniville_populations(list<mini_ville> available_cities) {
    	// Reset counts for the passed cities
		ask available_cities {
			population_count <- 0.0;
		}
		
		// Map individuals to cities
		ask individual {
			// Fallback: Assign home if missing or if home is not in the current available list
			// Note: We check 'available_cities contains home' to ensure we only use valid cities provided by Urbanism
			if (home = nil or not(available_cities contains home)) {
				// Try to find a city with space
				list<mini_ville> candidates <- available_cities where (each.population_count < each.housing_capacity);
				if (!empty(candidates)) {
					home <- one_of(candidates);
				} else {
					// Fallback: Overcrowding (pick any city)
					if (!empty(available_cities)) { home <- one_of(available_cities); }
				}
			}

			if (home != nil) {
				home.population_count <- home.population_count + nb_humans_per_agent;
			}
		}
    }

	action debug_miniville_populations(list<mini_ville> cities) {
		if (cycle mod 12 = 0) { // once a year
			int total_mapped_pop <- 0; 
			ask cities {
				// Debug log every 100 mini_villes
				if (index mod 100 = 0) {
					total_mapped_pop <- total_mapped_pop + int(population_count);
					write "[Demography / MiniVille Debug] MiniVille " + index + " population: " + population_count + " / Cap: " + housing_capacity;
				}
			}
			write "[Demography Debug] Total Mapped Population: " + total_mapped_pop + " / " + (length(individual) * nb_humans_per_agent);
		}
	}
    
    action update_food_demand {
		float target_intake <- 2000.0;
		float current_intake <- max(1.0, calorie_intake); // Prevent division by zero

		// Weighted target by age structure
		int nb_kids <- individual count (each.age <= 18);
		int nb_adults <- individual count (each.age > 18 and each.age <= 60);
		int nb_elderly <- individual count (each.age > 60);
		int total_sample <- nb_kids + nb_adults + nb_elderly;
		float weighted_target <- 2200.0;
		if (total_sample > 0) {
			weighted_target <- ((nb_kids * 1400.0) + (nb_adults * 2200.0) + (nb_elderly * 1800.0)) / total_sample;
		}
		target_intake <- weighted_target;

		ask consumer {
			// Smooth proportional controller with recovery mechanism
			float ratio <- target_intake / current_intake;
			float factor <- ratio ^ 0.35;
			factor <- min(1.15, max(0.85, factor));

			// Ensure minimum demand to avoid starvation
			resources_to_consume["kg_meat"] <- max(4.0, resources_to_consume["kg_meat"] * factor);
			resources_to_consume["kg_vegetables"] <- max(8.0, resources_to_consume["kg_vegetables"] * factor);

			// Clamp to realistic monthly per-person bounds
			resources_to_consume["kg_meat"] <- min(25.0, resources_to_consume["kg_meat"]);
			resources_to_consume["kg_vegetables"] <- min(50.0, resources_to_consume["kg_vegetables"]);
		}
	}
	
	action update_water_demand {
		float target_water <- 55.0; // L/month/person (~1.8 L/day)
		float current_water <- max(1.0, last_consumed["L water"] / max(1, total_pop)); // Prevent division by zero

		ask consumer {
			float ratio <- target_water / current_water;
			float factor <- ratio ^ 0.35;
			factor <- min(1.12, max(0.9, factor));

			// Ensure minimum demand to avoid dehydration
			resources_to_consume["L water"] <- max(20.0, resources_to_consume["L water"] * factor);

			// Clamp tighter to avoid swings
			resources_to_consume["L water"] <- min(90.0, resources_to_consume["L water"]);
		}
	}
	
	action update_housing_demand {
		// Housing logic: 1 unit per person is the baseline target.
		// If deficit > 0, it means we have fewer houses than people.
		// Asking for > 1.0 "housing capacity" per person is a signal to build more.
		
		ask consumer {
			if (housing_deficit > 0) {
				// Shortage -> increase demand signal
				resources_to_consume["total_housing_capacity"] <- resources_to_consume["total_housing_capacity"] * 1.05;
			} else if (housing_deficit <= 0 and resources_to_consume["total_housing_capacity"] > 1.0) {
				// Surplus -> relax demand signal back towards 1.0
				resources_to_consume["total_housing_capacity"] <- resources_to_consume["total_housing_capacity"] * 0.98;
			}
			
			// Clamp: Never ask for less than 1.0 (everyone needs a home), max 2.0 (panic mode)
			resources_to_consume["total_housing_capacity"] <- max(1.0, min(2.0, resources_to_consume["total_housing_capacity"]));
		}
	}

	/* recompute mortality coefficients based on actual delivered resources */
	action recompute_resource_coeffs {
		do get_calorie_intake;
		do mortality_by_calories;
		do get_water_intake;
		do mortality_by_water;
		do get_housing_deficit;
		do mortality_by_housing;
	}
	
	/* initialize the population */
	action init_population{
		create individual number:nb_init_individuals{
			gender <- rnd_choice(init_gender_distrib); // override gender, pick a gender with respect to the real distribution
			age <- rnd_choice(init_age_distrib[gender]);  // pick an initial age with respect to the real distribution and gender
			do update_demog_probas;
		}
	}

   /* apply births */
	action update_births{ 
		int new_births <- 0;
		ask individual{
			if(ticks_before_birthday<=0){ // check only once a year for each individual
				if(gender = female_gender and flip(p_birth)){ // women can have children
					new_births <- new_births + 1;
				}
			}
		}
		int nb_f <- individual count(each.gender=female_gender and not(dead(each)));
		create individual number:new_births;
		births <- births + new_births;
		birth_rate <- new_births * nb_humans_per_agent; // births this tick (actual population)
	}

	/* 
	action send_production_agricultural(map<string, float> p){
		kg_meat <- p["kg_meat"];
		kg_vegetables <- p["kg_vegetables"];
	}
	*/
	

	/* get average calorie intake based on kg_meat + kg_vegetables inputs */
	action get_calorie_intake{
		//write "[DEMOGRAPHY] kg meat: " + kg_meat;
		//write "[DEMOGRAPHY] kg veggies: " + kg_vegetables;

		kg_meat_per_capita <- (last_consumed["kg_meat"] / max(1, total_pop));
		kg_veg_per_capita <- (last_consumed["kg_vegetables"] / max(1, total_pop));
		// 2500 kcal per kg of meat, 
		// 500 kcal per kg of vegetables
		// average per day
		calorie_intake <- ( (kg_meat_per_capita * 2500) + (kg_veg_per_capita * 500) ) / 30 ;
		//write "[DEMOGRAPHY]"+ "average daily calorie_intake of a single person in a " + (total_pop / 1000000) + " million pop=" + calorie_intake;
	}

	/* Get ideal calorie intake based on age (children need less than adults) */
	float get_ideal_calorie_for_age(int age) {
		// Based on WHO/FAO recommendations by age group
		if (age <= 1) { return 800.0; }      // Infants: ~800 kcal/day
		else if (age <= 3) { return 1300.0; } // Toddlers: ~1300 kcal/day
		else if (age <= 8) { return 1600.0; } // Young children: ~1600 kcal/day
		else if (age <= 13) { return 1800.0; } // Pre-teens: ~1800 kcal/day
		else if (age <= 18) { return 2200.0; } // Teens: ~2200 kcal/day
		else if (age <= 30) { return 2400.0; } // Young adults: ~2400 kcal/day
		else if (age <= 60) { return 2200.0; } // Adults: ~2200 kcal/day
		else if (age <= 75) { return 2000.0; } // Older adults: ~2000 kcal/day
		else { return 1800.0; }                // Elderly: ~1800 kcal/day
	}
	
	/* calculate mortality coefficient by average calorie intake */
	action mortality_by_calories{
		// MIN/MAX tuning parameters for sensitivity
		float min_coeff <- 0.95;
		float max_coeff <- 1.5; // Lower maximum to prevent rapid population collapse

		// First step protection: ignore mortality updates during initialization
		if (cycle <= 1) {
			coeff_death_cal <- 1.0;
			return;
		}

		// Use a reasonable population-weighted ideal intake based on typical age distribution
		// France has a median age around 42, so we use 2100 kcal/day as the average
		// This avoids the circular dependency of asking individuals during initialization
		float ideal_intake <- 2000.0;
		
		// Now compare actual intake to population-weighted ideal
		float deviation <- abs(calorie_intake - ideal_intake);
		
		if (calorie_intake < ideal_intake) {
			// Malnutrition increases mortality exponentially
			// At 1600 kcal: ~1.05x, at 1000 kcal: ~1.5x, at 500 kcal: ~2.5x, at 200 kcal: ~3.5x
			float severity <- (ideal_intake - calorie_intake) / ideal_intake;
			coeff_death_cal <- 1.0 + (severity * severity * 3.0);
		} else if (calorie_intake > ideal_intake) {
			// Excess calories (obesity) increases mortality moderately
			// Added safe zone: up to +10% (buffer) is fine
			if (calorie_intake <= ideal_intake * 1.1) {
				coeff_death_cal <- 0.98; // Perfect/Good
			} else {
				// At 2500 kcal: ~1.02x, at 3000 kcal: ~1.08x, at 4000 kcal: ~1.2x
				float excess <- (calorie_intake - (ideal_intake * 1.1)) / 2000.0;
				coeff_death_cal <- 1.0 + (excess * 0.3);
			}
		} else {
			// Perfect intake: slight bonus
			coeff_death_cal <- 0.98;
		}
		
		// Check cycle here too or rely on early return? (early return handles it)
		// Clamp with tuning parameters
		coeff_death_cal <- min(max_coeff, max(min_coeff, coeff_death_cal));
	}

	/* get average water intake based on L_water input */
	action get_water_intake{
		L_water_per_capita <- last_consumed["L water"] / max(1, total_pop);
		// average per day
		L_water_intake <- L_water_per_capita / 30; 
	}

	/* calculate mortality rate by average water intake */
	action mortality_by_water{
		// MIN/MAX tuning parameters for sensitivity
		float min_coeff <- 0.95;
		float max_coeff <- 2.0;

		// First step protection
		if (cycle <= 1) {
			coeff_death_water <- 1.0;
			return;
		}

		// Ideal water intake: 2-3 L/day
		// Adequate: 1.5-4 L/day -> coefficient ~1.0
		// Severe dehydration: <0.5 L/day -> coefficient up to 4.0
		
		float ideal_intake <- 2.5;
		float min_safe <- 1.5;
		
		if (L_water_intake < min_safe) {
			// Dehydration increases mortality exponentially
			// At 1.0 L: ~1.3x, at 0.5 L: ~2.0x, at 0.2 L: ~3.5x
			float severity <- (min_safe - L_water_intake) / min_safe;
			coeff_death_water <- 1.0 + (severity * severity * 4.0);
		} else if (L_water_intake >= ideal_intake - 0.5 and L_water_intake <= ideal_intake + 0.5) {
			// Ideal range: slight bonus
			coeff_death_water <- 0.98;
		} else {
			// Adequate but not ideal
			coeff_death_water <- 1.0;
		}
		
		// Clamp with tuning parameters
		coeff_death_water <- min(max_coeff, max(min_coeff, coeff_death_water));
	}

	/* calculate housing deficit */
	action get_housing_deficit{
		//write "[DEMOGRAPHY] total population: " + total_pop;
		//write "[DEMOGRAPHY] total housing capacity: " + last_consumed["total_housing_capacity"];
		housing_deficit <- total_pop - int(last_consumed["total_housing_capacity"]);
	}

	/* calculate mortality rate by housing deficit */
	action mortality_by_housing{
		// MIN/MAX tuning parameters
		float min_coeff <- 0.95;
		float max_coeff <- 1.5;

		// First step protection
		if (cycle <= 1) {
			coeff_death_housing <- 1.0;
			return;
		}

		// Housing deficit impacts mortality
		// No deficit (surplus): slight bonus ~0.97x
		// Small deficit (<10% population): ~1.1x
		// Moderate deficit (10-30% population): ~1.3-1.8x
		// Severe deficit (>30% population): up to 2.5x
		
		if (housing_deficit <= 0) {
			// Surplus or exact match: slight bonus
			// More surplus = slightly better (but diminishing returns)
			float surplus_ratio <- min(0.3, abs(housing_deficit) / max(1.0, total_pop));
			coeff_death_housing <- 1.0 - (surplus_ratio * 0.1);
		} else {
			// Deficit: exponentially increasing mortality
			float deficit_ratio <- housing_deficit / max(1.0, total_pop);
			// At 5% deficit: ~1.05x, at 10%: ~1.15x, at 20%: ~1.4x, at 50%: ~2.5x
			coeff_death_housing <- 1.0 + (deficit_ratio * 3.0);
		}
		
		// Clamp with tuning parameters
		coeff_death_housing <- min(max_coeff, max(min_coeff, coeff_death_housing));
	}

	/* calculate birth rate coefficient by housing deficit */
	action natality_by_housing{
		// MIN/MAX tuning parameters
		float min_coeff <- 0.4;
		// Increased maximum to allow significant population growth when conditions are good
		float max_coeff <- 1.5; 

		// First step protection
		if (cycle <= 1) {
			coeff_birth_housing <- 1.0;
			return;
		}

		// Housing availability impacts birth rates
		// Surplus housing: slight bonus 
		// Adequate housing: ~1.0x
		// Small deficit: ~0.9x
		// Large deficit: down to 0.5x
		
		if (housing_deficit <= 0) {
			// Surplus: people more likely to have children
			// Increased impact of surplus on birth rate
			float surplus_ratio <- min(0.3, abs(housing_deficit) / max(1.0, total_pop));
			coeff_birth_housing <- 1.0 + (surplus_ratio * 1.0); // Boost multiplier
		} else {
			// Deficit: people less likely to have children
			float deficit_ratio <- housing_deficit / max(1.0, total_pop);
			// At 10% deficit: ~0.85x, at 20%: ~0.7x, at 50%: ~0.5x
			coeff_birth_housing <- 1.0 - (deficit_ratio * 1.5);
		}
		
		// Clamp with tuning parameters
		coeff_birth_housing <- min(max_coeff, max(min_coeff, coeff_birth_housing));
	}
	
	/* updates global happiness based on resource satisfaction */
	action update_happiness_trend {
		// Calculate current stress based on mortality coefficients (deviation from 1.0)
		// Ideal state: coeffs are < 1.0 (bonus from good conditions)
		float food_stress <- max(0.0, coeff_death_cal - 1.05); // Tolerance up to 1.05 before stress
		float water_stress <- max(0.0, coeff_death_water - 1.05);
		float housing_stress <- max(0.0, coeff_death_housing - 1.05);
		float total_stress <- food_stress + water_stress + housing_stress;
		
		// Calculate satisfaction bonuses
		// Changed to <= 1.01 to include "neutral/met needs" state as positive contribution
		float food_bonus <- (coeff_death_cal <= 1.01) ? 1.0 : 0.0;
		float water_bonus <- (coeff_death_water <= 1.01) ? 1.0 : 0.0;
		float housing_bonus <- (housing_deficit <= 0) ? 1.0 : 0.0;
		float transport_completion <- producer.get_transport_completion();
		write "[Demography] Transport Completion: " + transport_completion;
		float transport_bonus <- (transport_completion >= 0.8) ? 0.5 : (transport_completion - 0.5); // Bonus if good, penalty if bad

		float total_bonus <- food_bonus + water_bonus + housing_bonus + max(0.0, transport_bonus);
		
		// Update global happiness index
		float target_happiness <- 0.5;
		if (total_stress > 0) {
			target_happiness <- max(0.0, 0.5 - (total_stress * 2.0));
			// Under stress: drop fast
			global_happiness_index <- (global_happiness_index * 0.6) + (target_happiness * 0.4);
		} else if (total_bonus > 0) {
			// If all bonuses met, target rises slowly
			target_happiness <- min(1.0, 0.5 + (total_bonus * 0.12));
			global_happiness_index <- (global_happiness_index * 0.98) + (target_happiness * 0.02);
		} else {
			// Neutral state, drift slowly to center
			global_happiness_index <- (global_happiness_index * 0.98) + (target_happiness * 0.02);
		}

		// Adjust birth rate based on happiness
		// If happy (>0.6), birth coefficient rises over time
		// If unhappy (<0.4), it drops
		if (global_happiness_index > 0.6) {
			coeff_birth_happiness <- coeff_birth_happiness + 0.002;
		} else if (global_happiness_index < 0.4) {
			coeff_birth_happiness <- coeff_birth_happiness - 0.005;
		} else {
			// drift back to 1.0 if neutral
			if (coeff_birth_happiness > 1.0) { coeff_birth_happiness <- coeff_birth_happiness - 0.001; }
			else if (coeff_birth_happiness < 1.0) { coeff_birth_happiness <- coeff_birth_happiness + 0.001; }
		}
		
		// Clamp birth coefficient
		coeff_birth_happiness <- max(0.5, min(1.8, coeff_birth_happiness));
	}

	/* apply deaths*/
	action update_deaths{
		int deaths_this_tick <- 0;
		ask individual{
			if(ticks_before_birthday<=0){ // check only once a year for each individual
				if(flip(p_death)){ // every individual has a chance to die every month, or die by reaching max_age
					deaths <- deaths + 1;
					deaths_this_tick <- deaths_this_tick + 1;
					do die;
				}
			}
		}
		death_rate <- deaths_this_tick * nb_humans_per_agent; // deaths this tick (actual population)
	}
	
	/* increments the age of the individual if the tick corresponds to its birthday, and updates birth and death probabilities */
	action increment_age{
		ask individual{
			if(ticks_before_birthday<=0){ // if the current tick is the individual birth date, increment the age
				age <- age +1;
				ticks_before_birthday <- nb_ticks_per_year;
				do update_demog_probas; // update the death and birth probabilities
			}
			else{
				ticks_before_birthday <- ticks_before_birthday -1;
			}
		}
	}
	
	action update_population{
		total_pop <- nb_inds * nb_humans_per_agent;
		//write "" + total_pop;
	}
	
	
	
		species residents_producer parent:production_agent {
		map<string, bloc> external_producers;
				
		map<string, float> tick_resources_used <- ["kg_meat"::0.0, "kg_vegetables"::0.0, "L water"::0.0, "total_housing_capacity"::0.0];
		map<string, float> tick_production <- [];
		map<string, float> tick_emissions <- [];
		map<string, float> last_delivery <- [];
		
		map<string, float> get_tick_inputs_used{		
			return tick_resources_used;
		}
		map<string, float> get_tick_outputs_produced{
			return tick_production;
		}
		map<string, float> get_tick_emissions{
			return tick_emissions;
		}

		action reset_tick_counters{
			loop r over: tick_resources_used.keys{
				tick_resources_used[r] <- 0.0;
			}
			last_delivery <- [];
		}

		init{
			do reset_tick_counters;
		}
		
		
		/**
		 * Orchestrate national energy production across all sources according to energy mix ratios
		 */
		map<string, unknown> produce(string bloc_name, map<string, float> demand){
			bool ok <- true;
			map<string, float> delivered <- [];

			loop r over: demand.keys{
				float qty <- demand[r];
				float received <- 0.0;
				bool resource_ok <- true;

				if(external_producers.keys contains r){
					if(r = "total_housing_capacity"){
						// Housing capacity is provided as an output metric; don't "order" it, just read it.
						map<string, float> outputs <- external_producers[r].producer.get_tick_outputs_produced();
						if("total_housing_capacity" in outputs.keys) {
							received <- outputs["total_housing_capacity"];
						} else {
							received <- 0.0;
							resource_ok <- false;
						}
					} else {
						map<string, unknown> info <- external_producers[r].producer.produce("population", [r::qty]);
						if ("ok" in info.keys and not bool(info["ok"])) {
							resource_ok <- false;
						}

						// Extract actually transmitted quantities when provided by the supplier
						if(r = "kg_meat" and "transmitted_meat" in info.keys){
							received <- float(info["transmitted_meat"]);
						} else if(r = "kg_vegetables" and "transmitted_vegetables" in info.keys){
							received <- float(info["transmitted_vegetables"]);
						} else if(r = "kg_cotton" and "transmitted_cotton" in info.keys){
							received <- float(info["transmitted_cotton"]);
						} else if(r = "L water" and "transmitted_water" in info.keys){
							received <- float(info["transmitted_water"]);
						} else if(r = "kWh energy" and "transmitted_kwh" in info.keys){
							received <- float(info["transmitted_kwh"]);
						} else if(r = "m² land" and "transmitted_land" in info.keys){
							received <- float(info["transmitted_land"]);
						} else {
							received <- qty;
						}
					}
				} else {
					resource_ok <- false;
					received <- 0.0;
				}

				if(not (tick_resources_used.keys contains r)){
					tick_resources_used[r] <- 0.0;
				}
				tick_resources_used[r] <- tick_resources_used[r] + received;
				delivered[r] <- received;

				if(not resource_ok){
					ok <- false;
				}
			}

			last_delivery <- copy(delivered);

			map<string, unknown> prod_info <- [
        		"ok"::ok,
        		"delivered"::delivered
        	];

			return prod_info;
		}
		
		action set_supplier(string product, bloc bloc_agent){
			external_producers[product] <- bloc_agent;
		}
	}

		species residents_consumer parent:consumption_agent{

        map<string, float> consumed <- [];
        map<string, float> demanded <- [];
		// Initial demand set to ~1500-1600 kcal/day to start (15kg meat + 25kg veg)
		// 15*2500 + 25*500 = 37500 + 12500 = 50000 / 30 = 1666 kcal/day
		map<string, float> resources_to_consume <- ["kg_meat"::10.0, "kg_vegetables"::15.0, "L water"::50.0, "total_housing_capacity"::1.0];
        
        map<string, float> get_tick_consumption{
            return copy(consumed);
        }
        
		init{
			loop c over: production_inputs{
				consumed[c] <- 0;
				demanded[c] <- 0;
			}
		}
        
		action reset_tick_counters{
			loop c over: consumed.keys{
				consumed[c] <- 0;
			}
			loop c over: demanded.keys{
				demanded[c] <- 0;
			}
		}
        
        /**
         * Calculate monthly energy consumption per individual
         * Consumption varies slightly
         */
		action consume(human h){
            // float monthly_kwh <- gauss(human_cfg["avg_kwh_per_person"], human_cfg["std_kwh_per_person"]);
            // float individual_kwh <- max(human_cfg["min_kwh_conso"], min(human_cfg["monthly_kwh"], human_cfg["max_kwh_conso"]));
			
			// Get individual needs modifier from demography bloc
			individual ind <- individual(h);
			float modifier <- 1.0;
			if (ind != nil) {
				ask residents { modifier <- get_needs_modifier(ind.age); }
			}

			// Apply modifier to base demand
			float individual_kg_meat <- resources_to_consume["kg_meat"] * modifier;
			float individual_kg_vegetables <- resources_to_consume["kg_vegetables"] * modifier;
            float individual_L <- resources_to_consume["L water"] * modifier;
			// Housing is typically 1 unit per person regardless of age (or per household, but simplifying)
			float individual_housing <- resources_to_consume["total_housing_capacity"];

	            // Add to aggregated demand (real population scale)
	            demanded["kg_meat"] <- demanded["kg_meat"] + individual_kg_meat * nb_humans_per_agent;
	            demanded["kg_vegetables"] <- demanded["kg_vegetables"] + individual_kg_vegetables * nb_humans_per_agent;
	            demanded["L water"] <- demanded["L water"] + individual_L * nb_humans_per_agent;
	            demanded["total_housing_capacity"] <- demanded["total_housing_capacity"] + individual_housing * nb_humans_per_agent;
        }

		action set_actual_consumption(map<string, float> delivered){
			// Record what was really received after supplier shortages
			loop r over: delivered.keys{
				consumed[r] <- delivered[r];
			}
		}
    }

	/* Get multiplier for resource needs based on age */
	float get_needs_modifier(int age) {
		// Infants (0-3): Low consumption
		if (age <= 3) { return 0.4; } 
		// Children (4-12): Moderate consumption
		else if (age <= 12) { return 0.7; }
		// Teenagers (13-18): High consumption (growth spurt)
		else if (age <= 18) { return 1.1; }
		// Adults (19-60): Standard
		else if (age <= 60) { return 1.0; }
		// Elderly (60+): Reduced consumption
		else { return 0.8; }
	}

}

/**
 * We define the agents used in the demography bloc. We here extends the 'human' species of the API to add some functionalities.
 * Be careful to define features that will only be called within the demography block, in order to respect the API.
 * 
 * The demography of our population will here be based on death and birth probabilities.
 * These probabilities will depend on somme attributes of the individuals (age, gender ...).
 * We propose some formulas for these probabilities, based on INSEE data. These are rough estimates.
 */
	species individual parent:human{
	float p_death <- 0.0;
	float p_birth <- 0.0;
	int ticks_before_birthday <- 0;
	int delay_next_child <- 0;
	int child <- 0;
	mini_ville home <- nil;
	
	int ticks_counter <- 0;
	
	init{
		gender <- one_of ([female_gender, male_gender]); // pick a gender randomly
	    ticks_before_birthday <- rnd(nb_ticks_per_year); // set a random birth date in the year (uniformly)
	    // set initial birth & death probabilities :
	    p_birth <- get_p_birth(); 
		p_death <- get_p_death();
	}
	
	/* returns the age category matching the age of the individual from a list */
	int get_age_category(list<int> ages_categories){
		int age_cat <- max(ages_categories where (each <= age)); // get the last age category with a lower bound inferior to the age
		return age_cat;
	}
	
	/* returns the probability for the individual to die this year */
	float get_p_death{ // compute monthly death probability of an individual
		int age_cat <- get_age_category(death_proba[gender].keys);
		p_death <- death_proba[gender][age_cat];

		ask residents {
			// add mortality by calorie intake
			do get_calorie_intake();
			do mortality_by_calories();
			
			// add mortality by water intake
			do get_water_intake;
			do mortality_by_water;
			
			// add mortality by housing deficit
			do get_housing_deficit;
			do mortality_by_housing;
		}
		// Apply multiplicative coefficients to preserve age-based death rates
		// Includes seasonal variation (higher in winter, lower in summer)
		p_death <- p_death * coeff_death_cal * coeff_death_water * coeff_death_housing * coeff_death_seasonal;

		return  p_death * coeff_death;
	}
	
	/* returns the probability for the individual to give birth this year */
	float get_p_birth{
		if(gender = male_gender){ // male don't give birth
			return 0.0;
		}
		int age_cat <- get_age_category(birth_proba[gender].keys);
		p_birth <-  birth_proba[gender][age_cat];

		// add natality by housing deficit
		ask residents {
			do get_housing_deficit;
			do natality_by_housing;
		}
		p_birth <- p_birth * coeff_birth_housing * coeff_birth_happiness;

		return p_birth * coeff_birth;
	}
	
	/* updates birth and death probabilities of the individual */
	action update_demog_probas{
		p_birth <- get_p_birth();
		p_death <- get_p_death();
		if (false and ticks_counter > 0) {
			write "";
			write "[DEMOGRAPHY] individual age: " + age;
			write "[DEMOGRAPHY] individual gender: " + gender;
			write "[DEMOGRAPHY] food intake update";
			write "calories per capita: " + calorie_intake;
			write "hunger mortality coefficient: " + coeff_death_cal;
			write "[DEMOGRAPHY] water intake update";
			write "liters of water per capita: " + L_water_intake;
			write "water mortality coefficient: " + coeff_death_water;
			write "[DEMOGRAPHY] housing update";
			write "housing deficit: " + housing_deficit;
			write "housing mortality coefficient: " + coeff_death_housing;
			write "housing natality coefficient: " + coeff_birth_housing;
			write "seasonal mortality coefficient: " + coeff_death_seasonal;
			write "p_birth: " + p_birth + "| p_death: " + p_death;
		}
		ticks_counter <- ticks_counter + 1;
	}
}

/**
 * We define here the experiment and the displays related to demography. 
 * We will then be able to run this experiment from the Main code of the simulation, with all the blocs connected.
 * 
 * Note : experiment car inherit another experiment, but we can't combine displays from multiple experiments at the same time. 
 * If needed, a new experiment combining all those displays should be added, for example in the Main code of the simulation.
 */
experiment run_demography type: gui {
	parameter "Initial number of individuals" var: nb_init_individuals min: 0 category: "Initialisation";
	parameter "Coefficient for birth probability" var: coeff_birth min: 0.0 max: 10.0 category: "Demography";
	parameter "Coefficient for death probability" var: coeff_death min: 0.0 max: 10.0 category: "Demography";
	parameter "Number of ticks per year" var: nb_ticks_per_year min:1 category: "Simulation";

	output {
		display Population_information {
			
			/*
			chart "Gender evolution" type: series size: {0.5,0.5} position: {0, 0} {
				data "number_of_man" value: pop_per_ind * (individual count(not dead(each) and each.gender = male_gender)) color: #red;
				data "number_of_woman" value: pop_per_ind * (individual count(not dead(each) and each.gender = female_gender)) color: #blue;
				data "total_population" value: total_pop color: #black;
			}
			chart "Age Pyramid" type: histogram background: #lightgray size: {0.5,0.5} position: {0, 0.5} {
				data "]0;15]" value: individual count (not dead(each) and each.age <= 15) color:#blue;
				data "]15;30]" value: individual count (not dead(each) and (each.age > 15) and (each.age <= 30)) color:#blue;
				data "]30;45]" value: individual count (not dead(each) and (each.age > 30) and (each.age <= 45)) color:#blue;
				data "]45;60]" value: individual count (not dead(each) and (each.age > 45) and (each.age <= 60)) color:#blue;
				data "]60;75]" value: individual count (not dead(each) and (each.age > 60) and (each.age <= 75)) color:#blue;
				data "]75;90]" value: individual count (not dead(each) and (each.age > 75) and (each.age <= 90)) color:#blue;
				data "]90;105]" value: individual count (not dead(each) and (each.age > 90) and (each.age <= 105)) color:#blue;
			}
			chart "Births and deaths" type: series size: {0.5,0.5} position: {0.5, 0} {
				data "number_of_births" value: births color: #green;
				data "number_of_deaths" value: deaths color: #black;
			}
			chart "Water consumption" type: series size: {0.5,0.5} position: {0.5, 0.5} {
				data "L water" value: last_consumed["L water"] color: #blue;
			}
			chart "Housing deficit" type: series size: {0.5,0.5} position: {0.5, 0.5} {
				data "housing_deficit" value: housing_deficit color: #red;
			}
			*/
            chart "Gender evolution" type: series size: {0.33,0.33} position: {0, 0} {
                data "number_of_man" value: nb_humans_per_agent * (individual count(not dead(each) and each.gender = male_gender)) color: #red;
                data "number_of_woman" value: nb_humans_per_agent * (individual count(not dead(each) and each.gender = female_gender)) color: #blue;
                data "total_population" value: total_pop color: #black;
            }
            chart "Age Pyramid" type: histogram background: #lightgray size: {0.33,0.33} position: {0, 0.33} {
                data "]0;15]" value: individual count (not dead(each) and each.age <= 15) color:#blue;
                data "]15;30]" value: individual count (not dead(each) and (each.age > 15) and (each.age <= 30)) color:#blue;
                data "]30;45]" value: individual count (not dead(each) and (each.age > 30) and (each.age <= 45)) color:#blue;
                data "]45;60]" value: individual count (not dead(each) and (each.age > 45) and (each.age <= 60)) color:#blue;
                data "]60;75]" value: individual count (not dead(each) and (each.age > 60) and (each.age <= 75)) color:#blue;
                data "]75;90]" value: individual count (not dead(each) and (each.age > 75) and (each.age <= 90)) color:#blue;
                data "]90;105]" value: individual count (not dead(each) and (each.age > 90) and (each.age <= 105)) color:#blue;
            }
chart "Births and deaths (cumulative)" type: series size: {0.33,0.33} position: {0, 0.66} {
				data "total_births" value: births color: #green;
				data "total_deaths" value: deaths color: #black;
			}
chart "Population Growth Rate" type: series size: {0.33,0.33} position: {0.66, 0.66} {
				// Show net growth rate percentage (0% = stable)
				data "Growth Rate %" value: (total_pop > 0) ? ((birth_rate - death_rate) / total_pop) * 100.0 : 0.0 color: #blue;
				data "Stable (0%)" value: 0.0 color: #black;
            }

            chart "Calorie mortality coefficient" type: series size: {0.33,0.33} position: {0.33, 0} {
                data "coeff_death_cal" value: coeff_death_cal color: #orange;
            }
            chart "Water mortality coefficient" type: series size: {0.33,0.33} position: {0.33, 0.33} {
                data "coeff_death_water" value: coeff_death_water color: #blue;
            }
			chart "Monthly Meat & Vegetables & Water per capita" type: series size: {0.33,0.33} position: {0.33, 0.66} {
				data "kg_meat_per_capita" value: kg_meat_per_capita color: #red;
				data "kg_veg_per_capita" value: kg_veg_per_capita color: #green;
				data "L_water_per_capita" value: L_water_per_capita color: #blue;
			}

			// Commenting this one because its just a sin graph technically
			/*chart "Seasonal mortality coefficient" type: series size: {0.33,0.33} position: {0.66, 0} {
				data "coeff_death_seasonal" value: coeff_death_seasonal color: #cyan;
			}*/
			
			chart "Global happiness index" type: series size: {0.33,0.33} position: {0.66, 0} {
				data "global_happiness_index" value: global_happiness_index color: #magenta;
			}
			
			chart "Housing coefficients" type: series size: {0.33,0.33} position: {0.66, 0.33} {
				data "coeff_death_housing" value: coeff_death_housing color: #red;
				data "coeff_birth_housing" value: coeff_birth_housing color: #purple;
				data "coeff_birth_happiness" value: coeff_birth_happiness color: #magenta;
			}
			
		}

		display MiniVille_Distribution_6 {
			chart "MiniVille Population Sample" type: histogram background: #white {
				data "MV A" value: (length(monitored_minivilles) > 0) ? monitored_minivilles[0].population_count : 0 color: #blue;
				data "MV B" value: (length(monitored_minivilles) > 1) ? monitored_minivilles[1].population_count : 0 color: #red;
				data "MV C" value: (length(monitored_minivilles) > 2) ? monitored_minivilles[2].population_count : 0 color: #green;
				data "MV D" value: (length(monitored_minivilles) > 3) ? monitored_minivilles[3].population_count : 0 color: #purple;
				data "MV E" value: (length(monitored_minivilles) > 4) ? monitored_minivilles[4].population_count : 0 color: #orange;
			}
		}
		
		/* 
		display MiniVille_Distribution type: java2D { 
			graphics "World_Background" {
				draw shape color: #white border: #red;
			}
			species mini_ville aspect: population_map;
		}*/
	}
}



