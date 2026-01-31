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
	float initial_fill_ratio <- 0.2; // share of buildable area already used at init

	// Housing capacity per unit (shared baseline)
	map<string, float> capacity_per_unit <- ["wood"::3.0, "modular"::2.5]; // persons per unit
}

/**
 * Mini-ville (v1): fixed set, aggregate land-use budgets and housing stock.
 * No explicit building agents in this version.
 */
species mini_ville {
	float buildable_area <- total_area_per_ville * buildable_ratio;
	float used_buildable_area <- 0.0;
	float area_per_unit <- area_per_unit_default;
	int wood_housing_units <- 0;
	int modular_housing_units <- 0;
	float housing_capacity <- 0.0;
	float remaining_buildable_area <- buildable_area;

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
}
