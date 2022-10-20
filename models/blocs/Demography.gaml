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
	
	/* Parameters */ 
	map<string, float> death_coeff <- [female_gender:: 0.71, male_gender:: 1.29]; // coefficients that modulate the average probability of death
	float coeff_birth <- 0.2; // a parameter that can be used to increase or decrease the birth probability
	float coeff_death <- 0.9; // a parameter that can be used to increase or decrease the death probability
	int nb_init_individuals <- 50000; // pop size
	int min_age_init <- 1; // min age of individuals at the start of the simulation
	int max_age_init <- 90; // max age of individuals at the start of the simulation
	int max_age <- 105; // older people will systematically die
	int delay_between_child <- 12; // minimum delay (in ticks) between two births from the same individual
	int max_child <- 4; // maximum number of children (birth probability is 0 beyond)
	
	/* Counters & Stats */
	int nb_inds -> {length(individual)};
	float births <- 0; // counter, accumulate the total number of births
	float deaths <- 0; // counter, accumulate the total number of deaths
	float men_per_woman <- 1.0; // ratio of available man per woman (will be updated during the simulation)
	
	init{ // a security added to avoid launching an experiment without the other blocs
		if (length(coordinator) = 0){
			error "Coordinator agent not found. Ensure you launched the experiment from the Main model";
			// If you see this error when trying to run an experiment, this means the coordinator agent does not exist.
			// Ensure you launched the experiment from the Main model (and not from the bloc model containing the experiment).
		}
	}
}


/**
 * We define here the content of the demography bloc as a species.
 * We implement the methods of the API. Some are empty (do nothing) because this bloc do not have consumption nor production.
 * We also add methods specific to this bloc to handle the births and deaths in the population.
 */
species residents parent:bloc{
	string name <- "residents";
	
	action setup{
		do init_population;
	}
	
	action tick(list<human> pop){
		do collect_last_tick_data;
		do update_deaths;
		do update_births;
		do increment_age;
	}
	
	list<string> get_input_resources_labels{ 
		return [];
	}
	
	list<string> get_output_resources_labels{
		return [];
	}
	
	production_agent get_producer{
		return nil;
	}
	
	action collect_last_tick_data{ // update stats & measures
		int nb_men <- individual count(not dead(each) and each.gender = male_gender);
		int nb_woman <-  individual count(not dead(each)) - nb_men;
		men_per_woman <- nb_men/nb_woman;
	}
	
	action population_activity(list<human> pop){
		// do nothing
	}
	
	action set_external_producer(string product, production_agent prod_agent){
		// do nothing
	}
	
	action init_population{
		create individual number:nb_init_individuals{
			age <- rnd(min_age_init, max_age_init);
			do update_demog_probas;
		}
	}

	action update_births{
		int new_births <- 0;
		ask individual{
			if(gender = female_gender and delay_next_child = 0 and flip(p_birth) and age > 15){ // women of childbearing age can have children
				new_births <- new_births + 1;
				child <- child + 1;
				delay_next_child <- delay_between_child;
			}
		}
		int nb_f <- individual count(each.gender=female_gender and not(dead(each)));
		create individual number:new_births;
		births <- births + new_births;
	}
	
	action update_deaths{
		ask individual{
			if((age >= max_age) or flip(p_death)){ // every individual has a chance to die every month, or die by reaching max_age
				deaths <- deaths +1;
				do die;
			}
		}
	}
	
	action increment_age{
		ask individual{
			if(ticks_before_birthday<=0){ // if the month it's the individual birth month, increment the age
				age <- age +1;
				ticks_before_birthday <- nb_ticks_per_year;
				do update_demog_probas; // update the death and birth probabilities
			}
			else{
				ticks_before_birthday <- ticks_before_birthday -1;
			}
			delay_next_child <- max(0, delay_next_child -1);
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
	    gender <- one_of ([female_gender, male_gender]);
	    ticks_before_birthday <- rnd(nb_ticks_per_year); // set a random birth date in the year (uniformly)
	    // set initial birth & death probabilities :
	    p_birth <- get_p_birth(); 
		p_death <- get_p_death();
	}
	
	float get_p_death{ // compute monthly death probability of an individual
		float gender_coeff <-  death_coeff[gender];
		float scale_coeff <- (1/nb_ticks_per_year)*(1/1000); // time and proportion scale factors
		float age_coeff <- 1.0;
		// base formulas proposed :
		if(age < 15){
			age_coeff <- max(0.0001,((1/10000) * exp((15-(age+1)) *0.75) + 0.08));
		}
		else{
			age_coeff <- max(0.0001,(-0.3 + 0.12 * exp((age+1) *0.07)));
		}
		// Note : formulas are deliberately not detailed/explained here: you will have to propose your own demographic model.
		return gender_coeff * scale_coeff * age_coeff * coeff_death;
	}
	
	float get_p_birth{
		if(gender = male_gender or child >= max_child or age < 15 or age > 50){
			return 0.0;
		}
		float scale_coeff <- (1/nb_ticks_per_year)*(1/100); // time and proportion scale factors
		float age_coeff <- 1.0;
		float coeff_availability <- min(1.0, men_per_woman);
		
		// formulas proposed :
		if(age < 35){
			age_coeff <- max(0,(-0.5 + 1.5 * exp((50-(age+1)) * 0.14)));
		}
		else{
			age_coeff <- max(0,(-0.035 * (age+1)^2 + 3.0*(age+1) - 50));
		}
		// Note : formulas are deliberately not detailed/explained here: you will have to propose your own demographic model.
		return scale_coeff * age_coeff * coeff_birth * coeff_availability;
	}
	
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
	parameter "Minimum age at start" var: min_age_init min: 0 max: 200 category: "Initialisation";
	parameter "Maximum age at start" var: max_age_init min: 0 max: 200 category: "Initialisation";
	parameter "Maximum reachable age" var: max_age min: 0 max: 200 category: "Demography";
	parameter "Coefficient for birth probability" var: coeff_birth min: 0.0 max: 10.0 category: "Demography";
	parameter "Coefficient for death probability" var: coeff_death min: 0.0 max: 10.0 category: "Demography";
	parameter "Number of ticks per year" var: nb_ticks_per_year min:1 category: "Simulation";

	output {
		display Population_information {
			chart "Gender evolution" type: series size: {0.5,0.5} position: {0, 0} {
				data "number_of_man" value: individual count(not dead(each) and each.gender = male_gender) color: #red;
				data "number_of_woman" value: individual count(not dead(each) and each.gender = female_gender) color: #blue;
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




