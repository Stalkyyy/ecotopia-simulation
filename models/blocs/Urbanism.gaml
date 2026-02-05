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
	// Demography scaling (must match Demography.gaml pop_per_ind)
	float nb_humans_per_agent <- 19500.0;
	//int pop_per_ind <- 6700;
	
	/* Setup */
	list<string> housing_types <- ["wood", "modular"];
	float modular_surface_factor <- 1.15; // modular units use more surface than wood (multiplier)

	map<string, int> init_units <- ["wood"::0, "modular"::0]; // will be synced from mini-villes

	// IMPORTANT: use the SAME surface notion as mini-villes (area_per_unit), otherwise you create fake land gaps.
	// In v1, we use a single footprint per unit. Later, you can refine per typology.
	map<string, float> surface_per_unit <- ["wood"::area_per_unit_default, "modular"::(area_per_unit_default * modular_surface_factor)]; // m² per unit // m² per unit

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
	int max_units_per_tick <- 7000;            // CAP in *real* housing units / tick (tune later)
	int min_units_per_tick <- 0;

	// Construction pipeline timing (interpretation: 1 tick = 1 month)
	int build_duration_months_default <- 6;
	int build_duration_months_wood <- 5;
	int build_duration_months_modular <- 8; // modular is slower (months)

	int max_waiting_checks_per_tick <- 200; // try to start up to N waiting orders per tick
	int max_builds_started_per_tick <- 50; // cap number of mini-villes that can transition to 'building' per tick
	int builds_started_count_tick <- 0; // debug + gating for max_builds_started_per_tick

	// Two-phase diagnostics (no API changes)
	int tick_can_checks <- 0;
	int tick_can_fails <- 0;
	int tick_commit_fails <- 0;

	// Debug / diagnostics
	bool prev_totals_initialized <- false;
	int prev_total_units <- 0;
	int prev_wood_units <- 0;
	int prev_modular_units <- 0;

	int completed_units_tick <- 0; // total units that finished since last tick (delta of stock)
	int completed_wood_units_tick <- 0;
	int completed_modular_units_tick <- 0; // units that finished this tick (delta of stock)
	int demolished_units_tick <- 0; // total units demolished since last tick (delta of stock)
	int demolished_wood_units_tick <- 0;
	int demolished_modular_units_tick <- 0;
	float completed_capacity_tick <- 0.0;
	float demolished_capacity_tick <- 0.0;
	int net_units_tick <- 0;
	float net_capacity_tick <- 0.0;

	map<string, int> tick_orders_created <- ["wood"::0, "modular"::0];
	map<string, float> tick_orders_created_scaled <- ["wood"::0.0, "modular"::0.0];
	float pending_surface_total <- 0.0;   // sum of pending_surface in non-idle cities (m², simulated)
	float pending_capacity_total <- 0.0;  // sum of pending capacity in non-idle cities (persons, simulated)

	// CDC scaling for charts: upscale capacity/land if simulated mini-villes represent constellations
	int target_pop_per_miniville_real <- 10000;
	int nb_minivilles_sim <- 1;
	int nb_minivilles_real <- 1;
	float alpha_mv <- 1.0;
	bool use_dynamic_alpha <- false; // if true, recompute alpha_mv each tick (can make scaled capacity 'wiggle' with population)
	bool alpha_mv_frozen_set <- false;
	float alpha_mv_frozen <- 1.0;
	// Debug: artificially inflate demand to make resources scarce (for testing can_produce / reservation)
	bool debug_scarcity_enabled <- false;
	float debug_scarcity_multiplier <- 5.0; // multiply resource demands by this factor when debug_scarcity_enabled=true


// --- Decay (housing lifecycle v0) controls (annual rate, applied every N cycles) ---
float decay_rate_annual_param <- 0.002;     // e.g. 0.002 = 0.2% per year
int decay_period_cycles_param <- 12;        // if 1 tick = 1 month, 12 => yearly decay
float decay_land_recovery_fraction_param <- 1.0; // 1.0 = fully recover land on decay
bool debug_decay_log_param <- false;
 // snapshot of alpha_mv_dynamic at first tick when frozen
	float capacity_real_scaled <- 0.0;
	float surface_used_scaled <- 0.0;
	float remaining_buildable_scaled <- 0.0;

	/* State (for charts/logging) */
	int population_count <- 0;           // nb of human agents (sample)
	float population_real <- 0.0;        // scaled population in real persons (nb_humans * nb_humans_per_agent)
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
		// Initialize mini-villes from the GIS "city" layer.
		// IMPORTANT: if mini_ville_count > number of GIS cities, we *replicate* city locations
		// (cycling through the available cities). This is only for scaling/performance tests.
		// For a true ~6500-location run, the "city" layer must contain ~6500 features.
		list<city> cities <- (city as list<city>);

		if(length(cities) > 0){
			loop i from: 0 to: (mini_ville_count - 1) {
				city c <- cities[i mod length(cities)];
				create mini_ville number: 1 {
					location <- c.location;
				}
			}
		} else {
			// Fallback: create mini-villes without spatial anchoring.
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

		// Reset per-tick diagnostics
		builds_started_count_tick <- 0;
		tick_can_checks <- 0;
		tick_can_fails <- 0;
		tick_commit_fails <- 0;

		// Always sync first (single source of truth = mini-villes)
		do sync_from_cities(cities);
		do sync_constructible_surface(cities);
// Push decay settings into mini-villes (so decay is controllable from the Urbanism experiment)
ask cities {
    annual_decay_rate <- decay_rate_annual_param;
    decay_period_cycles <- decay_period_cycles_param;
    decay_land_recovery_fraction <- decay_land_recovery_fraction_param;
    debug_decay_log <- debug_decay_log_param;
}

		// Try to start some orders that are waiting for resources (resource dependence)
		int checked_from_waiting <- 0;
		loop c over: (cities where (each.construction_state = "waiting_resources")) {
			if(checked_from_waiting >= max_waiting_checks_per_tick) { break; }
			if(builds_started_count_tick >= max_builds_started_per_tick) { break; }
			bool ok <- try_start_city_order(c);
			checked_from_waiting <- checked_from_waiting + 1;
		}
		// Population (REAL) — Demography uses the same scaling
		int nb_humans <- length(pop);
		population_count <- nb_humans;
		population_real <- nb_humans * nb_humans_per_agent;

		// Completed units this tick = delta in built stock (construction commits happen inside mini-villes)
		int current_wood_units <- units["wood"];
		int current_modular_units <- units["modular"];
		int current_total_units <- current_wood_units + current_modular_units;

		// Compute completions as *deltas* of built stock (so "completed" != "started").
		// Avoid a large spike at the first tick by initializing previous totals once.
		if(!prev_totals_initialized){
			prev_totals_initialized <- true;
			prev_wood_units <- current_wood_units;
			prev_modular_units <- current_modular_units;
			prev_total_units <- current_total_units;

			completed_wood_units_tick <- 0;
			completed_modular_units_tick <- 0;
			completed_units_tick <- 0;

			demolished_wood_units_tick <- 0;
			demolished_modular_units_tick <- 0;
			demolished_units_tick <- 0;

			completed_capacity_tick <- 0.0;
			demolished_capacity_tick <- 0.0;
			net_units_tick <- 0;
			net_capacity_tick <- 0.0;
		} else {
			// Positive deltas = new units completed
			completed_wood_units_tick <- max(0, current_wood_units - prev_wood_units);
			completed_modular_units_tick <- max(0, current_modular_units - prev_modular_units);
			completed_units_tick <- completed_wood_units_tick + completed_modular_units_tick;

			// Negative deltas = units removed (decay / demolition)
			demolished_wood_units_tick <- max(0, prev_wood_units - current_wood_units);
			demolished_modular_units_tick <- max(0, prev_modular_units - current_modular_units);
			demolished_units_tick <- demolished_wood_units_tick + demolished_modular_units_tick;

			completed_capacity_tick <- (float(completed_wood_units_tick) * capacity_per_unit["wood"])
				+ (float(completed_modular_units_tick) * capacity_per_unit["modular"]);
			demolished_capacity_tick <- (float(demolished_wood_units_tick) * capacity_per_unit["wood"])
				+ (float(demolished_modular_units_tick) * capacity_per_unit["modular"]);

			net_units_tick <- completed_units_tick - demolished_units_tick;
			net_capacity_tick <- completed_capacity_tick - demolished_capacity_tick;

			prev_wood_units <- current_wood_units;
			prev_modular_units <- current_modular_units;
			prev_total_units <- current_total_units;
		}
// CDC-style scaling: if the simulated set of mini-villes represents a constellation of real mini-villes
		nb_minivilles_sim <- max(1, length(cities));
		nb_minivilles_real <- int(ceil(population_real / target_pop_per_miniville_real));
		float alpha_mv_dynamic <- float(nb_minivilles_real) / float(nb_minivilles_sim);
		if (!alpha_mv_frozen_set) {
			alpha_mv_frozen <- alpha_mv_dynamic;
			alpha_mv_frozen_set <- true;
		}
		if (use_dynamic_alpha) {
			alpha_mv <- alpha_mv_dynamic;
		} else {
			alpha_mv <- alpha_mv_frozen;
		}

		// Pending (orders waiting/building) to prevent overshoot and land overbooking
		pending_surface_total <- sum(cities where (each.construction_state != "idle") collect each.pending_surface);
		pending_capacity_total <- sum(cities where (each.construction_state != "idle") collect ((each.pending_wood_units * capacity_per_unit["wood"]) + (each.pending_modular_units * capacity_per_unit["modular"])));

		// Capacity and land are computed from the simulated mini-villes, then scaled by alpha for comparisons to real population
		float capacity_effective <- total_capacity * alpha_mv; // persons (built stock)
		float capacity_future_effective <- (total_capacity + pending_capacity_total) * alpha_mv; // persons (built + in pipeline)
		capacity_real_scaled <- capacity_effective;
		surface_used_scaled <- surface_used * alpha_mv;
		remaining_buildable_scaled <- constructible_surface_total * alpha_mv;

		if(not cities_logged){
			write "urbanism received mini_villes=" + string(length(cities)) + " alpha_mv=" + string(alpha_mv);
			cities_logged <- true;
		}

		float desired_capacity <- population_real / target_occupancy_rate;
		float deficit_people <- max(0.0, desired_capacity - capacity_future_effective);

		// Convert deficit in persons to a number of (SIMULATED) housing units to add this tick
		int units_needed <- int(ceil(deficit_people / (average_capacity_per_unit() * alpha_mv)));
		int planned_units <- int(ceil(units_needed * build_fraction_of_deficit));
		planned_units <- min(max_units_per_tick, planned_units);
		planned_units <- max(min_units_per_tick, planned_units);

		// Hysteresis: stop building once we are comfortably below the target occupancy
		float occupancy <- population_real / max(1.0, capacity_future_effective);
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

				map<string, float> demand <- compute_resource_demand(wood_plan, modular_plan, planned_surface);

				// Always register the order first (city enters waiting_resources).
				// IMPORTANT: do NOT call producer.produce() before the order exists.
				// Resource reservation/consumption happens only when the city transitions to "building".
				int planned_duration <- compute_build_duration(wood_plan, modular_plan);
				ask target_city { do set_construction_order(wood_plan, modular_plan, planned_surface, demand, planned_duration); }
				tick_orders_created["wood"] <- tick_orders_created["wood"] + wood_plan;
				tick_orders_created["modular"] <- tick_orders_created["modular"] + modular_plan;
				tick_orders_created_scaled["wood"] <- tick_orders_created_scaled["wood"] + float(wood_plan);
				tick_orders_created_scaled["modular"] <- tick_orders_created_scaled["modular"] + float(modular_plan);

					// Try to reserve resources immediately so construction can start in the same tick when possible.
					// Respect the per-tick cap to avoid mass-start artifacts when many cities request at once.
					if(builds_started_count_tick < max_builds_started_per_tick and try_start_city_order(target_city)){
						write "urbanism: start build " + string(planned_units) + " units (area=" + string(planned_surface)
							+ ") in mini_ville " + string(target_city.index);
					}
				// If ok=false, the mini-ville stays in waiting_resources and will be retried on later ticks.

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
			map<string, unknown> info <- producer.produce("urbanism", energy_demand);
		}
	}

	// Centralized start logic: reserve external resources and transition the city to "building".
	// This is used both for newly created orders and for retrying "waiting_resources" orders.
	bool try_start_city_order(mini_ville c){
		if(c = nil){ return false; }
		if(c.construction_state != "waiting_resources"){ return false; }
		if(length(c.pending_demand) = 0){ return false; }

		// Enforce per-tick cap on starts (prevents 'instant mass build' artifacts at scale)
		if(builds_started_count_tick >= max_builds_started_per_tick){ return false; }

<<<<<<< HEAD
		// Dry-run feasibility check (no API changes): only if the producer is our urban_producer
		urban_producer up <- urban_producer(producer);
		if(up != nil){
			tick_can_checks <- tick_can_checks + 1;
			map<string, unknown> can_info <- up.can_produce(c.pending_demand);
			if(!bool(can_info["ok"])) {
				tick_can_fails <- tick_can_fails + 1;
				return false;
			}
		}

		map<string, unknown> info <- producer.produce("urbanism", c.pending_demand);
		if(!bool(info["ok"])) { tick_commit_fails <- tick_commit_fails + 1; }
=======
		map<string, unknown> info <- producer.produce("urbanism", c.pending_demand);
>>>>>>> 7e044260ba3797e7355b2e25dec5ab184ecb7f9b
		if(bool(info["ok"])) {
			ask c { do start_build; }
			builds_started_count_tick <- builds_started_count_tick + 1;

			// Count as started builds this tick (still not completed)
			tick_constructions["wood"] <- tick_constructions["wood"] + c.pending_wood_units;
			tick_constructions["modular"] <- tick_constructions["modular"] + c.pending_modular_units;
			tick_constructions_scaled["wood"] <- tick_constructions_scaled["wood"] + float(c.pending_wood_units);
			tick_constructions_scaled["modular"] <- tick_constructions_scaled["modular"] + float(c.pending_modular_units);
			return true;
		}
		return false;
	}

	/* Helpers */
	float average_capacity_per_unit{
		return (sum(housing_types collect capacity_per_unit[each]) / length(housing_types));
	}

<<<<<<< HEAD
	
	int compute_build_duration(int wood_units, int modular_units){
		int total_units <- wood_units + modular_units;
		if(total_units <= 0){ return build_duration_months_default; }
		float weighted <- (float(build_duration_months_wood) * wood_units + float(build_duration_months_modular) * modular_units) / float(total_units);
		return max(1, int(ceil(weighted)));
	}

map<string, float> compute_resource_demand(int wood_units, int modular_units, float planned_surface){
		// IMPORTANT: do NOT multiply again by pop_per_ind — these are already REAL units.
=======
	map<string, float> compute_resource_demand(int wood_units, int modular_units, float planned_surface){
		// IMPORTANT: do NOT multiply again by nb_humans_per_agent — these are already REAL units.
>>>>>>> 7e044260ba3797e7355b2e25dec5ab184ecb7f9b
		map<string, float> demand <- ["kg wood"::0.0, "kg_cotton"::0.0, "kWh energy"::0.0, "m² land"::0.0];

		demand["kg wood"] <- resource_per_unit_wood["kg wood"] * wood_units;
		demand["kg_cotton"] <- resource_per_unit_modular["kg_cotton"] * modular_units;
		demand["kWh energy"] <- (resource_per_unit_wood["kWh energy"] * wood_units
			+ resource_per_unit_modular["kWh energy"] * modular_units);

		demand["m² land"] <- planned_surface;

		
		if (debug_scarcity_enabled) {
			// Inflate *resource* demand to force feasibility failures without desynchronizing land accounting
			demand["kg wood"] <- demand["kg wood"] * debug_scarcity_multiplier;
			demand["kg_cotton"] <- demand["kg_cotton"] * debug_scarcity_multiplier;
			demand["kWh energy"] <- demand["kWh energy"] * debug_scarcity_multiplier;
		}

return demand;
	}

	bool surface_room(int planned_units){
		float planned_surface <- planned_units * (surface_per_unit["wood"] * 0.6 + surface_per_unit["modular"] * 0.4);
		return (surface_used + planned_surface) <= constructible_surface_total;
	}

	mini_ville select_city(list<mini_ville> cities, float required_area){
		if(length(cities) = 0){
			return nil;
		}
		list<mini_ville> candidates <- cities where (each.construction_state = "idle" and each.remaining_buildable_area >= required_area);
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
		// We subtract pending_surface (orders in waiting/building) to avoid overbooking land before commits.
		float local_remaining <- 0.0;
		float local_pending <- 0.0;
		loop c over: cities{
			local_remaining <- local_remaining + c.remaining_buildable_area;
			if(c.construction_state != "idle"){
				local_pending <- local_pending + c.pending_surface;
			}
		}
		local_remaining <- max(0.0, local_remaining - local_pending);

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
		builds_started_count_tick <- 0;
		tick_constructions["wood"] <- 0;
		tick_constructions["modular"] <- 0;
		tick_constructions_scaled["wood"] <- 0.0;
		tick_constructions_scaled["modular"] <- 0.0;
		tick_orders_created["wood"] <- 0;
		tick_orders_created["modular"] <- 0;
		tick_orders_created_scaled["wood"] <- 0.0;
		tick_orders_created_scaled["modular"] <- 0.0;
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

<<<<<<< HEAD
	
	// Dry-run feasibility check (no side effects). Does NOT require API.gaml changes.
	map<string, unknown> can_produce(map<string, float> demand){
		bool ok <- true;

		// Non-ecosystem resources: we can only validate presence of a supplier (unless sub-blocs expose their own checks).
		loop r over: demand.keys{
			float qty <- demand[r];
			if(qty <= 0.0){ continue; }
			if(r = "m² land" or r = "kg wood" or r = "L water"){ continue; }
			if(!(external_producers.keys contains r)){
				ok <- false;
			}
		}

		// Ecosystem resources: we can safely pre-check stocks (land/wood/water) without consuming anything.
		map<string, float> eco_demand <- [];
		if("m² land" in demand.keys and demand["m² land"] > 0.0){ eco_demand["m² land"] <- demand["m² land"]; }
		if("kg wood" in demand.keys and demand["kg wood"] > 0.0){ eco_demand["kg wood"] <- demand["kg wood"]; }
		if("L water" in demand.keys and demand["L water"] > 0.0){ eco_demand["L water"] <- demand["L water"]; }

		if(length(eco_demand) > 0){
			if(length(ecosystem) = 0){
				ok <- false;
			} else {
				// Check we have an ecosystem supplier bloc registered
				bloc eco_bloc <- nil;
				if(external_producers.keys contains "m² land"){ eco_bloc <- external_producers["m² land"]; }
				else if(external_producers.keys contains "kg wood"){ eco_bloc <- external_producers["kg wood"]; }
				else if(external_producers.keys contains "L water"){ eco_bloc <- external_producers["L water"]; }
				if(eco_bloc = nil){
					ok <- false;
				} else {
					float land_av <- 0.0;
					float wood_av <- 0.0;
					float water_av <- 0.0;
					ask one_of(ecosystem){
						land_av <- land_stock;
						wood_av <- wood_stock_kg;
						water_av <- water_stock_l;
					}
					if("m² land" in eco_demand.keys and eco_demand["m² land"] > land_av){ ok <- false; }
					if("kg wood" in eco_demand.keys and eco_demand["kg wood"] > wood_av){ ok <- false; }
					if("L water" in eco_demand.keys and eco_demand["L water"] > water_av){ ok <- false; }
				}
			}
		}

		return ["ok"::ok];
	}

	map<string, unknown> produce(string bloc_name, map<string, float> demand){
		// Two-phase: dry-run feasibility check before consuming anything
		map<string, unknown> pre <- can_produce(demand);
		if(!bool(pre["ok"])) { return ["ok"::false]; }

=======
	map<string, unknown> produce(string bloc_name, map<string, float> demand){
>>>>>>> 7e044260ba3797e7355b2e25dec5ab184ecb7f9b
		bool ok <- true;
		list<string> processed <- [];

		// --- Phase 1: non-ecosystem resources in a stable order ---
		// Rationale: Agriculture/Energy may have their own constraints and can fail.
		// We try them BEFORE consuming scarce ecosystem land/wood.
		list<string> priority <- ["kg_cotton", "kWh energy"];
		loop r over: priority {
			if(r in demand.keys){
				float qty <- demand[r];
				if(external_producers.keys contains r){
<<<<<<< HEAD
					map<string, unknown> info <- external_producers[r].producer.produce(bloc_name, [r::qty]);
=======
					map<string, unknown> info <- external_producers[r].producer.produce("urbanism", [r::qty]);
>>>>>>> 7e044260ba3797e7355b2e25dec5ab184ecb7f9b
					if not bool(info["ok"]) {
						ok <- false;
					} else {
						if(not (tick_resources_used.keys contains r)){
							tick_resources_used[r] <- 0.0;
						}
						tick_resources_used[r] <- tick_resources_used[r] + qty;
					}
				} else {
					ok <- false;
				}
				processed <- processed + [r];
			}
		}

		// --- Phase 2: any other non-ecosystem keys (except land/wood) ---
		loop r over: demand.keys{
			if(r in processed){ continue; }
			if(r = "m² land" or r = "kg wood" or r = "L water"){ continue; }
			float qty <- demand[r];
			if(external_producers.keys contains r){
<<<<<<< HEAD
				map<string, unknown> info <- external_producers[r].producer.produce(bloc_name, [r::qty]);
=======
				map<string, unknown> info <- external_producers[r].producer.produce("urbanism", [r::qty]);
>>>>>>> 7e044260ba3797e7355b2e25dec5ab184ecb7f9b
				if not bool(info["ok"]) {
					ok <- false;
				} else {
					if(not (tick_resources_used.keys contains r)){
						tick_resources_used[r] <- 0.0;
					}
					tick_resources_used[r] <- tick_resources_used[r] + qty;
				}
			} else {
				ok <- false;
			}
			processed <- processed + [r];
		}

		// --- Phase 3: ecosystem resources (atomic pre-check + single call) ---
		map<string, float> eco_demand <- [];
		if("m² land" in demand.keys){ eco_demand["m² land"] <- demand["m² land"]; }
		if("kg wood" in demand.keys){ eco_demand["kg wood"] <- demand["kg wood"]; }
		if("L water" in demand.keys){ eco_demand["L water"] <- demand["L water"]; }

		if(length(eco_demand) > 0){
			// If no ecosystem exists yet, fail explicitly
			if(length(ecosystem) = 0){
				ok <- false;
			} else {
				float land_av <- 0.0;
				float wood_av <- 0.0;
				float water_av <- 0.0;
				ask one_of(ecosystem){
					land_av <- land_stock;
					wood_av <- wood_stock_kg;
					water_av <- water_stock_l;
				}

				bool eco_ok <- true;
				if("m² land" in eco_demand.keys and eco_demand["m² land"] > land_av){ eco_ok <- false; }
				if("kg wood" in eco_demand.keys and eco_demand["kg wood"] > wood_av){ eco_ok <- false; }
				if("L water" in eco_demand.keys and eco_demand["L water"] > water_av){ eco_ok <- false; }

				if(!eco_ok){
					ok <- false;
				} else {
					// Pick the ecosystem supplier bloc (m² land preferred, else kg wood / L water)
					bloc eco_bloc <- nil;
					if(external_producers.keys contains "m² land"){ eco_bloc <- external_producers["m² land"]; }
					else if(external_producers.keys contains "kg wood"){ eco_bloc <- external_producers["kg wood"]; }
					else if(external_producers.keys contains "L water"){ eco_bloc <- external_producers["L water"]; }

					if(eco_bloc = nil){
						ok <- false;
					} else {
<<<<<<< HEAD
						map<string, unknown> info <- eco_bloc.producer.produce(bloc_name, eco_demand);
=======
						map<string, unknown> info <- eco_bloc.producer.produce("urbanism", eco_demand);
>>>>>>> 7e044260ba3797e7355b2e25dec5ab184ecb7f9b
						if not bool(info["ok"]) {
							ok <- false;
						} else {
							loop r over: eco_demand.keys{
								float qty <- eco_demand[r];
								if(not (tick_resources_used.keys contains r)){
									tick_resources_used[r] <- 0.0;
								}
								tick_resources_used[r] <- tick_resources_used[r] + qty;
							}
						}
					}
				}
			}
		}

		return ["ok"::ok];
	}
}

/**
 * Minimal experiment to visualize capacity vs population and construction activity.
 */
experiment run_urbanism type: gui {
	// --- Debug parameters (shown in the GUI Parameters view) ---
parameter "Decay rate (annual)" var: decay_rate_annual_param category: "Decay";
parameter "Decay period (cycles)" var: decay_period_cycles_param category: "Decay";
parameter "Decay land recovery fraction" var: decay_land_recovery_fraction_param category: "Decay";
parameter "Log decay events" var: debug_decay_log_param category: "Decay";
parameter "Use dynamic alpha scaling (debug)" var: use_dynamic_alpha;
	parameter "Frozen alpha_mv (debug)" var: alpha_mv_frozen;
	parameter "Scarcity enabled (debug)" var: debug_scarcity_enabled;
	parameter "Scarcity multiplier (debug)" var: debug_scarcity_multiplier;
	output {
		display Urbanism_information type:2d{
			chart "Capacity vs population" type: series size: {0.5,0.5} position: {0, 0} {
				data "capacity (real, scaled)" value: capacity_real_scaled color: #blue;
				data "capacity (sim built)" value: total_capacity color: #lightblue;
				data "population (real)" value: population_real color: #darkgray;
			}
			chart "Construction pipeline" type: series size: {0.5,0.5} position: {0.5, 0} {
				data "orders created (scaled)" value: (tick_orders_created_scaled["wood"] + tick_orders_created_scaled["modular"]) * alpha_mv color: #darkgray;
				data "builds started (scaled)" value: (tick_constructions_scaled["wood"] + tick_constructions_scaled["modular"]) * alpha_mv color: #orange;
				data "units completed (scaled)" value: float(completed_units_tick) * alpha_mv color: #green;
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

		
		display Urbanism_lifecycle type:2d{
			chart "Net housing delta" type: series size: {0.5,0.5} position: {0, 0} {
				data "net units (scaled)" value: float(net_units_tick) * alpha_mv color: #purple;
				data "net capacity (scaled)" value: net_capacity_tick * alpha_mv color: #blue;
			}
			chart "Housing decay" type: series size: {0.5,0.5} position: {0.5, 0} {
				data "units completed (scaled)" value: float(completed_units_tick) * alpha_mv color: #green;
				data "units demolished (scaled)" value: float(demolished_units_tick) * alpha_mv color: #red;
				data "capacity demolished (scaled)" value: demolished_capacity_tick * alpha_mv color: #darkred;
			}
		}

		display Pipeline_debug type:2d{
			chart "Mini-ville states" type: series size: {1.0,0.5} position: {0, 0} {
				data "idle" value: mini_ville count (each.construction_state = "idle");
				data "waiting_resources" value: mini_ville count (each.construction_state = "waiting_resources");
				data "building" value: mini_ville count (each.construction_state = "building");

			}

			chart "Feasibility debug" type: series size: {1.0,0.5} position: {0, 0.5} {
				data "can_checks" value: tick_can_checks;
				data "can_fails" value: tick_can_fails;
				data "commit_fails" value: tick_commit_fails;
			}
		}


		monitor "alpha_mv" value: alpha_mv;
		monitor "capacity_scaled" value: capacity_real_scaled;
		monitor "pop_real" value: population_real;
		monitor "housing_deficit" value: max(0.0, population_real - capacity_real_scaled);
		monitor "occupancy" value: occupancy_rate;
		monitor "tick_can_checks" value: tick_can_checks;
		monitor "tick_can_fails" value: tick_can_fails;
		monitor "tick_commit_fails" value: tick_commit_fails;
		monitor "tick_builds_started" value: builds_started_count_tick;
		monitor "tick_units_completed" value: completed_units_tick;

		monitor "tick_units_demolished" value: demolished_units_tick;
		monitor "tick_net_units" value: net_units_tick;
		monitor "tick_capacity_demolished" value: demolished_capacity_tick;
		monitor "tick_net_capacity" value: net_capacity_tick;

		display MiniVille_state_map type:2d{
			// Visualize construction pipeline spatially (colors: green=idle, orange=waiting, red=building)
			species mini_ville aspect: construction_state_view;
		}

		display MiniVille_information type:2d{
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

experiment urbanism_tests type: test autorun: true {
	test "urbanism_invariants" {
		assert length(mini_ville) > 0;

		// Stocks must never go negative
		assert min(mini_ville collect each.wood_housing_units) >= 0;
		assert min(mini_ville collect each.modular_housing_units) >= 0;

		// Land accounting must remain consistent
		assert min(mini_ville collect each.used_buildable_area) >= 0.0;
		float max_overuse <- max(mini_ville collect (each.used_buildable_area - each.buildable_area));
		assert max_overuse <= 1e-6;
		float min_remaining <- min(mini_ville collect each.remaining_buildable_area);
		assert min_remaining >= -1e-6;

		// Capacity computed in Urbanism should match the sum over cities (within tolerance)
		float expected_capacity <- sum(mini_ville collect ((each.wood_housing_units * capacity_per_unit["wood"]) + (each.modular_housing_units * capacity_per_unit["modular"])));
		float observed_capacity <- sum(mini_ville collect each.housing_capacity);
		assert abs(expected_capacity - observed_capacity) < 1e-3;
	}
}