/**
* Name: Agricultural bloc (MOSIMA)
* Authors: Maël Franceschetti, Cédric Herpson, Jean-Daniel Kant
* Mail: firstname.lastname@lip6.fr
*/

model Agricultural

import "../API/API.gaml"
import "../blocs/Demography.gaml"


/**
 * We define here the global variables and data of the bloc. Some are needed for the displays (charts, series...).
 */
global{
	
	/* Setup */
	list<string> production_outputs_A <- ["kg_meat", "kg_vegetables", "kg_cotton"];
	list<string> production_inputs_A <- ["L water", "kWh energy", "m² land", "km/kg_scale_2"];
	list<string> production_emissions_A <- ["gCO2e emissions"];
	
	/* Parameter for transport */
	float distance <- 50.0;
	
	/* Parameter to simulate production without pesticide */
	float without_pesticide_vegetables <- 74.0/41.0;
	float without_pesticide_cotton <- 84.0/38.0;
	
	/* Production data */
	map<string, map<string, float>> production_output_inputs_A <- [
		"kg_meat"::["L water"::8576.0, "kWh energy"::10.0, "m² land"::12.8, "km/kg_scale_2"::distance],
		"kg_vegetables"::["L water"::425.0*without_pesticide_vegetables, "kWh energy"::0.5*without_pesticide_vegetables, "m² land"::0.47*without_pesticide_vegetables, "km/kg_scale_2"::distance],
		"kg_cotton"::["L water"::10000.0*without_pesticide_cotton, "kWh energy"::0.2*without_pesticide_cotton, "m² land"::13.3*without_pesticide_cotton, "km/kg_scale_2"::distance]
	];
	map<string, map<string, float>> production_output_emissions_A <- [
		"kg_meat"::["gCO2e emissions"::12.6],
		"kg_vegetables"::["gCO2e emissions"::0.5],
		"kg_cotton"::["gCO2e emissions"::8]
	];
	
	/* Initialization of production areas */
	map<string, float> surface_production_A <- [
		"kg_meat"::0.0,
		"kg_vegetables"::0.0,
		"kg_cotton"::0.0
	];
	
	/* Overproduction factor for stock forecasting */
	float overproduction_factor <- 0.05;
	
	/* Percentage of stock utilization */
	float stock_use_rate <- 1.0;
	
	/* Initialization of the stock of agricultural production */
	map<string, list<map<string, float>>> stock <- [
		"kg_meat"::[],
		"kg_vegetables"::[],
		"kg_cotton"::[]
	];
	
	/* Lifespan of agricultural products (in number of ticks) */
	map<string, int> lifetime_productions <- [
		"kg_meat"::6,
		"kg_vegetables"::8,
		"kg_cotton"::12
	];
	
	/* Total stock per resource displayed on the experience graph */
	map<string, float> stock_display <- [];
	
	/* Number of humans coef */
	//int nb_humans <- 6700;
	
	/* Consumption data */
	//float vegetarian_proportion <- 0.022;
	//map<string, float> indivudual_consumption_A <- ["kg_meat"::7.1*(1-vegetarian_proportion), "kg_vegetables"::10.5*(1+vegetarian_proportion)];
	
	/* Counters & Stats */
	map<string, float> tick_production_A <- [];
	map<string, float> tick_pop_consumption_A <- [];
	map<string, float> tick_resources_used_A <- [];
	map<string, float> tick_emissions_A <- [];
	
	/* Parameters for hunting */
	float hunting_over_farm <- 0.6; // proportions of meat produced from hunting
	float hunted_per_month <- 38000000 / 12; // number of animals hunted per month in France
	float kg_per_animal <- 25.0;
    int hunted_animals <- 0;
    float hunted_animals_kg <- 0.0;
    
    
    /* Parameters for fertilizer */
    float kg_fertilizer_per_m2 <- 3.0;
    float fertilizer_yield_increase <- 0.3;  
    
    float manure_produced_per_kg_meat <- 20.0; // A REVOIR (calculs)
    //float loss_per_kg_vegetables <- 10.0; // A REVOIR (calculs) <- est ce réellement utile ? on prend les pertes dues au manque de pesticides non ?
    int time_transform_waste_to_fertilizer <- 4; // A REVOIR -> chercher la donnée
    float recycling_percentage <- 0.99;
    float vegetables_to_fertilizer_percentage <- 0.3;
    float manure_to_fertilizer_percentage <- 0.5;
    
    float production_emissions_fertilizer <- 1.2; // A REVOIR -> retrouver le lien
    
    map<float,int> time_to_fertilize <- [];
    float kg_fertilizer_available <- 0.0;
    float kg_rotten_stock <- 0.0;
    float food_waste_received <- 0.0;
    
    
    /* Parameters for seasons */
    map<string, int> production_seasons <- [
		"spring"::1.0,
		"summer"::0.8,
		"autumn"::0.9,
		"winter"::0.3
	];
    
    list<string> seasons <- ["spring", "summer", "autumn", "winter"];
    int current_season <- 0;
    int cpt_tick <- 0;
    
    
    /*map<string, float> seasonal_overproduction <- [
	    "spring"::0.30,
	    "summer"::0.10,
	    "autumn"::0.15,
	    "winter"::0.0
	];
	
	map<string, float> seasonal_stock_use <- [
	    "spring"::0.0,
	    "summer"::0.2,
	    "autumn"::0.1,
	    "winter"::0.8
	];*/
	
	
	//469 000 000 kg de viande
	//703 500 000 kg de légumes
	
	// * 8576.0 = 4 022 144 000 000 L d'eau pour la viande tot par mois
	// * 425 * 74/41 = 539 635 975 609,76 L d'eau pour les légumes tot par mois
	
	// le tout additionné -> 4 561 779 975 609,8 L pour la consommation de la population
	// soit 4,6 * 10^12 L
	
	// mais avec le pourcentage de production de 5% on a 4,6 * 10^12 * 1.05 = 4 830 000 000 000 L soit 4,8 * 10^12 L
	// mais qu'en est-il des demandes d'urbanisme ? et est-ce qu'on obtient les mêmes résultats que les demandes de population ? 
	// pour atteindre les 10^13 L que nous avions comme résultat en macro, il nous reste 5200000000000 L soit 5,2*10^12 L
	
	// urbanisme, une maison a besoin de 20 000 kg de coton, soit 20 000 * 10 000 * (84/38) = 442 105 263,2 soit 4,4*10^8 L
	// pour atteindre les 5,2*10^12 L nécessaires restants, il faudrait que urbanisme construise 5,2*10^12 * 0.95 = 4 940 000 000 000 soit 4,9*10^12 L restant
	// suite du calcul : 4,9*10^12 / 4,4*10^8 = 11 136,3636364 soit environ 11 136 nouvelles maisons par mois ???? 
	
	init{ // a security added to avoid launching an experiment without the other blocs
		if (length(coordinator) = 0){
			error "Coordinator agent not found. Ensure you launched the experiment from the Main model";
			// If you see this error when trying to run an experiment, this means the coordinator agent does not exist.
			// Ensure you launched the experiment from the Main model (and not from the bloc model containing the experiment).
		}
	}
}

/**
 * We define here the agricultural bloc as a species.
 * We implement the methods of the API.
 * We also add methods specific to this bloc to consumption behavior of the population.
 */
species agricultural parent:bloc{
	string name <- "agricultural";
		
	agri_producer producer <- nil;
	agri_consumer consumer <- nil;
	
	action setup{
		list<agri_producer> producers <- [];
		list<agri_consumer> consumers <- [];
		create agri_producer number:1 returns:producers; // instanciate the agricultural production handler
		create agri_consumer number:1 returns: consumers; // instanciate the agricultural consumption handler
		producer <- first(producers);
		consumer <- first(consumers);
	}
	
	action tick(list<human> pop) {
		do collect_last_tick_data();
		//do population_activity(pop);
		
		cpt_tick <- cpt_tick + 1;
		if(cpt_tick mod 3 = 0){
			current_season <- (current_season + 1) mod 4;
		}
		do production_fertilizer;
	}
	
	action set_external_producer(string product, bloc bloc_agent){
		ask producer{
			do set_supplier(product, bloc_agent);
		}
	}
	
	production_agent get_producer{
		return producer;
	}

	list<string> get_output_resources_labels{
		return production_outputs_A;
	}
	
	list<string> get_input_resources_labels{
		return production_inputs_A;
	}
	
	list<string> get_emissions_labels{
		return production_emissions_A;
	}
	
	
	action receive_waste_food(float waste) {
		food_waste_received <- waste;
	}
	
	action collect_last_tick_data{
		if(cycle > 0){ // skip it the first tick
			tick_pop_consumption_A <- consumer.get_tick_consumption(); // collect consumption behaviors
	    	tick_resources_used_A <- producer.get_tick_inputs_used(); // collect resources used
	    	tick_production_A <- producer.get_tick_outputs_produced(); // collect production
	    	tick_emissions_A <- producer.get_tick_emissions(); // collect emissions
	    	
	    	// aging of stock
	    	loop p over: production_outputs_A{
	    		if not empty(stock[p]){
	    			list<map<string, float>> aged_stock <- [];
	    			loop lot over: stock[p]{
	    				lot["nb_ticks"] <- lot["nb_ticks"] + 1.0;
	    				
	    				if lot["nb_ticks"] <= lifetime_productions[p]{
							aged_stock << lot;
						} else {
							kg_rotten_stock <- kg_rotten_stock + lot["quantity"];
							//write "Péremption " + p + " : quantité = " + lot["quantity"] + ", âge = " + lot["nb_ticks"];
						}
	    			}
	    			stock[p] <- aged_stock;
	    		}
	    	}
	    	
	    	// calculation of surplus production to be stored + consumption of stock
	    	loop p over: production_outputs_A{
	    		float demand <- tick_pop_consumption_A[p];
	    		float from_stock <- get_stock_to_consume(p, demand);
	    		do consume_stock(p, from_stock);
	    		float demand_to_produce <- demand - from_stock;
	    		float produced <- tick_production_A[p];
	    		float surplus <- produced - demand_to_produce;
	    		
	    		if surplus > 0.0{
	    			stock[p] <- stock[p] + [["quantity"::surplus, "nb_ticks"::0.0]];
	    		}
	    	}
	    	
	    	// we update the displayed stock
	    	loop c over: production_outputs_A {
			    stock_display[c] <- sum(stock[c] collect each["quantity"]);
			}
	    	
	    	// sending the quantities of meat and vegetables produced (excluding surplus) to the population
	    	/*map<string,float> food_production <- [];
	    	loop fp over: tick_pop_consumption_A.keys{
	    		if(fp != "kg_cotton"){
	    			food_production[fp] <- tick_pop_consumption_A[fp];
	    		}
	    	}*/
	    	/*ask one_of(residents){
	    		do send_production_agricultural(food_production);
	    	}	*/    	
	    	
	    	ask agri_consumer{ // prepare new tick on consumer side
	    		do reset_tick_counters;
	    	}
	    	
	    	ask agri_producer{ // prepare new tick on producer side
	    		do reset_tick_counters;
	    	}
	    	
    	}
	}
	
	/*action population_activity(list<human> pop) {
		// to vary the probability of vegetarians
		indivudual_consumption_A <- ["kg_meat"::7.1*(1-vegetarian_proportion), "kg_vegetables"::10.5*(1+vegetarian_proportion)];
		
    	ask pop{ // execute the consumption behavior of the population
    		ask myself.agri_consumer{
    			do consume(myself); // individuals consume agricultural goods
    		}
    	}
    	 
    	ask agri_consumer{ // produce the required quantities
    		ask agri_producer{
    			loop c over: myself.consumed.keys{
    				if(c != "kg_cotton"){
			    		map<string, unknown> info <- produce([c::myself.consumed[c]]); // send the demands to the producer
			    		// note : in this example, we do not take into account the 'ok' signal.
			    	}
		    	}
		    }
    	}    	
    }*/
    
    
    float get_stock_to_consume(string p, float demand){
		if empty(stock[p]) or stock_use_rate <= 0.0 or demand <= 0.0{
			return 0.0;
		}
		
		float stock_to_use <- 0.0;
		float desired_from_stock <- demand * stock_use_rate;
		
		// We sort the stock according to the age (descending) of the resources to consume the oldest ones first
		// FIFO operation
		//list<map<string, float>> sorted_stock <- reverse(sort_by(copy(stock[p]), each["nb_ticks"]));
		list<map<string, float>> sorted_stock <- sort_by(copy(stock[p]), -(each["nb_ticks"]));
		
		loop lot over:sorted_stock{
			if stock_to_use >= desired_from_stock{
				break;
			}
			
			float remaining <- desired_from_stock - stock_to_use;
			stock_to_use <- stock_to_use + min(lot["quantity"], remaining);
		}
		return stock_to_use;
	}
	
	
	action consume_stock(string p, float demand){
		float stock_to_use <- demand;
		
		// sorting the stock according to the age (descending) of the resources (FIFO)
		//list<map<string, float>> sorted_stock <- reverse(sort_by(copy(stock[p]), each["nb_ticks"]));
		list<map<string, float>> sorted_stock <- sort_by(copy(stock[p]), -(each["nb_ticks"]));
		
		list<map<string, float>> updated_stock <- [];
		
		loop lot over:sorted_stock{
			if stock_to_use > 0.0{
				float take <- min(lot["quantity"], stock_to_use);
				lot["quantity"] <- lot["quantity"] - take;
				stock_to_use <- stock_to_use - take;
				continue;
			}
			
			if lot["quantity"] > 0.0{
				updated_stock << lot;
			}
		}
		stock[p] <- updated_stock;
	}
	
	
	action production_fertilizer{
		float qtte_vegetables <- tick_production_A["vegetables"];
		float qtte_cotton <- tick_production_A["cotton"];
		
		// calculating vegetable and cotton losses to make fertilizer (natural and seasonal losses)
		float kg_losses <- float(vegetables_losses(qtte_vegetables));
		kg_losses <- kg_losses + float(cotton_losses(qtte_cotton));
		kg_losses <- kg_losses + kg_rotten_stock; // peut-être différencier cotons, pourritures, légumes ?
		// calculating livestock manure
		float kg_manure <- float(manure_production());
		// calculating food waste PLUS TARD
		//float kg_food_waste <- 0.0; // considérer comme du loss vegetables aussi ?
		
		// transformation into fertilizer
		float kg_fertilizer <- float(tranformation_into_fertilizer(kg_losses, kg_manure));
		
		// VOIR OU METTRE LE CO2 CREE
		//tick_emissions["gCO2e emissions"] <- tick_emissions["gCO2e emissions"] + (production_emissions_fertilizer * kg_fertilizer);
		
		
		// fertilizer stock update (aging)
		if(time_to_fertilize != nil){
			loop f over: time_to_fertilize.keys{
				time_to_fertilize[f] <- time_to_fertilize[f] - 1;
			}
			
			loop f over: time_to_fertilize.keys{
				if time_to_fertilize[f] <= 0 {
					kg_fertilizer_available <- kg_fertilizer_available + f;
					
					// REVOIR LA SUPRESSION
					//time_to_fertilize.remove(f);
				}
			}
		}	
		
		// fertilizer stock update (new qtte)
		time_to_fertilize[kg_fertilizer] <- time_transform_waste_to_fertilizer;	
	}
	
	
	action vegetables_losses(float qtte){
		float tot_losses <- qtte/without_pesticide_vegetables;
		
		/*if(cpt_tick mod 3 = 0){
			current_season <- (current_season + 1) mod 4;
		}*/
		
		string season_name <- seasons[current_season];
		float season_factor <- float(production_seasons[season_name]);
		tot_losses <- tot_losses + (qtte * (1 - season_factor));
		
		return tot_losses * recycling_percentage;
	}
	
	
	action cotton_losses(float qtte){
		float tot_losses <- qtte/without_pesticide_cotton;
		
		/*if(cpt_tick mod 3 = 0){
			current_season <- (current_season + 1) mod 4;
		}*/
		
		string season_name <- seasons[current_season];
		float season_factor <- float(production_seasons[season_name]);
		tot_losses <- tot_losses + (qtte * (1 - season_factor));
		
		return tot_losses * recycling_percentage;
	}
	
	
	action manure_production{
		float kg_animals_tot <- production_output_inputs_A["kg_meat"]["m² land"] * surface_production_A["kg_meat"];
		float manure_tot <- kg_animals_tot *  manure_produced_per_kg_meat;
		return manure_tot * recycling_percentage; 
	}
	
	
	action tranformation_into_fertilizer(float kg_losses, float kg_manure){
		// ajouter les calculs de food waste (et voir avec le transport)
		float kg_fertilizer <- 0.0;
		kg_fertilizer <- kg_fertilizer + (kg_losses * vegetables_to_fertilizer_percentage);
		kg_fertilizer <- kg_fertilizer + (kg_manure * manure_to_fertilizer_percentage);
		return kg_fertilizer;
	}

	
	/**
	 * We define here the production agent of the agricultural bloc as a micro-species (equivalent of nested class in Java).
	 * We implement the methods of the API.
	 * The production is very simple here : for each behavior, we apply an average resource consumption and emissions.
	 * Some of those resources can be provided by other blocs (external producers).
	 */
	species agri_producer parent:production_agent{
		map<string, bloc> external_producers; // external producers that provide the needed resources
		map<string, float> tick_resources_used <- [];
		map<string, float> tick_production <- [];
		map<string, float> tick_emissions <- [];
		
		init{
			external_producers <- []; // external producers that provide the needed resources
		}
		
		map<string, float> get_tick_inputs_used{
			return tick_resources_used;
		}
		
		map<string, float> get_tick_outputs_produced{
			return tick_production;
		}
		
		map<string, float> get_tick_emissions{
			return tick_emissions;
		}
		
		action set_supplier(string product, bloc bloc_agent){
			write name+": external producer "+bloc_agent+" set for "+product;
			external_producers[product] <- bloc_agent;
		}
	
		action reset_tick_counters{ // reset impact counters
			loop u over: production_inputs_A{
				tick_resources_used[u] <- 0.0; // reset resources usage
			}
			loop p over: production_outputs_A{
				tick_production[p] <- 0.0; // reset productions
			}
			loop e over: production_emissions_A{
				tick_emissions[e] <- 0.0;
			}
			
			// reset of hunted animals
			hunted_animals <- 0;
			hunted_animals_kg <- 0.0;
		}
		
		
		
		map<string, unknown> produce(map<string,float> demand){
			bool ok <- true;
			loop c over: demand.keys{
				if(c = "kg_meat" or c = "kg_vegetables" or c = "kg_cotton"){
						
					// recalculation of demand with the impact of seasons
					if(c = "kg_vegetables" or c = "kg_cotton"){
						demand[c] <- demand[c] + float(impact_seasons(demand[c]));
					}
					
					
					float from_stock <- 0.0;
					ask one_of(agricultural){
						from_stock <- get_stock_to_consume(c, demand[c]);
					}
					float to_produce <- demand[c] - from_stock;
					float augmented_demand <- to_produce * (1 + overproduction_factor);
					
					
					float additional_production <- 0.0;
					// application of the hunting
					if(c = "kg_meat"){
						do hunting(augmented_demand); 
						//additional_production <- hunted_animals_kg;
						additional_production <- min(hunted_animals_kg, augmented_demand);
					}
					// application of the fertilizer
					if(c = "kg_vegetables"){ 
						//additional_production <- float(application_fertilizer("kg_vegetables"));
						additional_production <- min(float(application_fertilizer("kg_vegetables")), augmented_demand);	
					}
					// application of the fertilizer
					if(c = "kg_cotton"){
						additional_production <- min(float(application_fertilizer("kg_cotton")), augmented_demand);
					}
					tick_production[c] <- tick_production[c] + additional_production;
					augmented_demand <- augmented_demand - additional_production;
					
					
					loop u over: production_inputs_A{
						
						float quantity_needed; // quantify the resources consumed/emitted by this demand
						
						if(external_producers.keys contains u){ // if there is a known external producer for this product/good
						
							// we specifically send JUST the request
							if(u = "km/kg_scale_2"){
								quantity_needed <- production_output_inputs_A[c][u] * demand[c];
																
								tick_resources_used[u] <- tick_resources_used[u] + quantity_needed; 
								// bool av <- external_producers[u].producer.produce([u::quantity_needed]); // ask the external producer to product the required quantity
								// if not av{
								// 	 ok <- false;
								// }
								
								map<string, unknown> info <- external_producers[u].producer.produce([u::quantity_needed]);
								if not bool(info["ok"]) {
									ok <- false;
								}
								
								continue;
							}
							
							quantity_needed <- production_output_inputs_A[c][u] * augmented_demand;
														
							// allocate only the necessary space without the space already belonging to us
							if(u = "m² land"){
								tick_resources_used[u] <- tick_resources_used[u] + surface_production_A[c];
								
								if(quantity_needed > surface_production_A[c]){
									quantity_needed <- quantity_needed - surface_production_A[c];
									surface_production_A[c] <- surface_production_A[c] + quantity_needed;
								} else {
									continue;
								}
							}
							
							tick_resources_used[u] <- tick_resources_used[u] + quantity_needed; 
							// bool av <- external_producers[u].producer.produce([u::quantity_needed]); // ask the external producer to product the required quantity
							// if not av{
							//	 ok <- false;
							// }
							
							map<string, unknown> info <- external_producers[u].producer.produce([u::quantity_needed]);
							if not bool(info["ok"]) {
								ok <- false;
							}
						}
					}
					
					loop e over: production_emissions_A{ // apply emissions
						float quantity_emitted <- production_output_emissions_A[c][e] * augmented_demand;
						tick_emissions[e] <- tick_emissions[e] + quantity_emitted;
						do send_ges_to_ecosystem(tick_emissions[e]);
					}
					
					// adding of fertilizer's emissions (on production/fermentation or utilisation ?)
					
					tick_production[c] <- tick_production[c] + augmented_demand;
					
					tick_pop_consumption_A[c] <- tick_pop_consumption_A[c] + demand[c];
				
				}
			}
			
			map<string, unknown> prod_info <- [
        		"ok"::ok
        	];
			
			return prod_info;
		}
		
		action hunting(float demand){
			float kg_animal_to_hunt <- demand * hunting_over_farm;
			float max_kg_hunted <- hunted_per_month * kg_per_animal;
			float hunted_kg <- min(kg_animal_to_hunt, max_kg_hunted);
			hunted_animals_kg <- hunted_kg;
		}	
		
		
		action application_fertilizer(string type){
			float nb_m2_with_fertilizer <- kg_fertilizer_available / kg_fertilizer_per_m2;
			
			if(nb_m2_with_fertilizer > surface_production_A[type]){
				float m2_extra <- nb_m2_with_fertilizer - surface_production_A[type];
				float fertilizer_extra <- m2_extra * kg_fertilizer_per_m2;
				
				nb_m2_with_fertilizer <- surface_production_A[type];	
				kg_fertilizer_available <- fertilizer_extra;
			} else {
				kg_fertilizer_available <- 0.0;	
			}
			
			float m2_per_kg_type <- production_output_inputs_A[type]["m² land"];
			float kg_type_with_fertilizer <- nb_m2_with_fertilizer * m2_per_kg_type;
			float additional_yield <- kg_type_with_fertilizer * fertilizer_yield_increase;
			
			return additional_yield;
		}
		
		
		action impact_seasons(float demand){
			if(cpt_tick mod 3 = 0){
				current_season <- (current_season + 1) mod 4;
			}
			
			string season_name <- seasons[current_season];
			float season_factor <- float(production_seasons[season_name]);
			float kg_production_to_add <- demand * (1 - season_factor);
			
			return kg_production_to_add;
		}
			
	}
	
	
	
	/**
	 * We define here the consumption agent of the agricultural bloc as a micro-species (equivalent of nested class in Java).
	 * We implement the methods of the API.
	 * The consumption is very simple here : each behavior as a certain probability to be selected.
	 */
	species agri_consumer parent:consumption_agent{
	
		map<string,float> consumed <- [];
		
		map<string, float> get_tick_consumption{
			return copy(consumed);
		}
		
		init{
			loop c over: production_outputs_A{
				consumed[c] <- 0;
			}
		}
		
		action reset_tick_counters{ 
    		loop c over: consumed.keys{ // reset choices counters
    			consumed[c] <- 0;
    		}
		}
		
		action consume(human h){ 
		    /*loop c over: indivudual_consumption_A.keys{
		    	if(c != "kg_cotton"){
		    		consumed[c] <- consumed[c]+ (indivudual_consumption_A[c] * nb_humans);
		    	}
		    }*/
		}
	}
}


/**
 * We define here the experiment and the displays related to agricultural. 
 * We will then be able to run this experiment from the Main code of the simulation, with all the blocs connected.
 * 
 * Note : experiment car inherit another experiment, but we can't combine displays from multiple experiments at the same time. 
 * If needed, a new experiment combining all those displays should be added, for example in the Main code of the simulation.
 */
experiment run_agricultural type: gui {
	
	//parameter "Taux végétariens" var:vegetarian_proportion min:0.0 max:1.0;
	parameter "Taux surproduction" var:overproduction_factor min:0.0 max:1.0;
	parameter "Taux utilisation stock" var:stock_use_rate min:0.0 max:1.0;
	parameter "Taux de chasse" var:hunting_over_farm min:0.0 max:1.0;
	
	output {
		display Agricultural_information {
			chart "Population direct consumption" type: series  size: {0.5,0.5} position: {0, 0} {
			    loop c over: production_outputs_A{
			    	data c value: tick_pop_consumption_A[c]; // note : products consumed by other blocs NOT included here (only population direct consumption)
			    }
			}
			chart "Total production" type: series  size: {0.5,0.5} position: {0.5, 0} {
			    loop c over: production_outputs_A{
			    	data c value: tick_production_A[c];
			    }
			}
			chart "Resources usage" type: series size: {0.5,0.5} position: {0, 0.5}  y_log_scale:true{
			    loop r over: production_inputs_A{
			    	data r value: tick_resources_used_A[r];
			    }
			}
			chart "Production emissions" type: series size: {0.5,0.5} position: {0.5, 0.5} {
			    loop e over: production_emissions_A{
			    	data e value: tick_emissions_A[e];
			    }
			}
			chart "Stock quantity evolution" type: series  size: {0.5,0.5} position: {1, 0}{
			    loop c over: production_outputs_A{
			    	data c value: stock_display[c];
			    }
			}
			chart "Surface production" type: series size: {0.5,0.5} position: {1, 0.5}  y_log_scale:true{
			    loop s over: production_outputs_A{
			    	data s value: surface_production_A[s];
			    }
			}
			chart "Chasse" type: series size: {0.5,0.5} position: {0, 1}{
				data "hunted_kg" value:hunted_animals_kg;
			}
	    }
	}
}
