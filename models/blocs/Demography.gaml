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
	int nb_init_individuals <- 1000; // pop size
	
	/* Counters & Stats */
	int nb_inds -> {length(individual)};
	float births <- 0; // counter, accumulate the total number of births
	float deaths <- 0; // counter, accumulate the total number of deaths

	/* Input data */
	float kg_meat <- 0.0;
	float kg_vegetables <- 0.0;
	float L_water <- 0.0;
	int available_housing <- 0;

	/* Variables for mortality by calorie intake */
	float calorie_intake <- 0.0;
	float p_death_cal <- 0.0;

	/* Variables for mortality by water intake */
	float L_water_intake <- 0.0;
	float p_death_water <- 0.0;

	/* Variables for mortality and natality by available housing */
	int housing_deficit <- 0;
	float p_death_housing <- 0.0;
	float p_birth_housing <- 0.0;
	
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
	bool enabled <- false; // true to activate the demography (births, deaths), else false.
	
	/* setup the resident agent : initialize the population */
	action setup{
		do init_population;
	}
	
	/* updates the population every tick */
	action tick(list<human> pop){
		do collect_last_tick_data;
		if(enabled){
			do update_births;
			do update_deaths;
			do increment_age;
		}
	}
	
	list<string> get_input_resources_labels{ 
		return ["kg_meat", "kg_vegetables", "L_water", "available_housing"];
	}
	
	list<string> get_output_resources_labels{
		return ["nb_individuals", "food_demand", "transport_demand", "housing_demand"];
	}
	
	production_agent get_producer{
		return nil; // no producer for demography component (function declared only to respect bloc API)
	}
	
	action collect_last_tick_data{ // update stats & measures
		int nb_men <- individual count(not dead(each) and each.gender = male_gender);
		int nb_woman <-  individual count(not dead(each)) - nb_men;
	}
	
	action population_activity(list<human> pop){
		 // no population activity for demography component (function declared only to respect bloc API)
	}
	
	action set_external_producer(string product, production_agent prod_agent){
		// no external producer for demography component (function declared only to respect bloc API)
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

	action send_production_water(map<string, float> p){
		L_water <- p["L_water"];
	}

	action send_production_housing(map<string, int> p){
		available_housing <- p["available_housing"];
	}
	

	/* get average calorie intake based on kg_meat + kg_vegetables inputs */
	action get_calorie_intake{
		int total_pop <- nb_inds;
		float meat_per_capita <- (kg_meat / total_pop);
		float veg_per_capita <- (kg_vegetables / total_pop);
		// 2500 kcal per kg of meat, 
		// 500 kcal per kg of vegetables
		calorie_intake <- (meat_per_capita * 2500) + (veg_per_capita * 500);
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
		L_water_intake <- L_water / nb_inds;
	}

	/* calculate mortality rate by average water intake */
	action mortality_by_water{
		float a <- 0.001;
		float b <- 3.0;
		float R <- 3.0;
		p_death_water <- a * (1 / (1 + exp(b*(L_water_intake-R))));
	}

	/* calculate housing deficit */
	action get_housing_deficit{
		housing_deficit <- nb_inds - available_housing;
		if(housing_deficit < 0){
			housing_deficit <- 0;
		}
	}

	/* calculate mortality rate by housing deficit */
	action mortality_by_housing{
		float a <- 0.000001;
		p_death_housing <- -a * housing_deficit;
	}

	/* calculate birth rate by housing deficit */
	action natality_by_housing{
		float a <- 0.00001;
		p_birth_housing <- -a * housing_deficit;
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
		p_birth <- p_birth + p_birth_housing;

		return p_birth * coeff_birth;
	}
	
	/* updates birth and death probabilities of the individual */
	action update_demog_probas{
		p_birth <- get_p_birth();
		p_death <- get_p_death();
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
			chart "Gender evolution" type: series size: {0.5,0.5} position: {0, 0} {
				data "number_of_man" value: individual count(not dead(each) and each.gender = male_gender) color: #red;
				data "number_of_woman" value: individual count(not dead(each) and each.gender = female_gender) color: #blue;
				data "total_individuals" value: individual count(not dead(each)) color: #black;
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
		}
	}
}




