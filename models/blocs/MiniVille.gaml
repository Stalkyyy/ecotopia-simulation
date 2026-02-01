/**
* Name: Mini-villes
* Shared core entity used by all blocs.
*
* v1 focus:
* - mini-villes are fixed in number (created at setup from a shapefile / city layer)
* - housing is aggregated inside each mini-ville (no building agents)
* - construction is a simple pipeline: order -> waiting resources -> building (time) -> commit
*/

model MiniVille

global{
	// Mini-ville initialization (v1: fixed number, no creation/destruction)
	int mini_ville_count <- 550;
	float total_area_per_ville <- 2e6; // m² per mini-ville (macro proxy)
	float buildable_ratio <- 0.4;
	float green_ratio <- 0.4;
	float population_count <- 0.0;
	float infrastructure_ratio <- 0.2;
	float area_per_unit_default <- 70.0; // m² per housing unit (avg footprint)
	float initial_fill_ratio <- 0.2; // share of buildable area already used at init

	// Housing capacity per unit (shared baseline)
	map<string, float> capacity_per_unit <- ["wood"::3.0, "modular"::2.5]; // persons per unit
}

/**
* Mini-ville (v1): fixed set, aggregate land-use budgets and housing stock.
* No explicit building agents in this version.
*
* Construction pipeline fields are used by the Urbanism bloc:
* - construction_state in {"idle","waiting_resources","building"}
* - pending_* describe the current order
* - build_months_remaining counts down when building
*/

species mini_ville {
	// Land + housing stocks
	float buildable_area <- total_area_per_ville * buildable_ratio;
	float used_buildable_area <- 0.0;
	float area_per_unit <- area_per_unit_default;
	int wood_housing_units <- 0;
	int modular_housing_units <- 0;
	float housing_capacity <- 0.0;
	float remaining_buildable_area <- buildable_area;

	// --- Construction pipeline ---
	string construction_state <- "idle"; // idle | waiting_resources | building

	int pending_wood_units <- 0;
	int pending_modular_units <- 0;
	float pending_surface <- 0.0; // m² footprint requested for the order
	map<string, float> pending_demand <- []; // resource demand map for the order
	int pending_build_duration_months <- 0;
	int build_months_remaining <- 0;

	

	// --- Order queue (v1: FIFO, no cancellation) ---
	list<int> queued_wood_units <- [];
	list<int> queued_modular_units <- [];
	list<float> queued_surface <- [];
	list<map<string,float>> queued_demand <- [];
	list<int> queued_duration_months <- [];
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

	// Register an order (does NOT consume resources).
	action set_construction_order(int wood_units, int modular_units, float surface, map<string, float> demand, int duration_months){
		// v1: if a build is already in progress, enqueue (FIFO)
		if(construction_state != "idle"){
			add item:max(0, wood_units) to: queued_wood_units;
			add item:max(0, modular_units) to: queued_modular_units;
			add item:max(0.0, surface) to: queued_surface;
			add item:copy(demand) to: queued_demand;
			add item:max(1, duration_months) to: queued_duration_months;
			return;
		}
pending_wood_units <- max(0, wood_units);
		pending_modular_units <- max(0, modular_units);
		pending_surface <- max(0.0, surface);
		pending_demand <- copy(demand);
		pending_build_duration_months <- max(1, duration_months);
		build_months_remaining <- 0;
		construction_state <- "waiting_resources";
	}

	// Start building after resources are reserved by Urbanism.
	action start_build{
		if(construction_state != "waiting_resources"){
			return;
		}
		build_months_remaining <- pending_build_duration_months;
		construction_state <- "building";
	}

	// Commit the build at completion (updates land + units + capacity).
	action commit_build{
		int total_units <- pending_wood_units + pending_modular_units;
		if(total_units <= 0){
			// clear
			pending_wood_units <- 0;
			pending_modular_units <- 0;
			pending_surface <- 0.0;
			pending_demand <- [];
			pending_build_duration_months <- 0;
			build_months_remaining <- 0;
			construction_state <- "idle";
			return;
		}

		// Clamp to remaining buildable area
		float area_per_unit_here <- area_per_unit;
		int max_fit <- int(floor(remaining_buildable_area / area_per_unit_here));
		int feasible <- min(total_units, max_fit);

		// keep ratio if clamped
		int wood_feasible <- int(floor(feasible * 0.6));
		int modular_feasible <- feasible - wood_feasible;

		float area_used_now <- feasible * area_per_unit_here;

		wood_housing_units <- wood_housing_units + wood_feasible;
		modular_housing_units <- modular_housing_units + modular_feasible;
		used_buildable_area <- used_buildable_area + area_used_now;
		remaining_buildable_area <- max(0.0, buildable_area - used_buildable_area);

		housing_capacity <- (wood_housing_units * capacity_per_unit["wood"])
			+ (modular_housing_units * capacity_per_unit["modular"]);

		// clear order
		pending_wood_units <- 0;
		pending_modular_units <- 0;
		pending_surface <- 0.0;
		pending_demand <- [];
		pending_build_duration_months <- 0;
		build_months_remaining <- 0;
		construction_state <- "idle";
	}

	// Progress countdown each tick.
	reflex construction_progress when: construction_state = "building" {
		build_months_remaining <- build_months_remaining - 1;
		if(build_months_remaining <= 0){
			do commit_build;
		}
	}


	// If idle and some queued orders exist, load the next one (FIFO).
	reflex dequeue_next_order when: construction_state = "idle" and length(queued_wood_units) > 0 {
		int w <- queued_wood_units at 0;
		int m <- queued_modular_units at 0;
		float s <- queued_surface at 0;
		map<string,float> d <- queued_demand at 0;
		int dur <- queued_duration_months at 0;

		remove from: queued_wood_units index: 0;
		remove from: queued_modular_units index: 0;
		remove from: queued_surface index: 0;
		remove from: queued_demand index: 0;
		remove from: queued_duration_months index: 0;

		do set_construction_order(w, m, s, d, dur);
	}

	// Simple visualization used by Urbanism display MiniVille_state_map
	aspect construction_state_view {
		rgb c <- rgb("green");
		if(construction_state = "waiting_resources") { c <- rgb("orange"); }
		if(construction_state = "building") { c <- rgb("red"); }
		draw circle(250.0) color: c border: rgb("black");
		// small label
		string lab <- construction_state;
		if(construction_state = "building") { lab <- "building(" + string(build_months_remaining) + ")"; }
		draw lab at: location + {0.0, 0.0} color: rgb("black");
	}
}
