/**
* Name: Urbanism bloc
* Authors: team A MOSIMA
*
* Notes (2026-01):
* - Mini-ville variables (housing units, housing_capacity, buildable_area, used_buildable_area) are treated as
*   *real* aggregate quantities at the scale of the model territory (i.e., do NOT multiply them again by pop_per_ind).
* - Population is represented by a sample of human agents; Demography uses pop_per_ind to scale demands.
*   In Urbanism we therefore compare population_real (= nb_humans * pop_per_ind) against housing_capacity_real.
*/

model Urbanism

import "../API/API.gaml"

/*
 * Macroscale urbanism bloc.
 * Tracks aggregated housing stock (wood vs modular), capacity, land-use and resource needs.
 * No explicit building agents in v1: housing is aggregated inside mini-villes.
 */
global{
	/* Setup */
	list<string> housing_types <- ["wood", "modular"];
	map<string, int> init_units <- ["wood"::0, "modular"::0]; // will be synced from mini-villes

	// IMPORTANT: use the SAME surface notion as mini-villes (area_per_unit), otherwise you create fake land gaps.
	// In v1, we use a single footprint per unit. Later, you can refine per typology.
	map<string, float> surface_per_unit <- ["wood"::area_per_unit_default, "modular"::area_per_unit_default]; // m² per unit

	// Resource needs per unit (defaults, to be refined with data)
	map<string, float> resource_per_unit_wood <- ["kg wood"::24000.0, "kWh energy"::7000.0]; // ~30 m3 @ 800 kg/m3
	map<string, float> resource_per_unit_modular <- ["kg_cotton"::20000.0, "kWh energy"::8000.0];

	// Monthly energy use per housing unit (kWh / month / unit)
	map<string, float> energy_use_per_unit <- ["wood"::375.0, "modular"::20.0];

	// Behavioural parameters
	float target_occupancy_rate <- 0.95;       // aim for ~95% occupancy
	float occupancy_hysteresis <- 0.01;         // avoid flip-flop around the target
	float occupancy_rate <- 0.0;             // population_real / capacity_effective
	float build_fraction_of_deficit <- 0.25;     // build only a fraction of the deficit per tick (tune)
	int max_units_per_tick <- 5000;            // CAP in *real* housing units / tick (tune later)
	int min_units_per_tick <- 0;

	// Demography scaling (must match Demography.gaml pop_per_ind)
	int pop_per_ind <- 6700;

	// CDC scaling for charts: upscale capacity/land if simulated mini-villes represent constellations
	int target_pop_per_miniville_real <- 10000;
	int nb_minivilles_sim <- 1;
	int nb_minivilles_real <- 1;
	float alpha_mv <- 1.0;
	float capacity_real_scaled <- 0.0;
	float surface_used_scaled <- 0.0;
	float remaining_buildable_scaled <- 0.0;

	/* State (for charts/logging) */
	int population_count <- 0;           // nb of human agents (sample)
	float population_real <- 0.0;        // scaled population in real persons (nb_humans * pop_per_ind)
	map<string, int> units <- copy(init_units);
	map<string, float> tick_resources_used <- ["kg wood"::0.0, "kg_cotton"::0.0, "kWh energy"::0.0, "m² land"::0.0];
	map<string, int> tick_constructions <- ["wood"::0, "modular"::0];

	// Land + capacity (REAL units)
	float surface_used -> {sum(housing_types collect (surface_per_unit[each] * units[each]))}; // m²
	float total_capacity -> {sum(housing_types collect (capacity_per_unit[each] * units[each]))}; // persons

	// Convenience mirrors for charts (keep names to avoid breaking displays)
	float total_capacity_scaled_state <- 0.0; // actually REAL capacity now
	map<string, float> tick_constructions_scaled <- ["wood"::0.0, "modular"::0.0]; // actually REAL units now

	float constructible_surface_total <- 0.0; // synced each tick as sum of remaining_buildable_area (m²)

	init{
		// safety: avoid running this bloc alone
		if (length(coordinator) = 0){
			error "Coordinator agent not found. Launch from Main model.";
		}
	}
}

/**
 * Bloc implementation
 */
species urbanism parent: bloc{
	string name <- "urbanism";
	urban_producer producer <- nil;
	bool cities_logged <- false;

	action setup{
		// initialize mini-villes near existing GIS cities when available
		list<city> cities <- (city as list<city>);
		int n <- min(mini_ville_count, length(cities));

		if(n > 0){
			loop c over: cities {
				if(n <= 0) { break; }
				create mini_ville number: 1 {
					location <- c.location;
				}
				n <- n - 1;
			}
		} else {
			create mini_ville number: mini_ville_count;
		}

		list<urban_producer> producers <- [];
		create urban_producer number: 1 returns: producers;
		producer <- first(producers);

		// Initial sync so charts don’t start at zero
		do sync_from_cities((mini_ville as list<mini_ville>));
		do sync_constructible_surface((mini_ville as list<mini_ville>));
	}

	list<string> get_input_resources_labels{
		return ["kg wood", "kg_cotton", "kWh energy", "m² land"];
	}

	list<string> get_output_resources_labels{
		// expose aggregate housing capacity (REAL persons) for Demography
		return ["total_housing_capacity"];
	}

	action tick(list<human> pop, list<mini_ville> cities){
		do reset_tick_counters;
		ask producer { do reset_tick_counters; }

		// Always sync first (single source of truth = mini-villes)
		do sync_from_cities(cities);
		do sync_constructible_surface(cities);
		// Population (REAL) — Demography uses the same scaling
		int nb_humans <- length(pop);
		population_count <- nb_humans;
		population_real <- nb_humans * pop_per_ind;

		// CDC-style scaling: if the simulated set of mini-villes represents a constellation of real mini-villes
		nb_minivilles_sim <- max(1, length(cities));
		nb_minivilles_real <- int(ceil(population_real / target_pop_per_miniville_real));
		alpha_mv <- float(nb_minivilles_real) / float(nb_minivilles_sim);

		// Capacity and land are computed from the simulated mini-villes, then scaled by alpha for comparisons to real population
		float capacity_effective <- total_capacity * alpha_mv; // persons
		capacity_real_scaled <- capacity_effective;
		surface_used_scaled <- surface_used * alpha_mv;
		remaining_buildable_scaled <- constructible_surface_total * alpha_mv;

		if(not cities_logged){
			write "urbanism received mini_villes=" + string(length(cities)) + " alpha_mv=" + string(alpha_mv);
			cities_logged <- true;
		}

		float desired_capacity <- population_real / target_occupancy_rate;
		float deficit_people <- max(0.0, desired_capacity - capacity_effective);

		// Convert deficit in persons to a number of (SIMULATED) housing units to add this tick
		int units_needed <- int(ceil(deficit_people / (average_capacity_per_unit() * alpha_mv)));
		int planned_units <- int(ceil(units_needed * build_fraction_of_deficit));
		planned_units <- min(max_units_per_tick, planned_units);
		planned_units <- max(min_units_per_tick, planned_units);

		// Hysteresis: stop building once we are comfortably below the target occupancy
		float occupancy <- population_real / max(1.0, capacity_effective);
		occupancy_rate <- occupancy;
		if(occupancy <= (target_occupancy_rate - occupancy_hysteresis)) {
			planned_units <- 0;
		}
		if(planned_units > 0 and surface_room(planned_units)){
			int wood_plan <- int(floor(planned_units * 0.6));
			int modular_plan <- planned_units - wood_plan;

			// land footprint (REAL m²)
			float planned_surface <- surface_per_unit["wood"] * wood_plan
				+ surface_per_unit["modular"] * modular_plan;

			// choose a target city that can absorb land
			mini_ville target_city <- select_city(cities, planned_surface);
			if(target_city != nil){

				map<string, float> demand <- compute_resource_demand(wood_plan, modular_plan);
				map<string, unknown> info <- producer.produce(demand);
				bool ok <- bool(info["ok"]);

				if(ok){
					write "urbanism: build " + string(planned_units) + " units (area=" + string(planned_surface)
						+ ") in mini_ville " + string(target_city.index);

					do add_units_to_city(target_city, wood_plan, modular_plan, planned_surface);

					// re-sync after modifications
					do sync_from_cities(cities);
					do sync_constructible_surface(cities);

					tick_constructions["wood"] <- wood_plan;
					tick_constructions["modular"] <- modular_plan;
					tick_constructions_scaled["wood"] <- float(wood_plan);
					tick_constructions_scaled["modular"] <- float(modular_plan);
				}
			}
		}

		// continuous energy consumption of existing housing stock (REAL kWh / tick)
		do consume_housing_energy;

		// publish capacity (REAL persons)
		ask producer {
			tick_outputs["total_housing_capacity"] <- total_capacity;
		}

		// collect for charts/logs
		tick_resources_used <- producer.get_tick_inputs_used();
	}

	action consume_housing_energy{
		float total_energy_need <- sum(housing_types collect (energy_use_per_unit[each] * units[each]));
		if(total_energy_need > 0){
			map<string, float> energy_demand <- ["kWh energy"::total_energy_need];
			// If energy is missing, producer will return ok=false; we still record demanded amounts separately if needed later
			map<string, unknown> info <- producer.produce(energy_demand);
		}
	}

	/* Helpers */
	float average_capacity_per_unit{
		return (sum(housing_types collect capacity_per_unit[each]) / length(housing_types));
	}

	map<string, float> compute_resource_demand(int wood_units, int modular_units){
		// IMPORTANT: do NOT multiply again by pop_per_ind — these are already REAL units.
		map<string, float> demand <- ["kg wood"::0.0, "kg_cotton"::0.0, "kWh energy"::0.0];

		demand["kg wood"] <- resource_per_unit_wood["kg wood"] * wood_units;
		demand["kg_cotton"] <- resource_per_unit_modular["kg_cotton"] * modular_units;
		demand["kWh energy"] <- (resource_per_unit_wood["kWh energy"] * wood_units
			+ resource_per_unit_modular["kWh energy"] * modular_units);

		return demand;
	}

	bool surface_room(int planned_units){
		float planned_surface <- planned_units * (surface_per_unit["wood"] + surface_per_unit["modular"]) / 2.0;
		return (surface_used + planned_surface) <= constructible_surface_total;
	}

	mini_ville select_city(list<mini_ville> cities, float required_area){
		if(length(cities) = 0){
			return nil;
		}
		list<mini_ville> candidates <- cities where (each.remaining_buildable_area >= required_area);
		if(length(candidates) > 0){
			return one_of(candidates);
		}
		// No city has enough remaining buildable area for the required surface: do not build this tick
		return nil;
	}

	action sync_from_cities(list<mini_ville> cities){
		int wood_total <- 0;
		int modular_total <- 0;
		loop c over: cities{
			wood_total <- wood_total + c.wood_housing_units;
			modular_total <- modular_total + c.modular_housing_units;
		}
		units["wood"] <- wood_total;
		units["modular"] <- modular_total;
	}

	action sync_constructible_surface(list<mini_ville> cities){
		// Local constraint = sum of remaining buildable areas in mini-villes
		float local_remaining <- 0.0;
		loop c over: cities{
			local_remaining <- local_remaining + c.remaining_buildable_area;
		}

		// Global constraint can also come from ecosystem land stock.
		float eco_land <- 1e18;
		if(length(ecosystem) > 0){
			ask one_of(ecosystem){
				eco_land <- land_stock; // m²
			}
		}

		constructible_surface_total <- min(local_remaining, eco_land);
	}

	action add_units_to_city(mini_ville target_city, int wood_units, int modular_units, float planned_surface){
		ask target_city{
			// Clamp to remaining buildable area to avoid negative stocks if selection fallback triggered.
			float area_per_unit_here <- area_per_unit;
			int total_units <- wood_units + modular_units;

			int max_fit <- int(floor(remaining_buildable_area / area_per_unit_here));
			int feasible <- min(total_units, max_fit);

			// keep ratio if clamped
			int wood_feasible <- int(floor(feasible * 0.6));
			int modular_feasible <- feasible - wood_feasible;

			float area_used_now <- feasible * area_per_unit_here;

			wood_housing_units <- wood_housing_units + wood_feasible;
			modular_housing_units <- modular_housing_units + modular_feasible;

			used_buildable_area <- used_buildable_area + area_used_now;
			// Report actual land consumption back to the Urbanism bloc (outside the ask scope)
			tick_resources_used["m² land"] <- tick_resources_used["m² land"] + area_used_now;
			remaining_buildable_area <- max(0.0, buildable_area - used_buildable_area);

			housing_capacity <- (wood_housing_units * capacity_per_unit["wood"])
				+ (modular_housing_units * capacity_per_unit["modular"]);
		}
	}

	action reset_tick_counters{
		tick_resources_used <- ["kg wood"::0.0, "kg_cotton"::0.0, "kWh energy"::0.0, "m² land"::0.0];
		tick_constructions["wood"] <- 0;
		tick_constructions["modular"] <- 0;
		tick_constructions_scaled["wood"] <- 0.0;
		tick_constructions_scaled["modular"] <- 0.0;
	}
}

/**
 * Production handler for the urbanism bloc.
 * Requests external resources via coordinator-wired suppliers and tracks usage.
 */
species urban_producer parent: production_agent{
	map<string, bloc> external_producers <- [];
	map<string, float> tick_resources_used <- ["kg wood"::0.0, "kg_cotton"::0.0, "kWh energy"::0.0, "m² land"::0.0];
	map<string, float> tick_outputs <- [];
	map<string, float> tick_emissions <- [];

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
	}

	map<string, float> get_tick_inputs_used{
		return tick_resources_used;
	}

	map<string, float> get_tick_outputs_produced{
		return tick_outputs;
	}

	map<string, float> get_tick_emissions{
		return tick_emissions;
	}

	map<string, unknown> produce(map<string, float> demand){
		bool ok <- true;

		loop r over: demand.keys{
			float qty <- demand[r];

			if(external_producers.keys contains r){
				map<string, unknown> info <- external_producers[r].producer.produce([r::qty]);
				if not bool(info["ok"]) {
					ok <- false;
				} else {
					// Count as used only if it was actually provided
					if(not (tick_resources_used.keys contains r)){
						tick_resources_used[r] <- 0.0;
					}
					tick_resources_used[r] <- tick_resources_used[r] + qty;
				}
			} else {
				// No supplier registered: fail explicitly
				ok <- false;
			}
		}

		return ["ok"::ok];
	}
}

/**
 * Minimal experiment to visualize capacity vs population and construction activity.
 */
experiment run_urbanism type: gui {
	output {
		display Urbanism_information {
			chart "Capacity vs population" type: series size: {0.5,0.5} position: {0, 0} {
				data "capacity (real, scaled)" value: capacity_real_scaled color: #blue;
				data "population (real)" value: population_real color: #darkgray;
			}
			chart "Constructions per tick" type: series size: {0.5,0.5} position: {0.5, 0} {
				data "wood units (scaled)" value: tick_constructions_scaled["wood"] * alpha_mv color: #sienna;
				data "modular units (scaled)" value: tick_constructions_scaled["modular"] * alpha_mv color: #orange;
			}
			chart "Resource use (provided)" type: series size: {0.5,0.5} position: {0, 0.5} {
				loop r over: tick_resources_used.keys{
					data r value: tick_resources_used[r];
				}
			}
			chart "Land saturation" type: series size: {0.5,0.5} position: {0.5, 0.5} {
				data "surface_used (scaled)" value: surface_used_scaled color: #green;
				data "remaining_buildable (scaled)" value: remaining_buildable_scaled color: #black;
			}
		}


		monitor "alpha_mv" value: alpha_mv;
		monitor "capacity_scaled" value: capacity_real_scaled;
		monitor "pop_real" value: population_real;
		monitor "housing_deficit" value: max(0.0, population_real - capacity_real_scaled);
		monitor "occupancy" value: occupancy_rate;

		display MiniVille_information {
			chart "Mini-ville capacity" type: series size: {0.5,0.5} position: {0, 0} {
				data "total_housing_capacity" value: sum(mini_ville collect each.housing_capacity) color: #purple;
				data "total_units" value: sum(mini_ville collect (each.wood_housing_units + each.modular_housing_units)) color: #sienna;
			}
			chart "Mini-ville land use" type: series size: {0.5,0.5} position: {0.5, 0} {
				data "used_buildable_area" value: sum(mini_ville collect each.used_buildable_area) color: #green;
				data "remaining_buildable_area" value: sum(mini_ville collect each.remaining_buildable_area) color: #olive;
			}
		}
	}
}