/**
* Name: Mini-villes
* Shared core entity used by all blocs.
*/

model MiniVille

global{
	// Mini-ville initialization (v1: fixed number, no creation/destruction)
	int mini_ville_count <- 550;
	float total_area_per_ville <- 2e6; // m2 per mini-ville
	float buildable_ratio <- 0.4;
	float green_ratio <- 0.4;
	float infrastructure_ratio <- 0.2;
	float area_per_unit_default <- 70.0; // m2 per housing unit (avg footprint)


// Keep consistent with Urbanism: modular units use more surface than wood (multiplier)
float modular_surface_factor <- 1.15;

// --- Decay (housing lifecycle v0) defaults ---
float annual_decay_rate_default <- 0.002;      // per year
int decay_period_cycles_default <- 12;         // cycles between decay events
float decay_land_recovery_fraction_default <- 1.0; // 1.0 = fully recover land on decay
bool debug_decay_log_default <- false;
	float initial_fill_ratio <- 0.2; // share of buildable area already used at init

	// Housing capacity per unit (shared baseline)
	map<string, float> capacity_per_unit <- ["wood"::3.0, "modular"::2.5]; // persons per unit
}

/**
 * Mini-ville (v1): fixed set, aggregate land-use budgets and housing stock.
 * No explicit building agents in this version.
 */
species mini_ville {

	// --- Land / housing stock (aggregate, v1) ---
	float buildable_area <- total_area_per_ville * buildable_ratio;
	float used_buildable_area <- 0.0;
	float area_per_unit <- area_per_unit_default;
	int wood_housing_units <- 0;
	int modular_housing_units <- 0;
	float housing_capacity <- 0.0;
	float remaining_buildable_area <- buildable_area;

	// --- Construction pipeline (time + resource dependence) ---
	// States: "idle" | "waiting_resources" | "building"
	string construction_state <- "idle";
	int build_months_remaining <- 0;

	// Pending order (one at a time for v1)
	int pending_wood_units <- 0;
	int pending_modular_units <- 0;
	float pending_surface <- 0.0;               // m2 of land footprint requested/reserved (planned)
	map<string, float> pending_demand <- [];    // resources required (requested via Urbanism producer)
	int pending_build_duration_months <- 0;



// --- Type-specific footprint (used for decay land recovery) ---
map<string, float> surface_per_unit <- ["wood"::area_per_unit, "modular"::(area_per_unit * modular_surface_factor)];

// --- Decay controls (can be overwritten by Urbanism each tick) ---
float annual_decay_rate <- annual_decay_rate_default;
int decay_period_cycles <- decay_period_cycles_default;
float decay_land_recovery_fraction <- decay_land_recovery_fraction_default;
bool debug_decay_log <- debug_decay_log_default;

// Per-tick diagnostics (reset each cycle)
int tick_units_demolished <- 0;
float tick_capacity_demolished <- 0.0;
float tick_surface_freed <- 0.0;
	init{
		// initialize with partial usage of buildable area
		used_buildable_area <- buildable_area * initial_fill_ratio;
		remaining_buildable_area <- max(0.0, buildable_area - used_buildable_area);

		int total_units <- int(floor(used_buildable_area / area_per_unit));
		wood_housing_units <- int(floor(total_units * 0.6));
		modular_housing_units <- total_units - wood_housing_units;

		housing_capacity <- (wood_housing_units * capacity_per_unit["wood"])
			+ (modular_housing_units * capacity_per_unit["modular"]);

		// debug log
		write "mini_ville " + string(index) + " buildable_area=" + string(buildable_area);
	}

	/**
	 * Called by the Urbanism bloc when it wants to schedule a construction order.
	 * This does NOT consume resources by itself; it only stores the order and waits.
	 */
	action set_construction_order(int wood_units, int modular_units, float planned_surface, map<string, float> demand, int duration_months){
		if(construction_state != "idle") { return; }

		pending_wood_units <- max(0, wood_units);
		pending_modular_units <- max(0, modular_units);
		pending_surface <- max(0.0, planned_surface);
		pending_demand <- demand;
		pending_build_duration_months <- max(1, duration_months);

		construction_state <- "waiting_resources";
		build_months_remaining <- 0;
	}

	/**
	 * Called by the Urbanism bloc once resources have been successfully provided/reserved.
	 */
	action start_build{
		if(construction_state != "waiting_resources") { return; }
		construction_state <- "building";
		build_months_remaining <- pending_build_duration_months;
	}

	/**
	 * Commit housing stock and land use at completion.
	 * (Resources were already handled upstream by Urbanism/producer.)
	 */
	action commit_build{
		int total_units <- pending_wood_units + pending_modular_units;
		if(total_units <= 0) { return; }

		// Use the planned surface to derive an average footprint per unit (avoid mismatch with area_per_unit).
		float avg_area_per_unit <- pending_surface / max(1.0, float(total_units));
		avg_area_per_unit <- max(1.0, avg_area_per_unit);

		int max_fit <- int(floor(remaining_buildable_area / avg_area_per_unit));
		int feasible <- min(total_units, max_fit);

		if(feasible <= 0) { return; }

		float wood_ratio <- float(pending_wood_units) / max(1.0, float(total_units));
		int wood_feasible <- int(floor(feasible * wood_ratio));
		int modular_feasible <- feasible - wood_feasible;

		float area_used_now <- feasible * avg_area_per_unit;

		wood_housing_units <- wood_housing_units + wood_feasible;
		modular_housing_units <- modular_housing_units + modular_feasible;

		used_buildable_area <- used_buildable_area + area_used_now;
		remaining_buildable_area <- max(0.0, buildable_area - used_buildable_area);

		housing_capacity <- (wood_housing_units * capacity_per_unit["wood"])
			+ (modular_housing_units * capacity_per_unit["modular"]);
	}

	reflex construction_progress when: construction_state = "building" {
		build_months_remaining <- build_months_remaining - 1;

		if(build_months_remaining <= 0){
			do commit_build;

			// clear order
			pending_wood_units <- 0;
			pending_modular_units <- 0;
			pending_surface <- 0.0;
			pending_demand <- [];
			pending_build_duration_months <- 0;
			construction_state <- "idle";
		}
	}


// --- Housing decay (lifecycle v0): remove a small fraction of the stock periodically ---
reflex decay_and_reset {
    // reset diagnostics each cycle
    tick_units_demolished <- 0;
    tick_capacity_demolished <- 0.0;
    tick_surface_freed <- 0.0;

    int total_units <- wood_housing_units + modular_housing_units;
    if(total_units <= 0) { return; }
    if(decay_period_cycles <= 0) { return; }

    // Apply decay every 'decay_period_cycles'
    if((cycle mod decay_period_cycles) != 0) { return; }

    int units_to_remove <- int(round(float(total_units) * annual_decay_rate));
    units_to_remove <- min(units_to_remove, total_units);
    if(units_to_remove <= 0) { return; }

    // Remove proportionally across types (keep composition roughly stable)
    float wood_ratio <- float(wood_housing_units) / max(1.0, float(total_units));
    int remove_wood <- int(round(float(units_to_remove) * wood_ratio));
    remove_wood <- min(remove_wood, wood_housing_units);
    int remove_modular <- units_to_remove - remove_wood;
    remove_modular <- min(remove_modular, modular_housing_units);

    // If rounding left some units unremoved, take from the type with remaining stock
    int remaining_remove <- units_to_remove - (remove_wood + remove_modular);
    if(remaining_remove > 0){
        int take_wood <- min(remaining_remove, wood_housing_units - remove_wood);
        remove_wood <- remove_wood + take_wood;
        remaining_remove <- remaining_remove - take_wood;
        int take_mod <- min(remaining_remove, modular_housing_units - remove_modular);
        remove_modular <- remove_modular + take_mod;
    }

    // Compute freed capacity + surface (use type-specific footprints)
    float cap_removed <- remove_wood * capacity_per_unit["wood"] + remove_modular * capacity_per_unit["modular"];
    float surface_freed <- remove_wood * surface_per_unit["wood"] + remove_modular * surface_per_unit["modular"];

    // Apply demolition
    wood_housing_units <- max(0, wood_housing_units - remove_wood);
    modular_housing_units <- max(0, modular_housing_units - remove_modular);

    // Recover land (fully by default; can be < 1.0 to model irreversibility)
    float recovered_surface <- surface_freed * decay_land_recovery_fraction;
    used_buildable_area <- max(0.0, used_buildable_area - recovered_surface);
    remaining_buildable_area <- max(0.0, buildable_area - used_buildable_area);

    housing_capacity <- (wood_housing_units * capacity_per_unit["wood"])
        + (modular_housing_units * capacity_per_unit["modular"]);

    tick_units_demolished <- remove_wood + remove_modular;
    tick_capacity_demolished <- cap_removed;
    tick_surface_freed <- recovered_surface;

    if(debug_decay_log){
        write "DECAY mini_ville " + string(index) 
            + " removed=" + string(tick_units_demolished)
            + " recovered_m2=" + string(recovered_surface)
            + " remaining_m2=" + string(remaining_buildable_area);
    }
}



	// --- Visualization helper (debug) ---
	aspect construction_state_view {
		rgb c <- (construction_state = "building") ? rgb("red") : ((construction_state = "waiting_resources") ? rgb("orange") : rgb("green"));
		draw circle(1000) color: c border: rgb("black");
		// show remaining months and pending units
		draw (construction_state + " (" + string(build_months_remaining) + "m, +" + string(pending_wood_units + pending_modular_units) + ")") 
			color: rgb("black") size: 12;
	}

}
