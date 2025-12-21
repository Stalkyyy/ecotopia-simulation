/**
* Name: Urbanism bloc (MOSIMA)
* Authors: team A MOSIMA
*/

model Urbanism

import "../API/API.gaml"

/* 
 * Macroscale urbanism bloc.
 * Tracks aggregated housing stock (wood vs modular), capacity, surface, and resource needs.
 * Later micro features (families, matching, degradation) can extend this scaffold.
 */
global{
	/* Setup */
	list<string> housing_types <- ["wood", "modular"];
	map<string, int> init_units <- ["wood"::1700, "modular"::1700];
	map<string, float> capacity_per_unit <- ["wood"::3.0, "modular"::2.5]; // persons per unit
	map<string, float> surface_per_unit <- ["wood"::80.0, "modular"::60.0]; // m2 per unit
	
	// Resource needs per unit (defaults, to be refined with data)
	map<string, float> resource_per_unit_wood <- ["kg wood"::24000.0, "kWh energy"::500.0]; // assume ~800 kg/m3 -> 30 m3 -> 24 000 kg
	map<string, float> resource_per_unit_modular <- ["kg_cotton"::30000.0, "kWh energy"::400.0];
	
	float target_occupancy_rate <- 0.95; // aim for ~95% occupancy
	int max_units_per_tick <- 5; // build rate cap (scaled to represented population)
	float constructible_surface_total <- 1e9; // fallback surface cap (replaced by ecosystem land_stock when available)
	float available_land_from_ecosystem <- constructible_surface_total; // synced each tick from ecosystem
	float population_scaling_factor <- 6700.0; // how many real people a human agent represents
	
	/* State */
	int population_count <- 0; // last observed population size (for charts)
	float population_scaled <- 0.0; // scaled population for charts/consistency
	map<string, int> units <- copy(init_units);
	map<string, float> tick_resources_used <- ["kg wood"::0.0, "kg_cotton"::0.0, "kWh energy"::0.0, "m² land"::0.0];
	map<string, int> tick_constructions <- ["wood"::0, "modular"::0];
	map<string, float> tick_constructions_scaled <- ["wood"::0.0, "modular"::0.0];
	float surface_used -> {sum(housing_types collect (surface_per_unit[each] * units[each]))};
	float surface_used_scaled -> {surface_used * population_scaling_factor};
	float total_capacity -> {sum(housing_types collect (capacity_per_unit[each] * units[each]))};
	float total_capacity_scaled_state <- 0.0; // scaled capacity for charts/output
	
	init{
		// Ensure coordinator exists (experiment should be launched from Main)
		if (length(coordinator) = 0){
			error "Coordinator agent not found. Launch from Main model.";
		}
	}
}

/**
 * Bloc implementation (macroscale scaffold)
 */
species urbanism parent: bloc{
	string name <- "urbanism";
	urban_producer producer <- nil;
	
	action setup{
		list<urban_producer> producers <- [];
		create urban_producer number:1 returns: producers;
		producer <- first(producers);
	}
	
	list<string> get_input_resources_labels{
		return ["kg wood", "kg_cotton", "kWh energy", "m² land"];
	}
	
	list<string> get_output_resources_labels{
		// expose aggregate housing capacity
		return ["total_housing_capacity"];
	}
	
	action tick(list<human> pop){
		do reset_tick_counters;
		ask producer { do reset_tick_counters; }
		do sync_available_land;
		
		int occupants <- length(pop);
		population_count <- occupants;
		float occupants_scaled <- occupants * population_scaling_factor;
		population_scaled <- occupants_scaled;
		float total_capacity_scaled <- total_capacity * population_scaling_factor;
		total_capacity_scaled_state <- total_capacity_scaled;
		float desired_capacity <- occupants_scaled / target_occupancy_rate;
		float deficit <- max(0.0, desired_capacity - total_capacity_scaled);
		
		int units_needed <- ceil(deficit / average_capacity_per_unit());
		int planned_units <- min(max_units_per_tick, units_needed);
		
		if(planned_units > 0 and surface_room(planned_units)){
			int wood_plan <- floor(planned_units * 0.6);
			int modular_plan <- planned_units - wood_plan;
			
			map<string, float> demand <- compute_resource_demand(wood_plan, modular_plan);
			bool ok <- producer.produce(demand);
			
			if(ok){
				do add_units(wood_plan, modular_plan);
				tick_constructions["wood"] <- wood_plan;
				tick_constructions["modular"] <- modular_plan;
				tick_constructions_scaled["wood"] <- wood_plan * population_scaling_factor;
				tick_constructions_scaled["modular"] <- modular_plan * population_scaling_factor;
			}
		}
		
		// publish current capacity for other blocs
		ask producer {
			tick_outputs["total_housing_capacity"] <- total_capacity_scaled;
		}
		
		tick_resources_used <- producer.get_tick_inputs_used(); // collect for charts/logs
	}
	
	/* Helpers */
	float average_capacity_per_unit{
		return (sum(housing_types collect capacity_per_unit[each]) / length(housing_types));
	}
	
	map<string, float> compute_resource_demand(int wood_units, int modular_units){
		map<string, float> demand <- ["kg wood"::0.0, "kg_cotton"::0.0, "kWh energy"::0.0, "m² land"::0.0];
		float scale <- population_scaling_factor;
		demand["kg wood"] <- resource_per_unit_wood["kg wood"] * wood_units * scale;
		demand["kg_cotton"] <- resource_per_unit_modular["kg_cotton"] * modular_units * scale;
		demand["kWh energy"] <- (resource_per_unit_wood["kWh energy"] * wood_units
			+ resource_per_unit_modular["kWh energy"] * modular_units) * scale;
		demand["m² land"] <- (surface_per_unit["wood"] * wood_units + surface_per_unit["modular"] * modular_units) * scale;
		return demand;
	}
	
	bool surface_room(int planned_units){
		float planned_surface <- planned_units * (surface_per_unit["wood"] + surface_per_unit["modular"]) / 2.0; // rough avg
		return (surface_used + planned_surface) <= constructible_surface_total;
	}
	
	// Pull current land availability from ecosystem (preferred) or fall back to local cap
	action sync_available_land{
		float eco_land <- constructible_surface_total;
		if(length(ecosystem) > 0){
			ask one_of(ecosystem){
				eco_land <- land_stock;
			}
		}
		available_land_from_ecosystem <- eco_land;
		constructible_surface_total <- eco_land;
	}
	
	action add_units(int wood_units, int modular_units){
		units["wood"] <- units["wood"] + wood_units;
		units["modular"] <- units["modular"] + modular_units;
	}
	
	action reset_tick_counters{
		tick_resources_used <- ["kg wood"::0.0, "kg_cotton"::0.0, "kWh energy"::0.0, "m² land"::0.0];
		tick_constructions["wood"] <- 0;
		tick_constructions["modular"] <- 0;
	}
}

/**
 * Production handler for the urbanism bloc.
 * Requests external resources via coordinator-wired suppliers and tracks usage.
 */
species urban_producer parent: production_agent{
	map<string, bloc> external_producers <- [];
	map<string, float> tick_resources_used <- ["kg wood"::0.0, "kg_cotton"::0.0, "kWh energy"::0.0, "m² land"::0.0];
	map<string, float> tick_outputs <- []; // no tangible outputs yet
	map<string, float> tick_emissions <- []; // placeholder for future impacts
	
	init{
		do reset_tick_counters;
	}
	
	action set_supplier(string product, bloc bloc_agent){
		external_producers[product] <- bloc_agent;
	}
	
	action reset_tick_counters{
		loop r over: tick_resources_used.keys{
			tick_resources_used[r] <- 0.0;
		}
		tick_outputs["total_housing_capacity"] <- 0.0;
		total_capacity_scaled_state <- 0.0;
		tick_constructions_scaled["wood"] <- 0.0;
		tick_constructions_scaled["modular"] <- 0.0;
	}
	
	map<string, float> get_tick_inputs_used{
		return tick_resources_used;
	}
	
	map<string, float> get_tick_outputs_produced{
		return tick_outputs; // no tangible outputs (capacity is tracked in bloc state)
	}
	
	map<string, float> get_tick_emissions{
		return tick_emissions; // placeholder
	}
	
	bool produce(map<string, float> demand){
		bool ok <- true;
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
		}
		return ok;
	}
}

/**
 * Minimal experiment to visualize capacity vs population and construction activity.
 */
experiment run_urbanism type: gui {
	output {
		display Urbanism_information {
			chart "Capacity vs population" type: series size: {0.5,0.5} position: {0, 0} {
				data "capacity (scaled)" value: total_capacity_scaled_state color: #blue;
				data "population (scaled)" value: population_scaled color: #darkgray;
			}
			chart "Constructions per tick" type: series size: {0.5,0.5} position: {0.5, 0} {
				data "wood (scaled)" value: tick_constructions_scaled["wood"] color: #sienna;
				data "modular (scaled)" value: tick_constructions_scaled["modular"] color: #orange;
			}
			chart "Resource use" type: series size: {0.5,0.5} position: {0, 0.5} {
				loop r over: tick_resources_used.keys{
					data r value: tick_resources_used[r];
				}
			}
			chart "Surface saturation" type: series size: {0.5,0.5} position: {0.5, 0.5} {
				data "surface_used (scaled)" value: surface_used_scaled color: #green;
				data "constructible_surface" value: constructible_surface_total color: #black;
			}
		}
	}
}
