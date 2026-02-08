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
	
	bool verbose_Agricultural <- false;
	float nb_humans_per_agent <- 19500.0;
	// DEBUG: multiplier to scale all delivered outputs (set to 0.0 to simulate full shortage)
	float debug_output_multiplier <- 1.0;
	
	/* Setup */
	list<string> production_outputs_A <- ["kg_meat", "kg_vegetables", "kg_cotton"];
	list<string> production_inputs_A <- ["L water", "kWh energy", "m² land", "km/kg_scale_2"];
	list<string> production_emissions_A <- ["gCO2e emissions"];
	list<string> production_demand_A <- ["kg_meat", "kg_vegetables", "kg_cotton"];
	
	/* Parameter for transport */
	float distance <- 50.0;
	
	/* Parameter to simulate production without pesticide */
	float without_pesticide <- 1.35; // 35% additional production because of no pesticide
	
	/* Production data */
	map<string, map<string, float>> production_output_inputs_A <- [
		"kg_meat"::["L water"::8576.0, "kWh energy"::10.0, "m² land"::12.8, "km/kg_scale_2"::distance],
		"kg_vegetables"::["L water"::425.0*without_pesticide, "kWh energy"::0.5*without_pesticide, "m² land"::0.47*without_pesticide, "km/kg_scale_2"::distance],
		"kg_cotton"::["L water"::10000.0*without_pesticide, "kWh energy"::0.2*without_pesticide, "m² land"::13.3*without_pesticide, "km/kg_scale_2"::distance]
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
	//float overproduction_factor <- 0.05;
	
	/* Percentage of stock utilization */
	//float stock_use_rate <- 1.0;
	
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
	map<string, float> tick_demand_A <- [];
	map<string, float> tick_consumption_A <- [];
	float agri_water_used_tick <- 0.0;
	
	/* Parameters for hunting */
	float hunting_over_farm <- 0.6; // proportions of meat produced from hunting
	//float hunted_per_month <- 38000000 / 12; // number of animals hunted per month in France
	float kg_per_animal <- 25.0;
    int hunted_animals <- 0;
    float hunted_animals_kg <- 0.0;
    
    
    /* Parameters for fertilizer */
    float kg_fertilizer_per_m2 <- 3.0;
    float fertilizer_yield_increase <- 0.3;  
    
    float manure_produced_per_kg_meat <- 15.0;
    int time_transform_waste_to_fertilizer <- 4;
    float recycling_percentage <- 0.99;
    float vegetables_to_fertilizer_percentage <- 0.3;
    float manure_to_fertilizer_percentage <- 0.05;
    
    float production_emissions_fertilizer <- 1.2;
    float CO2_fermentation <- 0.15;
    //float CO2_production <- 0.05;
    //float CO2_emission <- 0.01;
    
    //map<float,int> time_to_fertilize <- [];
    list<map> fertilizer_batches <- [];
    
    
    float kg_fertilizer_available <- 0.0;
    float kg_rotten_stock <- 0.0;
    float food_waste_received <- 0.0;
    map<string, float> tick_fertilizer <- ["produced"::0.0, "applied"::0.0];
    
    map<string,float> production_this_tick <- ["kg_meat"::0.0, "kg_vegetables"::0.0, "kg_cotton"::0.0];
    
    float kg_losses <- 0.0;
    
    map<string, float> tick_resources_used_meat <- ["L water"::0.0, "kWh energy"::0.0, "m² land"::0.0, "km/kg_scale_2"::0.0];
	map<string, float> tick_resources_used_veg  <- ["L water"::0.0, "kWh energy"::0.0, "m² land"::0.0, "km/kg_scale_2"::0.0];
	map<string, float> tick_resources_used_cot  <- ["L water"::0.0, "kWh energy"::0.0, "m² land"::0.0, "km/kg_scale_2"::0.0];
    
    /* Parameters for seasons */
    int month_agri <- 0;
	int year_agri <- 0;
	string season_agri <- "winter";
    
    /*map<string, float> production_seasons <- [
		"spring"::1.0,
		"summer"::0.8,
		"autumn"::0.9,
		"winter"::0.3
	];
    
    map<string, float> seasonal_overproduction <- [
	    "spring"::0.15,
	    "summer"::0.05,
	    "autumn"::0.10,
	    "winter"::0.0
	];
	
	map<string, float> seasonal_stock_use <- [
	    "spring"::0.0,
	    "summer"::0.2,
	    "autumn"::0.1,
	    "winter"::0.8
	];*/
	
	/*map<string, float> seasonal_threshold_water <- [
	  "winter"::5.0e12,
	  "spring"::2.6e12,
	  "summer"::6.6e11,
	  "autumn"::4.0e12
	];*/
	
	// --- Lissage demande/production (éviter pics) ---
	float alpha_demand_smoothing <- 0.25; // 0.0 = pas de lissage ; 1.0 = ultra réactif
	map<string,float> smoothed_demand <- ["kg_meat"::0.0, "kg_vegetables"::0.0, "kg_cotton"::0.0];
	
	// --- Cap surface (limite physique) ---
	// tu fixes un plafond réaliste (à adapter à ton modèle)
	float max_surface_total <- 6.0e11; // m² (ex: 600 000 km² -> 6e11 m²) A AJUSTER
	float surface_growth_rate <- 0.05; // vitesse d’extension max par tick (5% du max)
	
	// --- Cap eau par tick (L) ---
	float max_water_use_per_tick <- 1.8e13; // 0.0 = désactive le cap
		
	// --- Lissage saison (éviter yoyo trop violent) ---
	map<string,float> production_seasons <- [
	  "spring"::1.0,
	  "summer"::0.9,
	  "autumn"::0.8,
	  "winter"::0.6
	];
	
	float global_overprod_factor <- 1.0; // >1 -> overproduction more intense overall, <1 -> less overprod
	float global_stock_use_factor <- 1.0; // >1 -> stock use more intense overall, <1 -> less usage of stock
	
	float overprod_spring <- 0.10;
	float overprod_summer <- 0.05;
	float overprod_autumn <- 0.08;
	float overprod_winter <- 0.02;
	
	// surproduction plus raisonnable
	map<string, float> seasonal_overproduction <- [
	  "spring"::overprod_spring * global_overprod_factor,
	  "summer"::overprod_summer * global_overprod_factor,
	  "autumn"::overprod_autumn * global_overprod_factor,
	  "winter"::overprod_winter * global_overprod_factor
	];
	// surproduction coton (réduite)
	map<string, float> seasonal_overproduction_cotton <- [
	  "spring"::0.02,
	  "summer"::0.01,
	  "autumn"::0.02,
	  "winter"::0.0
	];
	
		
	float stock_use_spring <- 0.10;
	float stock_use_summer <- 0.15;
	float stock_use_autumn <- 0.20;
	float stock_use_winter <- 0.25;
	
	// utilisation stock plus progressive (sinon tu vides tout en hiver et tu n’as plus rien)
	map<string, float> seasonal_stock_use <- [
	  "spring"::stock_use_spring * global_stock_use_factor,
	  "summer"::stock_use_summer * global_stock_use_factor,
	  "autumn"::stock_use_autumn * global_stock_use_factor,
	  "winter"::stock_use_winter * global_stock_use_factor
	];
	
	float seasonal_overproduction_effective {
	    return seasonal_overproduction[season_agri];
	}
	
	float seasonal_stock_use_effective {
	    return seasonal_stock_use[season_agri];
	}
		
	
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
	
	action tick(list<human> pop, list<mini_ville> cities) {
		
		//write season_agri;
		
		do update_time_and_season_agri;
		do collect_last_tick_data();
		
		//do population_activity(pop);
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
	
	list<string> get_demand_labels{
		return production_demand_A;
	}
	
	
	action receive_waste_food(float waste) {
		food_waste_received <- waste;
	}
	
	action collect_last_tick_data{
		if(cycle > 0){ // skip it the first tick
			tick_consumption_A <- producer.get_tick_consumption(); // collect consumption behaviors
	    	tick_resources_used_A <- producer.get_tick_inputs_used(); // collect resources used
	    	tick_production_A <- producer.get_tick_outputs_produced(); // collect production
	    	tick_emissions_A <- producer.get_tick_emissions(); // collect emissions
	    	tick_demand_A <- producer.get_tick_demand(); // collect demand of other sectors
	    	
	    	do production_fertilizer;
	    		    	
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
	    		float demand <- tick_consumption_A[p];
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
	    		loop e over:production_demand_A{
					tick_demand[e] <- 0.0;
					//tick_pop_consumption_A[e] <- 0.0;
				}
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
    
    float get_seasonal_overproduction{
	    string s <- season_agri;
	    return seasonal_overproduction[s];
	}
	
	float get_seasonal_stock_use{
	    string s <- season_agri;
	    return seasonal_stock_use[s];
	}
		
    
    
    float get_stock_to_consume(string p, float demand){
    	float seasonal_stock_rate <- get_seasonal_stock_use();
    	//write "consommation stock : " + seasonal_stock_rate;
		/*if empty(stock[p]) or stock_use_rate <= 0.0 or demand <= 0.0{
			return 0.0;
		}*/
		if empty(stock[p]) or seasonal_stock_rate <= 0.0 or demand <= 0.0{
			return 0.0;
		}
		
		float stock_to_use <- 0.0;
		//float desired_from_stock <- demand * stock_use_rate;
		float desired_from_stock <- demand * seasonal_stock_rate;
		
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
		tick_fertilizer["produced"] <- 0.0;
		tick_fertilizer["applied"] <- 0.0;

		float qtte_vegetables <- production_this_tick["kg_vegetables"];
		float qtte_cotton <- production_this_tick["kg_cotton"];
	
		// calculating vegetable and cotton losses to make fertilizer (natural and seasonal losses)
		kg_losses <- float(vegetables_losses(qtte_vegetables));
		kg_losses <- kg_losses + float(cotton_losses(qtte_cotton));
		kg_losses <- kg_losses + kg_rotten_stock;
		kg_rotten_stock <- 0.0;
		
		// calculating livestock manure
		float kg_manure <- float(manure_production());
		
		// transformation into fertilizer
		float kg_fertilizer <- float(tranformation_into_fertilizer(kg_losses, kg_manure));
		tick_fertilizer["produced"] <- kg_fertilizer;
		
		ask producer {
		    float gco2e_fert_prod <- CO2_fermentation * kg_fertilizer;
		    do send_ges_to_ecosystem("agriculture", gco2e_fert_prod);
		    tick_emissions["gCO2e emissions"] <- tick_emissions["gCO2e emissions"] + gco2e_fert_prod;
		}
		
		// fertilizer stock update (aging)
		if (!empty(fertilizer_batches)) {
		
		    list<map> keep <- [];
		
		    loop b over: copy(fertilizer_batches) {
		
		        float t <- float(b["t"]) - 1.0;
		        float kg <- float(b["kg"]);
		
		        if (t <= 0.0) {
		            kg_fertilizer_available <- kg_fertilizer_available + kg;
		        } else {
		            keep << ["kg"::kg, "t"::t];
		        }
		    }
		
		    fertilizer_batches <- keep;
		    
		}
		
		if (kg_fertilizer > 0.0) {
		    fertilizer_batches << ["kg"::kg_fertilizer, "t"::time_transform_waste_to_fertilizer];
		}
		
	}
	
	
	action vegetables_losses(float qtte){
	    float tot_losses <- qtte/without_pesticide;
	
	    string season_name <- season_agri;
	    float season_factor <- float(production_seasons[season_name]);
	
	    float internal <- qtte / max(season_factor, 1e-9);
	    float season_loss <- internal - qtte;
	
	    tot_losses <- tot_losses + season_loss;
	
	    return tot_losses * recycling_percentage;
	}
	
	action cotton_losses(float qtte){
	    float tot_losses <- qtte/without_pesticide;
	
	    string season_name <- season_agri;
	    float season_factor <- float(production_seasons[season_name]);
	
	    float internal <- qtte / max(season_factor, 1e-9);
	    float season_loss <- internal - qtte;
	
	    tot_losses <- tot_losses + season_loss;
	
	    return tot_losses * recycling_percentage;
	}
	
	action manure_production{
		float m2_used <- surface_production_A["kg_meat"];
		float m2_per_kg <- production_output_inputs_A["kg_meat"]["m² land"];
		
		float kg_meat_2 <- m2_used / max(m2_per_kg, 1e-9);
		float manure_tot <- kg_meat_2 * manure_produced_per_kg_meat;
		return manure_tot * recycling_percentage; 
	}
	
	
	action tranformation_into_fertilizer(float kg_losses, float kg_manure){
		// ajouter les calculs de food waste (et voir avec le transport)
		float kg_fertilizer <- 0.0;
		kg_fertilizer <- kg_fertilizer + (kg_losses * vegetables_to_fertilizer_percentage);
		kg_fertilizer <- kg_fertilizer + (kg_manure * manure_to_fertilizer_percentage);
		return kg_fertilizer;
	}
	
	action update_time_and_season_agri{
	    month_agri <- (month_agri + 1) mod 12;
	    if (month_agri = 0){
	        year_agri <- year_agri + 1;
	    }
	
	    if month_agri in [11, 0, 1]{          
	        season_agri <- "winter";
	    } else if month_agri in [2, 3, 4]{    
	        season_agri <- "spring";
	    } else if month_agri in [5, 6, 7]{    
	        season_agri <- "summer";
	    } else {                              
	        season_agri <- "autumn";
	    }
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
		map<string, float> tick_demand <- [];
		map<string, float> tick_consumption <- [];
		
		init{
			external_producers <- []; // external producers that provide the needed resources
		}
		
		map<string, float> get_tick_inputs_used{
			return tick_resources_used;
		}
		
		map<string, float> get_tick_outputs_produced{
			return tick_production;
		}
		
		map<string, float> get_tick_demand{
			return tick_demand;
		}
		
		map<string, float> get_tick_emissions{
			return tick_emissions;
		}
		
		map<string, float> get_tick_consumption{
			return tick_consumption;
		}
		
		action set_supplier(string product, bloc bloc_agent){
			if verbose_Agricultural {
				write name+": external producer "+bloc_agent+" set for "+product;
			}
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
			loop e over:production_demand_A{
				tick_demand[e] <- 0.0;
				tick_consumption[e] <- 0.0;
			}
			
			loop e over:production_this_tick.keys(){
				production_this_tick[e] <- 0.0;
			}
			
			// reset of hunted animals
			hunted_animals <- 0;
			hunted_animals_kg <- 0.0;
		}
		
		
		
		map<string, unknown> produce(string bloc_name, map<string,float> demand){
		    bool ok <- true;
		    		    
		    map<string, unknown> res <- [
		    	"ok"::true,
		    	"transmitted_vegetables"::0.0,
		    	"transmitted_meat"::0.0,
		  		"transmitted_cotton"::0.0
		    ];
		    		
		    loop c over: demand.keys(){
		    	
		    	tick_demand[c] <- tick_demand[c] + demand[c];
		    	
		    	/*float new_demand <- demand[c];
		    	float prev <- smoothed_demand[c];
				float smooth <- (1.0 - alpha_demand_smoothing) * prev + alpha_demand_smoothing * new_demand;
				smoothed_demand[c] <- smooth;
				new_demand <- smooth;*/
				float new_demand <- demand[c];
				
		    	if(external_producers.keys contains "km/kg_scale_2"){
	                float quantity_needed <- production_output_inputs_A[c]["km/kg_scale_2"] * demand[c];
					if(quantity_needed > 0){
	                    map<string, unknown> info <- external_producers["km/kg_scale_2"].producer.produce("agriculture", ["km/kg_scale_2"::quantity_needed]);
	                    if not bool(info["ok"]) { 
	                    	float transmitted_transport <- float(info["transmitted_transport_km"]);
	                    	float ratio <- float(transmitted_transport/quantity_needed);
	                    	new_demand <- demand[c]*ratio;
	                    	tick_resources_used["km/kg_scale_2"] <- tick_resources_used["km/kg_scale_2"] + transmitted_transport;
	                    	res["ok"] <- false;
	                    } else{
	                    	tick_resources_used["km/kg_scale_2"] <- tick_resources_used["km/kg_scale_2"] + quantity_needed;
	                    }
	            	}
                }
	    			    		
	    			    		
	            float from_stock <- 0.0;
	            float seasonal_overprod <- 0.0;
	            ask one_of(agricultural){
	                from_stock <- get_stock_to_consume(c, new_demand);
	                seasonal_overprod <- get_seasonal_overproduction();
	            }
	
	            float to_produce <- new_demand - from_stock;
	            if (to_produce < 0.0) { to_produce <- 0.0; }
	
	            // livré visé (surproduction)
	            //float deliver <- to_produce * (1 + overproduction_factor);
	            float deliver <- to_produce * (1 + seasonal_overprod);
	            if (c = "kg_cotton") {
	                deliver <- to_produce * (1 + seasonal_overproduction_cotton[season_agri]);
	            }
	            
	            
	            // aide (chasse / engrais) = livré
	            float additional_production <- 0.0;
	
	            if(c = "kg_meat"){
	                do hunting(deliver);
	                additional_production <- hunted_animals_kg;
	            }
	            if(c = "kg_vegetables"){
					additional_production <- float(application_fertilizer("kg_vegetables"));

	            }
	            if(c = "kg_cotton"){
	                additional_production <- float(application_fertilizer("kg_cotton"));
	            }
	
	            // on borne : pas plus que ce qu'on veut livrer
	            float additional_used <- min(additional_production, deliver);
	
	            // reste à produire "normalement" (livré)
	            float deliver_remaining <- deliver - additional_used;
	            
	            write "stock : " + from_stock;
	            write "additional : " + additional_used;
	            write "restant : " + deliver_remaining;
	            
	            
	            // on applique les pertes dues aux saisons
	            float deliver_remaining_with_losses <- deliver_remaining + (deliver_remaining * (1 - production_seasons[season_agri]));
					            
	
	            loop u over: production_inputs_A{
	                if(external_producers.keys contains u){	
	                    
	
	                    float quantity_needed <- production_output_inputs_A[c][u] * deliver_remaining_with_losses;
	
						if (u = "m² land") {
						
						    // besoin brut
						    float need_land <- quantity_needed;
						
						    // surface déjà installée
						    float already <- surface_production_A[c];
						
						    // manque réel
						    float missing <- max(need_land - already, 0.0);
						
						    // cap global (toutes cultures confondues)
						    float total_surface <- surface_production_A["kg_meat"] + surface_production_A["kg_vegetables"] + surface_production_A["kg_cotton"];
						
						    float remaining_global <- max(max_surface_total - total_surface, 0.0);
						
						    // cap d’extension par tick
						    float max_add_this_tick <- min(remaining_global, max_surface_total * surface_growth_rate);
						
						    float add_land <- min(missing, max_add_this_tick);
						
						    // on compte l’utilisation de la surface existante
						    tick_resources_used[u] <- tick_resources_used[u] + min(need_land, already);
						
						    // si on doit ajouter de la surface : on la demande au bloc land (et on borne)
						    if (add_land > 0.0) {
						        map<string, unknown> info <- external_producers[u].producer.produce("agriculture", [u::add_land]);
						
						        if not bool(info["ok"]) {
						            float transmitted_land <- float(info["transmitted_land"]);
						            float ratio <- transmitted_land / max(add_land, 1e-9);
						
						            // si on n’a pas eu toute la surface, on réduit la prod
						            deliver_remaining <- deliver_remaining * ratio;
						            deliver_remaining_with_losses <- deliver_remaining_with_losses * ratio;
						
						            tick_resources_used[u] <- tick_resources_used[u] + transmitted_land;
						            surface_production_A[c] <- surface_production_A[c] + transmitted_land;
						        } else {
						            tick_resources_used[u] <- tick_resources_used[u] + add_land;
						            surface_production_A[c] <- surface_production_A[c] + add_land;
						        }
						    } else {
						        // pas possible d’étendre -> on doit réduire la prod (cap dur)
						        if (missing > 0.0) {
						            // ratio de surface réellement dispo vs surface requise
						            float possible <- already / max(need_land, 1e-9);
						            possible <- max(min(possible, 1.0), 0.0);
						            deliver_remaining <- deliver_remaining * possible;
						            deliver_remaining_with_losses <- deliver_remaining_with_losses * possible;
						        }
						    }
						
						    continue;
						}

	                    
	                    if (u = "L water") {
						    float requested_water <- quantity_needed;
						    float water_limit <- max_water_use_per_tick;
						    float remaining_allowance <- (water_limit > 0.0) ? max(0.0, water_limit - tick_resources_used[u]) : requested_water;
						    float capped_request <- min(requested_water, remaining_allowance);
						
						    if (capped_request <= 0.0) {
						        deliver_remaining <- 0.0;
						        deliver_remaining_with_losses <- 0.0;
						        continue;
						    }
						
						    map<string, unknown> info <- external_producers[u].producer.produce("agriculture", [u::capped_request]);
						
						    if not bool(info["ok"]) {
						        float transmitted_water <- float(info["transmitted_water"]);
						        float ratio <- float(transmitted_water / max(requested_water, 1e-9));
						        deliver_remaining <- deliver_remaining * ratio;
						        deliver_remaining_with_losses <- deliver_remaining_with_losses * ratio;
						        tick_resources_used[u] <- tick_resources_used[u] + transmitted_water;
						    } else {
						        float ratio <- float(capped_request / max(requested_water, 1e-9));
						        if (ratio < 1.0) {
						            deliver_remaining <- deliver_remaining * ratio;
						            deliver_remaining_with_losses <- deliver_remaining_with_losses * ratio;
						        }
						        tick_resources_used[u] <- tick_resources_used[u] + capped_request;
						    }
						
						    continue;
						}

	                    
	                    if(u = "kWh energy"){
	                        map<string, unknown> info <- external_producers[u].producer.produce("agriculture", [u::quantity_needed]);
	                        // write "info : " + info;
	                        if not bool(info["ok"]) { 
	                        	//write "bloque" + u;
	                        	float transmitted_energy <- float(info["transmitted_kwh"]);
	                        	float ratio <- float(transmitted_energy/quantity_needed);
	                        	deliver_remaining <- deliver_remaining*ratio;
	                        	deliver_remaining_with_losses <- deliver_remaining_with_losses*ratio;
	                        	tick_resources_used[u] <- tick_resources_used[u] + transmitted_energy;
	                        } else{
	                        	tick_resources_used[u] <- tick_resources_used[u] + quantity_needed;
	                        }
	                        continue;
	                      
	                    }

	                }
		        }
		        
		        ask one_of(agricultural) {
					production_this_tick[c] <- production_this_tick[c] + deliver_remaining_with_losses;
				}
		        
		        loop e over: production_emissions_A{
	                float quantity_emitted <- production_output_emissions_A[c][e] * deliver_remaining_with_losses;
	              	do send_ges_to_ecosystem("agriculture", quantity_emitted);
	                tick_emissions[e] <- tick_emissions[e] + quantity_emitted;
	            }
	
	            
	            float deliver_real <- (deliver_remaining + additional_used + from_stock) * debug_output_multiplier;
	            
	            if(deliver_real >= new_demand){
	            	res["ok"] <- true;
	            } else {
	            	res["ok"] <- false;
	            }
		        
		        if(c = "kg_meat"){
		        	res["transmitted_meat"] <- min(new_demand,deliver_real); 
		        	tick_consumption[c] <- tick_consumption[c] + float(res["transmitted_meat"]); 
		        }
		        if(c = "kg_vegetables"){
		        	res["transmitted_vegetables"] <- min(new_demand,deliver_real); 
		        	tick_consumption[c] <- tick_consumption[c] + float(res["transmitted_vegetables"]); 
		        }
		        if(c = "kg_cotton"){
		        	res["transmitted_cotton"] <- min(new_demand,deliver_real); 
		        	tick_consumption[c] <- tick_consumption[c] + float(res["transmitted_cotton"]); 
		        }
		        
		        
		        tick_production[c] <- tick_production[c] + deliver_real - from_stock;	            
		    }
		    	
		    return res;
		}

		
		action hunting(float demand){
			float animals_needed <- demand / kg_per_animal;
		    float animals_obtained <- 0.0;
		    ask ecosystem {
		        animals_obtained <- hunt_request(animals_needed);
		    }
		    hunted_animals_kg <- animals_obtained * kg_per_animal;
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
			float kg_type_with_fertilizer <- nb_m2_with_fertilizer / max(m2_per_kg_type, 1e-9);
			float additional_yield <- kg_type_with_fertilizer * fertilizer_yield_increase;
			
			float kg_fertilizer_applied <- nb_m2_with_fertilizer * kg_fertilizer_per_m2;
			ask one_of(agricultural){
				tick_fertilizer["applied"] <- tick_fertilizer["applied"] + kg_fertilizer_applied;
			}
			
			return additional_yield;
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
	//parameter "Taux surproduction" var:overproduction_factor min:0.0 max:1.0;
	//parameter "Taux utilisation stock" var:stock_use_rate min:0.0 max:1.0;
	parameter "Taux de chasse" var:hunting_over_farm min:0.0 max:1.0;
	
	parameter 'Facteur global surprod' var: global_overprod_factor min:0.0 max:5.0 step:0.1;
	parameter "Surprod printemps" var: overprod_spring min:0.0 max:1.0 step:0.01;
	parameter "Surprod été"       var: overprod_summer min:0.0 max:1.0 step:0.01;
	parameter "Surprod automne"   var: overprod_autumn min:0.0 max:1.0 step:0.01;
	parameter "Surprod hiver"     var: overprod_winter min:0.0 max:1.0 step:0.01;
	
	parameter "Facteur global stock use" var: global_stock_use_factor min:0.0 max:5.0 step:0.1;
	parameter "Usage stock printemps" var: stock_use_spring min:0.0 max:1.0 step:0.05;
	parameter "Usage stock été"       var: stock_use_summer min:0.0 max:1.0 step:0.05;
	parameter "Usage stock automne"   var: stock_use_autumn min:0.0 max:1.0 step:0.05;
	parameter "Usage stock hiver"     var: stock_use_winter min:0.0 max:1.0 step:0.05;
	
	output {
		monitor "Mois" value: month_agri;
		monitor "Année" value: year_agri;
		monitor "Saison agricole" value: season_agri;
		monitor "Surproduction saison" value: one_of(agricultural).get_seasonal_overproduction();
		monitor "Usage stock saison" value: one_of(agricultural).get_seasonal_stock_use();
		
		display Agricultural_information {
			chart "Direct consumption" type: series  size: {0.5,0.5} position: {0, 0} {
			    loop c over: production_outputs_A{
			    	data c value: tick_consumption_A[c]; 
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
			chart "Engrais" type: series size: {0.5,0.5} position: {0.5, 1}{
				data "kg engrais produits" value:tick_fertilizer["produced"];
				data "kg engrais consommés" value:tick_fertilizer["applied"];				
			}
			chart "Pertes" type: series size: {0.5,0.5} position: {1, 1}{
				data "kg pertes production" value:kg_losses;				
			}
	    }
	}
}
