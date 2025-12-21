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
	
	// paramètre pour le transport 
	float distance <- 50.0;
	
	/* Production data */
	map<string, map<string, float>> production_output_inputs_A <- [
		// pourquoi j'ai besoin de gaz à effets de serre ?
		"kg_meat"::["L water"::15500.0, "kWh energy"::8.0, "m² land"::27.0, "km/kg_scale_2"::distance],
		"kg_vegetables"::["L water"::500.0, "kWh energy"::0.3, "m² land"::0.57, "km/kg_scale_2"::distance],
		"kg_cotton"::["L water"::5200.0, "kWh energy"::0.2, "m² land"::11.0, "km/kg_scale_2"::distance]
	];
	map<string, map<string, float>> production_output_emissions_A <- [
		"kg_meat"::["gCO2e emissions"::27.0],
		"kg_vegetables"::["gCO2e emissions"::0.4],
		"kg_cotton"::["gCO2e emissions"::4.7]
	];
	
	/* Initialisation des surfaces de production */
	map<string, float> surface_production_A <- [
		"kg_meat"::0.0,
		"kg_vegetables"::0.0,
		"kg_cotton"::0.0
	];
	
	/* Facteur de surpoduction pour prévoir du stock */
	float overproduction_factor <- 0.05;
	
	/* Porcetage d'utilisation du stock */
	float stock_use_rate <- 1.0;
	
	/* Initialisation du stock des productions agricoles */
	map<string, list<map<string, float>>> stock <- [
		"kg_meat"::[],
		"kg_vegetables"::[],
		"kg_cotton"::[]
	];
	
	/* Durée de vie des productions agricoles (en nombre de ticks) */
	map<string, int> lifetime_productions <- [
		"kg_meat"::6,
		"kg_vegetables"::8,
		"kg_cotton"::12
	];
	
	/* Stock total par ressource affiché sur le graphe de l'expérience */
	map<string, float> stock_display <- [];
	
	// nb_humains_divises
	int nb_humans <- 6700;
	
	/* Consumption data */
	float vegetarian_proportion <- 0.022;
	map<string, float> indivudual_consumption_A <- ["kg_meat"::7*(1-vegetarian_proportion), "kg_vegetables"::10*(1+vegetarian_proportion)];
	
	/* Counters & Stats */
	map<string, float> tick_production_A <- [];
	map<string, float> tick_pop_consumption_A <- [];
	map<string, float> tick_resources_used_A <- [];
	map<string, float> tick_emissions_A <- [];
	
	// paramètres pour la chasse (sangliers)
	float hunting_over_farm <- 0.4; // proportions de viandes produites venant de la chasse
	map<string, map<string, float>> wild_animals <- [
		"wild_boar"::["quantity"::2000000, "hunting_rate"::0.038, "kg_per_animal"::90.0, "reproduction_rate"::0.079, "mortality_rate"::0.056], // normalement newborns = 250 000 mais croissance expo
		"deer"::["quantity"::1500000, "hunting_rate"::0.03, "kg_per_animal"::24.0, "reproduction_rate"::0.02, "mortality_rate"::0.028],
		"pigeon"::["quantity"::5000000, "hunting_rate"::0.1, "kg_per_animal"::0.5, "reproduction_rate"::0.05, "mortality_rate"::0.066],
		"rabbit"::["quantity"::3000000, "hunting_rate"::0.04, "kg_per_animal"::0.75, "reproduction_rate"::0.068, "mortality_rate"::0.113],
		"random_animal"::["quantity"::50000000, "hunting_rate"::0.3, "kg_per_animal"::10.0, "reproduction_rate"::0.060, "mortality_rate"::0.070]
	];
	//int wild_boar <- 2000000; // près de 2 millions de sangliers en France
	//int hunting_proportion <- 75000; // près de 900 000 sangliers chassés / 12 mois 
    //float animals_reproduction <- 0.15; // ~ 1 à 2 portées par an donc 1/6 
    //int nb_per_litters <- 5; // 5 à 6 marcassins par portées
    //float weight_wilds_animals <- 90.0; // 100 à 110 kg par mâles, 70 à 80 kg par femelles
    
    //float animals_reproduction <- hunting_proportion / wilds_animals;
    int hunted_animals <- 0;
    float hunted_animals_kg <- 0.0;
	
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
		do population_activity(pop);
		do reproduce_animals;
		do natural_mortality_animals;
		//write "ANIMAUX : " + wild_animals;
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
	
	action collect_last_tick_data{
		if(cycle > 0){ // skip it the first tick
			tick_pop_consumption_A <- consumer.get_tick_consumption(); // collect consumption behaviors
	    	tick_resources_used_A <- producer.get_tick_inputs_used(); // collect resources used
	    	tick_production_A <- producer.get_tick_outputs_produced(); // collect production
	    	tick_emissions_A <- producer.get_tick_emissions(); // collect emissions
	    	
	    	// vieillissement du stock
	    	loop p over: production_outputs_A{
	    		if not empty(stock[p]){
	    			list<map<string, float>> aged_stock <- [];
	    			loop lot over: stock[p]{
	    				lot["nb_ticks"] <- lot["nb_ticks"] + 1;
	    				
	    				if lot["nb_ticks"] <= lifetime_productions[p]{
							aged_stock << lot;
						} else {
							write "Péremption " + p + " : quantité = " + lot["quantity"] + ", âge = " + lot["nb_ticks"];
						}
	    			}
	    			stock[p] <- aged_stock;
	    		}
	    	}
	    	
	    	// calcule du surplus de production à stocker + consommation du stock
	    	loop p over: production_outputs_A{
	    		float demand <- tick_pop_consumption_A[p];
	    		float from_stock <- get_stock_to_consume(p, demand);
	    		do consume_stock(p, from_stock);
	    		float demand_to_produce <- demand - from_stock;
	    		float produced <- tick_production_A[p];
	    		float surplus <- produced - demand_to_produce;
	    		
	    		if surplus > 0.0{
	    			stock[p] <- stock[p] + [["quantity"::surplus, "nb_ticks"::0]];
	    		}
	    	}
	    	
	    	// on met à jour le stock affiché
	    	loop c over: production_outputs_A {
			    stock_display[c] <- sum(stock[c] collect each["quantity"]);
			}
	    	
	    	// envoi les quantités de viande et légumes produites à population
	    	map<string,float> food_production <- [];
	    	loop fp over: tick_pop_consumption_A.keys{
	    		if(fp != "kg_cotton"){
	    			food_production[fp] <- tick_pop_consumption_A[fp];
	    		}
	    	}
	    	ask one_of(residents){
	    		do send_production_agricultural(food_production);
	    	}	    	
	    	
	    	ask agri_consumer{ // prepare new tick on consumer side
	    		do reset_tick_counters;
	    	}
	    	
	    	ask agri_producer{ // prepare new tick on producer side
	    		do reset_tick_counters;
	    	}
	    	
    	}
	}
	
	action population_activity(list<human> pop) {
		// on fait évoluer les besoins selon le taux de végétariens
		indivudual_consumption_A <- ["kg_meat"::7*(1-vegetarian_proportion), "kg_vegetables"::10*(1+vegetarian_proportion)];
		
    	ask pop{ // execute the consumption behavior of the population
    		ask myself.agri_consumer{
    			do consume(myself); // individuals consume agricultural goods
    		}
    	}
    	 
    	ask agri_consumer{ // produce the required quantities
    		ask agri_producer{
    			loop c over: myself.consumed.keys{
    				if(c != "kg_cotton"){
			    		bool ok <- produce([c::myself.consumed[c]]); // send the demands to the producer
			    		// note : in this example, we do not take into account the 'ok' signal.
			    	}
		    	}
		    }
    	}    	
    }
    
    
    float get_stock_to_consume(string p, float demand){
		if empty(stock[p]) or stock_use_rate <= 0.0 or demand <= 0.0{
			return 0.0;
		}
		
		float stock_to_use <- 0.0;
		float desired_from_stock <- demand * stock_use_rate;
		
		// on trie le stock en fonction de l'âge (décroissant) des ressources por consommer les plus vieilles d'abord
		// fonctionnement FIFO
		list<map<string, float>> sorted_stock <- reverse(sort_by(copy(stock[p]), each["nb_ticks"]));
		
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
		
		// tri du stock en fonction de l'âge (décroissant) des ressources (FIFO)
		list<map<string, float>> sorted_stock <- reverse(sort_by(copy(stock[p]), each["nb_ticks"]));
		
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
	
	action reproduce_animals {
	    loop a over: wild_animals.keys {
	    	/*if(wild_animals[a]["quantity"] < 1000){
			    wild_animals[a]["quantity"] <- wild_animals[a]["quantity"] + 1000;
			}*/
	        if wild_animals[a]["quantity"] > 0 {
	            float newborns <- round(wild_animals[a]["quantity"] * wild_animals[a]["reproduction_rate"]);
	            wild_animals[a]["quantity"] <- wild_animals[a]["quantity"] + newborns;
	        }
	    }
	}
	
	action natural_mortality_animals {
	    loop a over: wild_animals.keys {
	        if wild_animals[a]["quantity"] > 0 {
	            float deaths <- round(wild_animals[a]["quantity"] * wild_animals[a]["mortality_rate"]);
	            wild_animals[a]["quantity"] <- max(0, wild_animals[a]["quantity"] - deaths);
	        }
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
			
			// reset des animaux chassés
			hunted_animals <- 0;
			hunted_animals_kg <- 0.0;
		}
		
		
		
		bool produce(map<string,float> demand){
			bool ok <- true;
			loop c over: demand.keys{
				if(c = "kg_meat" or c = "kg_vegetables" or c = "kg_cotton"){
					//production_output_inputs_A[c]["km/kg_scale_2"] <- distance * demand[c];
					
					// on multiplie la demande par 6800 car on est à 10000 personnes sauf pour le coton
					float from_stock <- 0.0;
					ask one_of(agricultural){
						from_stock <- get_stock_to_consume(c, demand[c]);
					}
					float to_produce <- demand[c] - from_stock;
					float augmented_demand <- to_produce * (1 + overproduction_factor);
					
					
					if(c = "kg_meat"){ // pas de ressources utilisées dans le cas de la chasse ?
						do hunting(augmented_demand); // ou juste to_produce et surproduction que pour l'élevage?
						tick_production[c] <- tick_production[c] + hunted_animals_kg;
						augmented_demand <- augmented_demand - hunted_animals_kg;
						write "Kg ciande chassée : " + hunted_animals_kg;
						write "Kg Viande à produire : " + augmented_demand;
						//float kg_hunted_animals <- hunted_animals * weight_wilds_animals;
						//tick_production[c] <- tick_production[c] + kg_hunted_animals;
						//augmented_demand <- augmented_demand - kg_hunted_animals;
					}
					
					loop u over: production_inputs_A{
						
						float quantity_needed; // quantify the resources consumed/emitted by this demand
						
						if(external_producers.keys contains u){ // if there is a known external producer for this product/good
						
							// on envoie spécifiquement JUSTE la demande
							if(u = "km/kg_scale_2"){
								quantity_needed <- production_output_inputs_A[c][u] * demand[c];
																
								tick_resources_used[u] <- tick_resources_used[u] + quantity_needed; 
								bool av <- external_producers[u].producer.produce([u::quantity_needed]); // ask the external producer to product the required quantity
								if not av{
									ok <- false;
								}
								
								continue;
							}
							
							// mais on produit la quantité nécessaire ET supplémentaire
							quantity_needed <- production_output_inputs_A[c][u] * augmented_demand;
														
							// allouer seulement l'espace nécessaire sans l'espace déjà à nous
							if(u = "m² land"){
								// dans tous cas on a au minimum la surface déjà allouée
								tick_resources_used[u] <- tick_resources_used[u] + surface_production_A[c];
								
								if(quantity_needed > surface_production_A[c]){
									quantity_needed <- quantity_needed - surface_production_A[c];
									
									// ici on part du principe que la surface est toujours donnée (à voir comment modifier ça plus tard)
									surface_production_A[c] <- surface_production_A[c] + quantity_needed;
								} else { // sinon on en a assez et on ne fait aucune demande
									continue;
								}
							}
							
							tick_resources_used[u] <- tick_resources_used[u] + quantity_needed; 
							bool av <- external_producers[u].producer.produce([u::quantity_needed]); // ask the external producer to product the required quantity
							if not av{
								ok <- false;
							}
						}
					}
	
					loop e over: production_emissions_A{ // apply emissions
						float quantity_emitted <- production_output_emissions_A[c][e] * augmented_demand;
						tick_emissions[e] <- tick_emissions[e] + quantity_emitted;
						do send_ges_to_ecosystem(tick_emissions[e]);
					}
					tick_production[c] <- tick_production[c] + augmented_demand;
				
				}
			}
			return ok;
		}
		
		action hunting(float demand){
			float kg_animal_to_hunt <- demand * hunting_over_farm;
			write "Kg viande À chasser : " + kg_animal_to_hunt;
			float total_hunted_kg <- 0.0;
			// s'il y a assez d'animaux pour la chasse on l'effectue, sinon pas de chasse
			
			loop a over:wild_animals.keys{
				if(total_hunted_kg >= kg_animal_to_hunt){
					break;
				}
				
				map<string, float> data <- wild_animals[a];
				float max_huntable_kg <- data["quantity"] * data["kg_per_animal"] * data["hunting_rate"];
				float to_hunt_kg <- min(kg_animal_to_hunt - total_hunted_kg, max_huntable_kg);
				
				if to_hunt_kg > 0{
					data["quantity"] <- max(0, data["quantity"] - round(to_hunt_kg / data["kg_per_animal"])); // ou ne pas mettre le max
					total_hunted_kg <- total_hunted_kg + to_hunt_kg;
					hunted_animals <- hunted_animals + round(to_hunt_kg / data["kg_per_animal"]);
					//write "DATA QUANTITY : " + data["quantity"];
					//write "WILD ANIMAL QUANTITY : " + wild_animals[a]["quantity"];
				}
			}
			hunted_animals_kg <- total_hunted_kg;
			/*if(wilds_animals > hunting_proportion){
				// calcul des animaux sauvages restants et ceux chassés
				wilds_animals <- wilds_animals - hunting_proportion;
				hunted_animals <- hunting_proportion;
			}
			
			// calcul de la reproduction des animaux sauvages
			//wilds_animals <- wilds_animals + int((wilds_animals/3) * animals_reproduction * nb_per_litters); // wilds_animals / 3 pour symboliser les femelles
			wilds_animals <- int(wilds_animals * (1 + animals_reproduction));*/
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
		    loop c over: indivudual_consumption_A.keys{
		    	if(c != "kg_cotton"){
		    		consumed[c] <- consumed[c]+ (indivudual_consumption_A[c] * nb_humans);
		    	}
		    }
		    // comme on ne considère pas la pénurie en macro, on peut mettre ici ce que chaque humain consomme
		    // en micro, faudra le mettre dans population activity avec la fonction produce qui renverra la vraie quantité
		    // h.vegetables <- consumed["kg_vegetables"];
		    // h.meat <- consumed["kg_meat"];
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
	
	parameter "Taux végétariens" var:vegetarian_proportion min:0.0 max:1.0;
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
			chart "Resources usage" type: series size: {0.5,0.5} position: {0, 0.5} {
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
			chart "Surface production" type: series size: {0.5,0.5} position: {1, 0.5} {
			    loop s over: production_outputs_A{
			    	data s value: surface_production_A[s];
			    }
			}
			chart "Chasse" type: series size: {0.5,0.5} position: {0, 1} {
				loop a over:wild_animals.keys{
					data a value: wild_animals[a]["quantity"];
			    }
			}
	    }
	}
}