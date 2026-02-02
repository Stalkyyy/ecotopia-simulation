/**
* Name: Ecosystem
* Manages natural resources: water, wood, land, and GES absorption
* Author: Enzo Pinho Fernandes
* Tags: 
*/

model Ecosystem
import "../API/API.gaml"


/*
 * Ecosystem bloc
 * Manages stocks of renewable and non-renewable resources
 */

global {
    
    /*
     * Setup
     */
    list<string> production_inputs_E_eco <- [];  								
    list<string> production_outputs_E_eco <- ["L water", "m² land", "kg wood"];
	list<string> production_emissions_E_eco <- [];  
	
	
	/*
	 * TIME AND SEASONS
	 */	
	 int month <- 0;
	 int year <- 0;
	 string season <- "winter"; 		
    
    
    /*
     * WATER STOCK & REGENERATION
     */    
     
    // Water stock
    float initial_water_stock_l <- 2.10e14;  									
    float water_stock_l <- initial_water_stock_l;
    float water_max_stock_l <- initial_water_stock_l; 								
    
    // Monthly production / Seasonal production
    float monthly_water_regeneration <- 1.75e13;
    float annual_water_regeneration <- 2.08e14;
    map<string, float> monthly_seasonal_water_regeneration <- [
    	"winter"::(0.48 * annual_water_regeneration) / 3,
    	"spring"::(0.1 * annual_water_regeneration) / 3, 
    	"summer"::(0.02 * annual_water_regeneration) / 3,
    	"autumn"::(0.4 * annual_water_regeneration) / 3
    ];
    
    map<string, float> water_used_by_bloc <- ["agriculture"::0.0, "energy"::0.0, "transport"::0.0, "urbanism"::0.0, "population"::0.0];
	map<string, float> water_used_by_bloc_tick <- ["agriculture"::0.0, "energy"::0.0, "transport"::0.0, "urbanism"::0.0, "population"::0.0];
	float received_water <- 0.0;
    
    
    /*
     * WOOD STOCK & REGENERATION
     */
    
    // Forest area
    float total_forest_area_m2 <- 1.77e11;  			
    
    // Monthly wood growth in kg
    float monthly_wood_growth_kg <- 3.66e9;										
    
    // Initial wood stock in kg
    float initial_wood_stock <- 1.55e12;  							
    float wood_stock_kg <- initial_wood_stock;
    float wood_max_stock_kg <- initial_wood_stock;
    
    
    /*
     * LAND STOCK
     */
     
    float total_land_france_m2 <- 5.4394e11; 										
    float land_protected <- total_land_france_m2 * 0.28;	// 28% of the total land in m²
    float land_stock <- total_land_france_m2 - land_protected - total_forest_area_m2;	
    float land_occupied <- 0.0; 
    
    map<string, float> land_used_by_bloc <- ["agriculture"::0.0, "energy"::0.0, "urbanism"::0.0];
	map<string, float> land_used_by_bloc_tick <- ["agriculture"::0.0, "energy"::0.0, "urbanism"::0.0];
    
    
    /*
     * WILDLIFE & HUNTING
     */
    float wildlife_population <- 9500000;						// total population of hunted species
	float wildlife_capacity <- 10000000;						// max capacity
	float wildlife_birth_rate <- 0.15;      					// per month
	float wildlife_mortality_rate <- 0.02;						// natural death, per month
	float wildlife_hunted_this_tick <- 0.0;
	float wildlife_hunted_last_tick <- 0.0; 														
    
    
    /*
     * GES STOCK & ABSORPTION
     */
    
    // GES stock (accumulates in atmosphere)
    float ges_stock <- 0.0;  									// Starts at 0 (no historical emissions)
    
    // Absorption coefficients (per month)
    float ges_absorption_per_m2_forest_per_month <- 0.0174; 	// kg CO2e/m²/month
    float ges_absorption_per_m2_water_per_month <- 0.002; 		// kg CO2e/m²/month
    
    // Estimate water bodies area in France (~5% of land)
    float water_bodies_area_m2 <- total_land_france_m2 * 0.05;						
    float forest_area_managed_m2 <- total_forest_area_m2;  		
    
    map<string, float> ges_by_bloc <- ["agriculture"::0.0, "energy"::0.0, "transport"::0.0, "urbanism"::0.0];
	map<string, float> ges_by_bloc_tick <- ["agriculture"::0.0, "energy"::0.0, "transport"::0.0, "urbanism"::0.0];					
    
    
    /*
     * Counters and stats
     */
    map<string, float> tick_production_eco <- [];
    map<string, float> tick_resources_used_eco <- [];
    map<string, float> tick_emissions_eco <- [];
    map<string, float> tick_ges_received_eco <- [];  // From other blocs
    map<string, float> tick_ges_absorbed_eco <- [];
    
    
    init{ 
        if (length(coordinator) = 0){
            error "Coordinator agent not found. Ensure you launched the experiment from the Main model";
        }
    }
}





/**
 * Ecosystem bloc - Main coordination species
 * Manages aggregated natural resources and stocks
 * Implements API methods for integration with coordinator
 */
species ecosystem parent:bloc {
    string name <- "ecosystem";
        
    ecosystem_producer producer <- nil;
    ecosystem_consumer consumer <- nil;
    
    action setup{
        list<ecosystem_producer> producers <- [];
        list<ecosystem_consumer> consumers <- [];
        create ecosystem_producer number:1 returns:producers;
        create ecosystem_consumer number:1 returns:consumers;
        producer <- first(producers);
        consumer <- first(consumers);
    }
    
    
    action tick(list<human> pop, list<mini_ville> cities) {
    	write water_used_by_bloc_tick;
    	do update_wildlife_population();
    	do update_time_and_season();
        do regenerate_resources();
        do absorb_ges();
        do collect_last_tick_data();
    }
    
    production_agent get_producer{
        return producer;
    }

    list<string> get_output_resources_labels{
        return production_outputs_E_eco;
    }
    
    list<string> get_input_resources_labels{
        return production_inputs_E_eco;
    }
    
    action set_external_producer(string product, bloc bloc_agent){
        // Ecosystem doesn't consume from other blocs
    }
    
    
    /*
     * Update time (months and year) and season
     */
     action update_time_and_season{
     	month <- (month + 1) mod 12;
     	if (month = 0){
     		year <- year + 1;
     	}
     	
     	if month in [11, 0, 1]{			// Dec, Jan, Feb -> Winter
     		season <- "winter";
     	} else if month in [2, 3, 4]{	// Mar, Apr, May -> Spring
     		season <- "spring";
     	} else if month in [5, 6, 7]{	// June, July, Aug -> Summer
     		season <- "summer";
     	} else {						// Sept, Oct, Nov -> Autumn
     		season <- "autumn";
     	}
     }
     
     
     
     /**
     * Wildlife population evolution and hunting
     */
    action update_wildlife_population {
	    float births <- wildlife_birth_rate * wildlife_population * (1 - wildlife_population / wildlife_capacity);
	    float deaths <- wildlife_mortality_rate * wildlife_population;
	
	    wildlife_population <- wildlife_population 
	                            + births 
	                            - deaths 
	                            - wildlife_hunted_this_tick;
	
	    wildlife_population <- max(0.0, wildlife_population);
	    wildlife_hunted_this_tick <- 0.0; // reset
	}
	
	action hunt_request(float requested){
		float max_hunt_per_month <- 38000000.0 / 12.0;
	    float sustainable_hunt <- min(wildlife_population * 0.02, max_hunt_per_month); 
	    float allowed <- min(requested, sustainable_hunt);
	
	    wildlife_hunted_this_tick <- wildlife_hunted_this_tick + allowed;
	    wildlife_hunted_last_tick <- allowed;
	
	    return allowed;
	}
    

    
    /**
     * Regeneration
     * Monthly production of renewable resources
     */
    action regenerate_resources {
    	
        // Water regeneration : constant amount per month
        //water_stock_l <- min(water_stock_l + monthly_water_regeneration, water_max_stock_l);  
        float effective_water_regeneration <- monthly_seasonal_water_regeneration[season];
        water_stock_l <- min(water_stock_l + effective_water_regeneration, water_max_stock_l);
        
        // Wood regeneration : constant amount per month
        //TODO: wood regenration according seasons and precipitations
        wood_stock_kg <- min(wood_stock_kg + monthly_wood_growth_kg, wood_max_stock_kg);
        
        // Land: no regeneration (only tracking what's occupied)
        // land_stock decreases as land_occupied increases
    }
    
    
    /**
     * GES absoption
     * Monthly absorption by forests and water bodies
     */
    action absorb_ges {
        float monthly_absorption_forests <- forest_area_managed_m2 * ges_absorption_per_m2_forest_per_month;
        float monthly_absorption_water <- water_bodies_area_m2 * ges_absorption_per_m2_water_per_month;
        float total_absorption <- monthly_absorption_forests + monthly_absorption_water;
        
        ges_stock <- max(0.0, ges_stock - total_absorption);
        tick_ges_absorbed_eco["forests"] <- monthly_absorption_forests;
        tick_ges_absorbed_eco["water"] <- monthly_absorption_water;
    }
    
    /*
     * Receive GES emited from other blocs
     */
    action receive_ges_emissions(string bloc_name, float emissions_gCO2e) {
    	ges_stock <- ges_stock + (emissions_gCO2e / 1000000.0);  // Convert gCO2e to kg
    	tick_ges_received_eco["total"] <- tick_ges_received_eco["total"] + emissions_gCO2e;
    	
    	if !(bloc_name in ges_by_bloc.keys) {
	        ges_by_bloc[bloc_name] <- 0.0;
	    }
	    if !(bloc_name in ges_by_bloc_tick.keys) {
	        ges_by_bloc_tick[bloc_name] <- 0.0;
	    }
    
    	// Cumul global
    	ges_by_bloc[bloc_name] <- ges_by_bloc[bloc_name] + (emissions_gCO2e / 1000000.0);

	    // Tick courant (pour affichage)
	    ges_by_bloc_tick[bloc_name] <- ges_by_bloc_tick[bloc_name] + (emissions_gCO2e / 1000000.0);
	}
	
	/*
     * Receive water reinjected by other blocs (e.g. cooling water from energy production)
     */
    action receive_water_reinjection(float water_l) {
        water_stock_l <- min(water_stock_l + water_l, water_max_stock_l);
        received_water <- received_water + water_l;
    }
    
    action collect_last_tick_data{
        if(cycle > 0){
            tick_production_eco <- producer.get_tick_outputs_produced();
            tick_resources_used_eco <- producer.get_tick_inputs_used();
            tick_emissions_eco <- producer.get_tick_emissions();
            ges_by_bloc_tick <- ["agriculture"::0.0, "energy"::0.0, "transport"::0.0, "urbanisme"::0.0];
            water_used_by_bloc_tick <- ["agriculture"::0.0, "energy"::0.0, "transport"::0.0, "urbanisme"::0.0, "population"::0.0];
            land_used_by_bloc_tick <- ["agriculture"::0.0, "energy"::0.0, "urbanism"::0.0];
            
            ask ecosystem_producer{
                do reset_tick_counters;
            }
        }
    }
    
    
    
    
    
    /**
     * Ecosystem producer
     * Allocates resources to requesting blocs
     */
    species ecosystem_producer parent:production_agent {
        map<string, bloc> external_producers;
        
        map<string, float> tick_resources_used <- [];
        map<string, float> tick_production <- [];
        map<string, float> tick_emissions <- [];
        
        map<string, float> get_tick_inputs_used		{ return tick_resources_used; }
        map<string, float> get_tick_outputs_produced	{ return tick_production; }
        map<string, float> get_tick_emissions		{ return tick_emissions; }
        
        action reset_tick_counters{
            tick_resources_used <- [];
            tick_production <- ["L water"::0.0, "m² land"::0.0, "kg wood"::0.0];
            tick_emissions <- [];
        }
        
        
        map<string,unknown> produce(string bloc_name, map<string,float> demand){
            bool ok <- true;
            float transmitted_water <- 0.0;
            float transmitted_land <- 0.0;
            float transmitted_wood <- 0.0;
            
            // WATER
            if("L water" in demand.keys){
                float water_requested_l <- demand["L water"];
                if(water_requested_l > water_stock_l){
                    ok <- false;
                }
                
                
                transmitted_water <- min(water_requested_l, water_stock_l);
                                
                water_stock_l <- water_stock_l - transmitted_water;
                tick_production["L water"] <- tick_production["L water"] + transmitted_water;
                
                water_used_by_bloc[bloc_name] <- water_used_by_bloc[bloc_name] + transmitted_water;
		        water_used_by_bloc_tick[bloc_name] <- water_used_by_bloc_tick[bloc_name] + transmitted_water;
            }
            
            // LAND
            if("m² land" in demand.keys){
                float land_requested <- demand["m² land"];
                if(land_requested > land_stock){
                    ok <- false;
                }
                
                transmitted_land <- min(land_requested, land_stock);
                
                land_occupied <- land_occupied + transmitted_land;
                land_stock <- land_stock - transmitted_land;
                tick_production["m² land"] <- tick_production["m² land"] + transmitted_land;
                
                land_used_by_bloc[bloc_name] <- land_used_by_bloc[bloc_name] + transmitted_land;
		        land_used_by_bloc_tick[bloc_name] <- land_used_by_bloc_tick[bloc_name] + transmitted_land;
            }
            
            // WOOD
            if("kg wood" in demand.keys){
                float wood_requested <- demand["kg wood"];
                if(wood_requested > wood_stock_kg){
                    ok <- false;
                }
                
                transmitted_wood <- min(wood_requested, wood_stock_kg);
                
                wood_stock_kg <- wood_stock_kg - transmitted_wood;
                tick_production["kg wood"] <- tick_production["kg wood"] + transmitted_wood;
            }
            
            map<string, unknown> prod_info <- [
            	"ok"::ok,
            	"transmitted_water"::transmitted_water,
            	"transmitted_land"::transmitted_land,
            	"transmitted_wood"::transmitted_wood
            ];
            
            return prod_info;
        }
        
        action set_supplier(string product, bloc bloc_agent){
            // Ecosystem doesn't have suppliers
        }
    }
    
    
    
    
    
    /**
     * Ecosystem consumer
     * Placeholder because ecosystem doesn't consume
     */
    species ecosystem_consumer parent:consumption_agent{
        map<string, float> consumed <- [];
        
        map<string, float> get_tick_consumption{
            return copy(consumed);
        }
        
        init{
            // Ecosystem doesn't consume anything
        }
        
        action reset_tick_counters{
            // Nothing to reset
        }
        
        /**
         * Consume action (required by API, but ecosystem doesn't consume)
         */
        action consume(human h){
            // Ecosystem doesn't consume anything from humans
        }
    }
}





/**
 * Ecosystem experiments and displays
 */
experiment run_ecosystem type: gui {
	
	
    output {
    	monitor "Month" value: month;
		monitor "Year" value: year;
		monitor "Season" value: season;
		monitor "Water regen (L/month)" value: monthly_seasonal_water_regeneration[season];
    
        display Ecosystem_information {
            /*
             * ROW 1
             */
            // Water stock evolution
            chart "Water stock (Liters)" type: series size: {0.25, 0.25} position: {0.0, 0.0} y_log_scale:true {
                data "Stock" value: water_stock_l;
                data "Max available" value: water_max_stock_l;
            }
            
            chart "Water consumption by bloc per tick (L / month)" type: series size: {0.25, 0.25} position: {0.25, 0.0} y_log_scale:true {
			    loop b over: water_used_by_bloc_tick.keys {
			        data b value: water_used_by_bloc_tick[b];
			    }
			}
			
			chart "Cumulative water consumption by bloc (L / month)" type: series size: {0.25, 0.25} position: {0.50, 0.0} y_log_scale:true {
			    loop b over: water_used_by_bloc.keys {
			        data b value: water_used_by_bloc[b];
			    }
			}
			
			// Cumulative reinjected water
            chart "Cumulative water reinjected (L)" type: series size: {0.25,0.25} position: {0.75, 0.0} {
			    data "Reinjected water" value: received_water;
			}
            
            
            /*
             * ROW 2
             */
            // Land usage
            chart "Land occupation (m²)" type: series size: {0.25, 0.25} position: {0.0, 0.25} {
                data "Occupied" value: land_occupied;
                data "Available" value: land_stock;
            }
            
            chart "Land occupation by bloc per tick (m²)" type: series size: {0.25, 0.25} position: {0.25, 0.25} {
			    loop b over: land_used_by_bloc_tick.keys {
			        data b value: land_used_by_bloc_tick[b];
			    }
			}
			
			chart "Cumulative land occupation by bloc (m²)" type: series size: {0.25, 0.25} position: {0.50, 0.25} {
			    loop b over: land_used_by_bloc.keys {
			        data b value: land_used_by_bloc[b];
			    }
			}
            
            
            /*
             * ROW 3
             */
            // GES stock and absorption : bugged kinda, not every execution show the correct thing
            chart "GES balance (kg CO2e)" type: series size: {0.25, 0.25} position: {0.0, 0.40} {
                data "GES in atmosphere" value: ges_stock;
            }
            
            chart "GES emissions by bloc per tick (kg CO2e / month)" type: series size: {0.25, 0.25} position: {0.25, 0.50} y_log_scale:true {
			    loop b over: ges_by_bloc_tick.keys {
			        data b value: ges_by_bloc_tick[b];
			    }
			}
			
			chart "Cumulative GES emissions by bloc (kg CO2e)" type: series size: {0.25, 0.25} position: {0.50, 0.50} y_log_scale:true {
			    loop b over: ges_by_bloc.keys {
			        data b value: ges_by_bloc[b];
			    }
			}
			
			/*
             * ROW 4
             */
			// Wood stock evolution
            chart "Wood stock (kg)" type: series size: {0.25, 0.25} position: {0.0, 0.75} {
                data "Stock" value: wood_stock_kg;
                data "Max" value: wood_max_stock_kg;
            }
            
            
            // Wildlife population
            chart "Wildlife population" type: series size: {0.25, 0.25} position: {0.25, 0.75} {
			    data "Population animale" value: wildlife_population;
			    data "Capacité écologique" value: wildlife_capacity;
			}
			
			// Proportion hunted animals
			chart "Wildlife hunting pressure" type: series size: {0.25, 0.25} position: {0.50, 0.75} {
			    data "Animaux chassés" value: wildlife_hunted_last_tick;
			}
        }
    }
}
