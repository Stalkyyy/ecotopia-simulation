/**
* Name: Demography bloc (MOSIMA)
* Authors: Maël Franceschetti, Cédric Herpson, Jean-Daniel Kant
* Mail: firstname.lastname@lip6.fr
*/

model Demography

import "../API/API.gaml"

/**
 * We define here the global variables of the bloc. Some are needed for the displays (charts, series...).
 */
global{
	/* Setup */ 
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
	int nb_init_individuals <- 10000; // pop size
	int pop_per_ind <- 6700;
	int total_pop <- nb_init_individuals * pop_per_ind;
	
	/* Counters & Stats */
	int nb_inds -> {length(individual)};
	float births <- 0; // counter, accumulate the total number of births
	float deaths <- 0; // counter, accumulate the total number of deaths

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
	float p_death_cal <- 0.0;

	/* Variables for mortality by water intake */
	float L_water_intake <- 0.0;
	float p_death_water <- 0.0;

	/* Variables for mortality and natality by available housing */
	int housing_deficit <- 0;
	float p_death_housing <- 0.0;
	float p_birth_coef_housing <- 0.0;
	
	init{  
		// a security added to avoid launching an experiment without the other blocs
		if (length(coordinator) = 0){
			error "Coordinator agent not found. Ensure you launched the experiment from the Main model";
			// If you see this error when trying to run an experiment, this means the coordinator agent does not exist.
			// Ensure you launched the experiment from the Main model (and not from the bloc model containing the experiment).
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
	action tick(list<human> pop){
		do population_activity(pop);
		do collect_last_tick_data;
		//map<string, float> demand <- ["kg_meat"::10.0, "kg_vegetables"::10.0, "L water"::10.0, "total_housing_capacity"::10.0];
		//bool ok <- producer.produce(demand);
		if(enabled){
			do update_births;
			do update_deaths;
			do increment_age;
			do update_population;
		}
		write "tick" + last_consumed;
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
        ask pop{ // execute the consumption behavior of the population
            ask myself.residents_consumer{
                do consume(myself); // individuals consume energy
            }
        }
         
        ask residents_consumer{ // produce the required quantities
            ask residents_producer{
                loop c over: myself.consumed.keys{
                    do produce([c::myself.consumed[c]]);
                }
            } 
        }
    }
	
	action set_external_producer(string product, bloc bloc_agent){
        ask producer {
            do set_supplier(product, bloc_agent);
        }
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
	}

	action send_production_agricultural(map<string, float> p){
		kg_meat <- p["kg_meat"];
		kg_vegetables <- p["kg_vegetables"];
	}
	

	/* get average calorie intake based on kg_meat + kg_vegetables inputs */
	action get_calorie_intake{
		//write "[DEMOGRAPHY] kg meat: " + kg_meat;
		//write "[DEMOGRAPHY] kg veggies: " + kg_vegetables;

		kg_meat_per_capita <- (last_consumed["kg_meat"] / total_pop);
		kg_veg_per_capita <- (last_consumed["kg_vegetables"] / total_pop);
		// 2500 kcal per kg of meat, 
		// 500 kcal per kg of vegetables
		// average per day
		calorie_intake <- ( (kg_meat_per_capita * 2500) + (kg_veg_per_capita * 500) ) / 30 ;
		//write "[DEMOGRAPHY]"+ "average daily calorie_intake of a single person in a " + (total_pop / 1000000) + " million pop=" + calorie_intake;
	}

	/* calculate mortality rate by average calorie intake */
	action mortality_by_calories{
		float a <- 0.0007;
		float b <- 0.004;
		float R <- 400.0;
		float u <- 0.00004;
		p_death_cal <- u + a * (1 / (1 + exp(b*(calorie_intake-R))));
	}

	/* get average water intake based on L_water input */
	action get_water_intake{
		L_water_per_capita <- last_consumed["L water"] / total_pop;
		// average per day
		L_water_intake <- L_water_per_capita / 30; 
	}

	/* calculate mortality rate by average water intake */
	action mortality_by_water{
		float a <- 0.015;
		float b <- 4.0;
		float R <- 0.3;
		p_death_water <- a * (1 / (1 + exp(b*(L_water_intake-R))));
	}

	/* calculate housing deficit */
	action get_housing_deficit{
		//write "[DEMOGRAPHY] total population: " + total_pop;
		//write "[DEMOGRAPHY] total housing capacity: " + last_consumed["total_housing_capacity"];
		housing_deficit <- total_pop - last_consumed["total_housing_capacity"];
	}

	/* calculate mortality rate by housing deficit */
	action mortality_by_housing{
		float a <- 0.000000000000001;
		p_death_housing <- a * housing_deficit;
	}

	/* calculate birth rate coefficient by housing deficit */
	action natality_by_housing{
		float a <- -10.0;
		float b <- 0.5;
		float c <- b/(2*a);
		float d <- 0.1;
		p_birth_coef_housing <- (-d/(b*(1+exp(a*(housing_deficit-0.3))))) - c;
		p_birth_coef_housing <- 1.0 + p_birth_coef_housing;
		
	}
	/* apply deaths*/
	action update_deaths{
		ask individual{
			if(ticks_before_birthday<=0){ // check only once a year for each individual
				if(flip(p_death)){ // every individual has a chance to die every month, or die by reaching max_age
					deaths <- deaths +1;
					do die;
				}
			}
		}
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
		total_pop <- nb_inds * pop_per_ind;
		//write "" + total_pop;
	}
	
	
	
	species residents_producer parent:production_agent {
		map<string, bloc> external_producers;
				
		map<string, float> tick_resources_used <- ["kg_meat"::0.0, "kg_vegetables"::0.0, "L water"::0.0, "total_housing_capacity"::0.0];
		map<string, float> tick_production <- [];
		map<string, float> tick_emissions <- [];
		
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
		}

		init{
			do reset_tick_counters;
		}
		
		
		/**
		 * Orchestrate national energy production across all sources according to energy mix ratios
		 */
		bool produce(map<string, float> demand){
			bool ok <- true;
			//write "[DEMOGRAPHY PRODUCER] demand received: " + demand;
			loop r over: demand.keys{
				float qty <- demand[r];
				if(external_producers.keys contains r){
					bool available <- external_producers[r].producer.produce([r::qty]);
					if(not available){
						ok <- false;
					}
				}
				if(not (tick_resources_used.keys contains r)){
					tick_resources_used[r] <- 0.0;
				}
				tick_resources_used[r] <- tick_resources_used[r] + qty;
				write "DEMAND " + r + " : " + demand[r] + "[" + ok + "]";  
			}
			return ok;
			
		}
		
		action set_supplier(string product, bloc bloc_agent){
			external_producers[product] <- bloc_agent;
		}
	}

	species residents_consumer parent:consumption_agent{
    
        map<string, float> consumed <- [];
		map<string, float> resources_to_consume <- ["kg_meat"::3.0, "kg_vegetables"::20.0, "L water"::50.0, "total_housing_capacity"::1.0];
        
        map<string, float> get_tick_consumption{
            return copy(consumed);
        }
        
        init{
            loop c over: production_inputs{
                consumed[c] <- 0;
            }
        }
        
        action reset_tick_counters{
            loop c over: consumed.keys{
				consumed[c] <- 0;
            }
        }
        
        /**
         * Calculate monthly energy consumption per individual
         * Consumption varies slightly
         */
        action consume(human h){
            // float monthly_kwh <- gauss(human_cfg["avg_kwh_per_person"], human_cfg["std_kwh_per_person"]);
            // float individual_kwh <- max(human_cfg["min_kwh_conso"], min(human_cfg["monthly_kwh"], human_cfg["max_kwh_conso"]));
			float individual_kg_meat <- resources_to_consume["kg_meat"];
			float individual_kg_vegetables <- resources_to_consume["kg_vegetables"];
            float individual_L <- resources_to_consume["L water"];
			float individual_housing <- resources_to_consume["total_housing_capacity"];

            // Add to total consumption
            consumed["kg_meat"] <- consumed["kg_meat"] + individual_kg_meat * pop_per_ind;
            consumed["kg_vegetables"] <- consumed["kg_vegetables"] + individual_kg_vegetables * pop_per_ind;
            consumed["L water"] <- consumed["L water"] + individual_L * pop_per_ind;
            consumed["total_housing_capacity"] <- consumed["total_housing_capacity"] + individual_housing * pop_per_ind;
        }
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
		p_death <- p_death + p_death_cal + p_death_water + p_death_housing;

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
		p_birth <- p_birth * p_birth_coef_housing;

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
			write "hunger excess mortality: " + p_death_cal;
			write "[DEMOGRAPHY] water intake update";
			write "liters of water per capita: " + L_water_intake;
			write "water excess mortality: " + p_death_water;
			write "[DEMOGRAPHY] housing update";
			write "housing deficit: " + housing_deficit;
			write "housing excess mortality: " + p_death_housing;
			write "housing excess natality coef: " + p_birth_coef_housing;
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
                data "number_of_man" value: pop_per_ind * (individual count(not dead(each) and each.gender = male_gender)) color: #red;
                data "number_of_woman" value: pop_per_ind * (individual count(not dead(each) and each.gender = female_gender)) color: #blue;
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
            chart "Births and deaths" type: series size: {0.33,0.33} position: {0, 0.66} {
                data "number_of_births" value: births color: #green;
                data "number_of_deaths" value: deaths color: #black;
            }

            chart "Calorie related excess mortality" type: series size: {0.33,0.33} position: {0.33, 0} {
                data "p_death_cal" value: p_death_cal color: #orange;
            }
            chart "Water related excess mortality" type: series size: {0.33,0.33} position: {0.33, 0.33} {
                data "p_death_water" value: p_death_water color: #blue;
            }
			chart "Daily Meat & Vegetables & Water per capita" type: series size: {0.33,0.33} position: {0.33, 0.66} {
				data "kg_meat_per_capita" value: kg_meat_per_capita color: #brown;
				data "kg_veg_per_capita" value: kg_veg_per_capita color: #green;
				data "L_water_per_capita" value: L_water_per_capita color: #cyan;
			}

            chart "Housing related excess mortality" type: series size: {0.33,0.33} position: {0.66, 0} {
                data "p_death_housing" value: p_death_housing color: #red;
            }
            chart "Housing related excess natality coefficient" type: series size: {0.33,0.33} position: {0.66, 0.33} {
                data "p_birth_coef_housing" value: p_birth_coef_housing color: #purple;
            }
            chart "Housing deficit" type: series size: {0.33,0.33} position: {0.66, 0.66} {
                data "housing_deficit" value: housing_deficit color: #purple;
            }

		}
	}
}




