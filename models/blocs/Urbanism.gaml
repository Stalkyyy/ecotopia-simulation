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
	map<string, int> init_units <- ["wood"::200, "modular"::100];
	map<string, float> capacity_per_unit <- ["wood"::3.0, "modular"::2.5]; // persons per unit
	map<string, float> surface_per_unit <- ["wood"::80.0, "modular"::60.0]; // m2 per unit
	
	// Resource needs per unit (defaults, to be refined with data)
	map<string, float> resource_per_unit_wood <- ["kg wood"::24000.0, "kWh energy"::500.0]; // assume ~800 kg/m3 -> 30 m3 -> 24 000 kg
	map<string, float> resource_per_unit_modular <- ["kg_cotton"::800.0, "kWh energy"::400.0];
	
	float target_occupancy_rate <- 0.95; // aim for ~95% occupancy
	int max_units_per_tick <- 20; // build rate cap
	float constructible_surface_total <- 100000.0; // m2 available to build
	
	/* State */
	int population_count <- 0; // last observed population size (for charts)
	map<string, int> units <- copy(init_units);
	map<string, float> tick_resources_used <- ["kg wood"::0.0, "kg_cotton"::0.0, "kWh energy"::0.0, "m² land"::0.0];
	map<string, int> tick_constructions <- ["wood"::0, "modular"::0];
	float surface_used -> {sum(housing_types collect (surface_per_unit[each] * units[each]))};
	float total_capacity -> {sum(housing_types collect (capacity_per_unit[each] * units[each]))};
	
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
		// no direct outputs yet (capacity is internal state)
		return [];
	}
	
	action tick(list<human> pop){
		do reset_tick_counters;
		ask producer { do reset_tick_counters; }
		
		int occupants <- length(pop);
		population_count <- occupants;
		float desired_capacity <- occupants / target_occupancy_rate;
		float deficit <- max(0.0, desired_capacity - total_capacity);
		
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
			}
		}
		
		tick_resources_used <- producer.get_tick_inputs_used(); // collect for charts/logs
	}
	
	/* Helpers */
	float average_capacity_per_unit{
		return (sum(housing_types collect capacity_per_unit[each]) / length(housing_types));
	}
	
	map<string, float> compute_resource_demand(int wood_units, int modular_units){
		map<string, float> demand <- ["kg wood"::0.0, "kg_cotton"::0.0, "kWh energy"::0.0, "m² land"::0.0];
		demand["kg wood"] <- resource_per_unit_wood["kg wood"] * wood_units;
		demand["kg_cotton"] <- resource_per_unit_modular["kg_cotton"] * modular_units;
		demand["kWh energy"] <- resource_per_unit_wood["kWh energy"] * wood_units
			+ resource_per_unit_modular["kWh energy"] * modular_units;
		demand["m² land"] <- surface_per_unit["wood"] * wood_units + surface_per_unit["modular"] * modular_units;
		return demand;
	}
	
	bool surface_room(int planned_units){
		float planned_surface <- planned_units * (surface_per_unit["wood"] + surface_per_unit["modular"]) / 2.0; // rough avg
		return (surface_used + planned_surface) <= constructible_surface_total;
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
				data "capacity" value: total_capacity color: #blue;
				data "population" value: population_count color: #darkgray;
			}
			chart "Constructions per tick" type: series size: {0.5,0.5} position: {0.5, 0} {
				data "wood" value: tick_constructions["wood"] color: #sienna;
				data "modular" value: tick_constructions["modular"] color: #orange;
			}
			chart "Resource use" type: series size: {0.5,0.5} position: {0, 0.5} {
				loop r over: tick_resources_used.keys{
					data r value: tick_resources_used[r];
				}
			}
			chart "Surface saturation" type: series size: {0.5,0.5} position: {0.5, 0.5} {
				data "surface_used" value: surface_used color: #green;
				data "constructible_surface" value: constructible_surface_total color: #black;
			}
		}
	}
}