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
     * WATER STOCK & REGENERATION
     */    
     
    // Water stock
    float initial_water_stock_l <- 2.10e14;  									
    float water_stock_l <- initial_water_stock_l;
    float water_max_stock_l <- initial_water_stock_l; 								
    
    // Monthly production
    float monthly_water_regeneration <- 1.75e13;
    
    
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
    
    
    action tick(list<human> pop) {
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

    
    /**
     * Regeneration
     * Monthly production of renewable resources
     */
    action regenerate_resources {
    	
        // Water regeneration : constant amount per month
        water_stock_l <- min(water_stock_l + monthly_water_regeneration, water_max_stock_l);        
        
        // Wood regeneration : constant amount per month 
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
    action receive_ges_emissions(float emissions_gCO2e) {
    	ges_stock <- ges_stock + (emissions_gCO2e / 1000000.0);  // Convert gCO2e to kg
    	tick_ges_received_eco["total"] <- tick_ges_received_eco["total"] + emissions_gCO2e;
	}
    
    action collect_last_tick_data{
        if(cycle > 0){
            tick_production_eco <- producer.get_tick_outputs_produced();
            tick_resources_used_eco <- producer.get_tick_inputs_used();
            tick_emissions_eco <- producer.get_tick_emissions();
            
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
        
        
        map<string,unknown> produce(map<string,float> demand){
            bool ok <- true;
            
            // WATER
            if("L water" in demand.keys){
                float water_requested_l <- demand["L water"];
                if(water_requested_l <= water_stock_l){
                    water_stock_l <- water_stock_l - water_requested_l;
                    tick_production["L water"] <- tick_production["L water"] + water_requested_l;
                } else {
                    ok <- false;
                    // tick_production["L water"] <- tick_production["L water"] + water_stock;
                    // water_stock <- 0.0;
                }
            }
            
            // LAND
            if("m² land" in demand.keys){
                float land_requested <- demand["m² land"];
                
                if(land_requested <= land_stock){
                    land_occupied <- land_occupied + land_requested;
                    land_stock <- land_stock - land_requested;
                    tick_production["m² land"] <- tick_production["m² land"] + land_requested;
                } else {
                    ok <- false;
                    // tick_production["m² land"] <- tick_production["m² land"] + land_stock;
                    // land_occupied <- land_occupied + land_stock;
                    // land_stock <- 0.0;
                }
            }
            
            // WOOD
            if("kg wood" in demand.keys){
                float wood_requested <- demand["kg wood"];
                if(wood_requested <= wood_stock_kg){
                    wood_stock_kg <- wood_stock_kg - wood_requested;
                    tick_production["kg wood"] <- tick_production["kg wood"] + wood_requested;
                } else {
                    ok <- false;
                    // tick_production["kg wood"] <- tick_production["kg wood"] + wood_stock;
                    // wood_stock <- 0.0;
                }
            }
            
            map<string, unknown> prod_info <- [
            	"ok"::ok
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
        display Ecosystem_information {
            
            // Water stock evolution
            chart "Water stock (Liters)" type: series size: {0.5,0.5} position: {0, 0} {
                data "Stock" value: water_stock_l;
                data "Max available" value: water_max_stock_l;
            }
            
            // Wood stock evolution
            chart "Wood stock (kg)" type: series size: {0.5,0.5} position: {0.5, 0} {
                data "Stock" value: wood_stock_kg;
                data "Max" value: wood_max_stock_kg;
            }
            
            // Land usage
            chart "Land occupation (m²)" type: series size: {0.5,0.5} position: {0, 0.5} {
                data "Occupied" value: land_occupied;
                data "Available" value: land_stock;
            }
            
            // GES stock and absorption : bugged kinda, not every execution show the correct thing
            chart "GES balance (kg CO2e)" type: series size: {0.5,0.5} position: {0.5, 0.5} {
                data "GES in atmosphere" value: ges_stock;
            }
        }
    }
}