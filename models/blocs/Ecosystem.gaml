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
    list<string> production_inputs_E_eco <- [];  									// Ecosystem doesn't consume to produce
    list<string> production_outputs_E_eco <- ["L water", "m² land", "kg wood"];
	list<string> production_emissions_E_eco <- [];  								// Ecosystem doesn't emit directly
    
    
    /*
     * WATER STOCK & REGENERATION
     */    
     
    // Water stock
    float initial_water_stock <- 1000000000000.0;  									// L -> 1 trillion liters (France's total water resources)
    float water_stock <- initial_water_stock;
    float water_max_stock <- initial_water_stock; 									// Can't exceed total available
    
    // Monthly production
    float monthly_rainfall <- 50000000000.0;  										// L/month (constant)
    float water_regeneration_rate <- 0.05;    										// 5% of INITIAL stock per month (NOT compound!)
    
    
    /*
     * WOOD STOCK & REGENERATION
     */
    
    // Forest area
    float total_forest_area_hectares <- 17000000.0;  								// ha
    float total_forest_area_m2 <- total_forest_area_hectares * 10000.0;  			// Convert to m²
    
    // Wood growth per hectare per month
    float wood_growth_kg_per_m2_per_year <- 0.5;  									// kg/m²/year
    float wood_growth_kg_per_m2_per_month <- wood_growth_kg_per_m2_per_year / 12.0;
    
    // Initial wood stock
    float initial_wood_stock <- 50000000000.0;  										// kg (estimated exploitable wood)
    float wood_stock <- initial_wood_stock;
    float wood_max_stock <- initial_wood_stock;
    
    
    /*
     * LAND STOCK
     */
    
    float total_land_france_m2 <- 543940000000.0; 									// 543,940 km² in m²
    float land_protected <- total_land_france_m2 * 0.28;							// 28% (152 303km²) of the total land in m²
    float land_stock <- total_land_france_m2 - land_protected - total_forest_area_m2;					// Initially all available
    float land_occupied <- 0.0;  													// Track cumulative occupation
    
    
    /*
     * GES STOCK & ABSORPTION
     */
    
    // GES stock (accumulates in atmosphere)
    float ges_stock <- 0.0;  														// Starts at 0 (no historical emissions)
    
    // Absorption coefficients (per month)
    float ges_absorption_per_m2_forest_per_month <- 0.0001;  						// kg CO2e/m²/month
    float ges_absorption_per_m2_water_per_month <- 0.00005;  						// kg CO2e/m²/month
    
    // Estimate water bodies area in France (~5% of land)
    float water_bodies_area_m2 <- total_land_france_m2 * 0.05;						// m²
    float forest_area_managed_m2 <- total_forest_area_m2;  							// 17M ha
    
    
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
        float monthly_water_production <- monthly_rainfall + (initial_water_stock * water_regeneration_rate);
        water_stock <- min(water_stock + monthly_water_production, water_max_stock);
        
        // Wood regeneration : forest_area * growth_per_m2_per_month
        float monthly_wood_growth <- total_forest_area_m2 * wood_growth_kg_per_m2_per_month;
        wood_stock <- min(wood_stock + monthly_wood_growth, wood_max_stock);
        
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
        
        
        bool produce(map<string,float> demand){
            bool all_available <- true;
            
            // WATER
            if("L water" in demand.keys){
                float water_requested <- demand["L water"];
                if(water_requested <= water_stock){
                    water_stock <- water_stock - water_requested;
                    tick_production["L water"] <- tick_production["L water"] + water_requested;
                } else {
                    all_available <- false;
                    tick_production["L water"] <- tick_production["L water"] + water_stock;
                    water_stock <- 0.0;
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
                    all_available <- false;
                    tick_production["m² land"] <- tick_production["m² land"] + land_stock;
                    land_occupied <- land_occupied + land_stock;
                    land_stock <- 0.0;
                }
            }
            
            // WOOD
            if("kg wood" in demand.keys){
                float wood_requested <- demand["kg wood"];
                if(wood_requested <= wood_stock){
                    wood_stock <- wood_stock - wood_requested;
                    tick_production["kg wood"] <- tick_production["kg wood"] + wood_requested;
                } else {
                    all_available <- false;
                    tick_production["kg wood"] <- tick_production["kg wood"] + wood_stock;
                    wood_stock <- 0.0;
                }
            }
            
            // RECEIVE GES from other blocs
            if("gCO2e emissions" in demand.keys){
                float ges_emitted <- demand["gCO2e emissions"];
                ges_stock <- ges_stock + (ges_emitted / 1000000.0);  // Convert gCO2e to kg
                tick_ges_received_eco["total"] <- ges_emitted;
            }
            
            return all_available;
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
                data "Stock" value: water_stock;
                data "Max available" value: water_max_stock;
            }
            
            // Wood stock evolution
            chart "Wood stock (kg)" type: series size: {0.5,0.5} position: {0.5, 0} {
                data "Stock" value: wood_stock;
                data "Max" value: wood_max_stock;
            }
            
            // Land usage
            chart "Land occupation (m²)" type: series size: {0.5,0.5} position: {0, 0.5} {
                data "Occupied" value: land_occupied;
                data "Available" value: land_stock;
            }
            
            // GES stock and absorption
            chart "GES balance (kg CO2e)" type: series size: {0.5,0.5} position: {0.5, 0.5} {
                data "GES in atmosphere" value: ges_stock;
            }
        }
    }
}