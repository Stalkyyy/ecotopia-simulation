model FranceTransportSimulation

global {
	// --- GIS FILES ---
	file shape_file_bounds <- file("../../includes/shapefiles/boundaries_france.shp");
	file shape_file_forests <- file("../../includes/shapefiles/forests_france_light.shp");
    file shape_rivers_lakes <- file("../../includes/shapefiles/rivers_france_light.shp");
    file shape_mountains <- file("../../includes/shapefiles/mountains_france_1300m.shp");
    // NOT using cities but regions
	geometry shape <- envelope(shape_file_bounds);

	// --- TIME & METRICS ---
	float step <- 1 #day;
	int simulation_duration <- 365;
	int population_size <- 10000;
	
	list<string> vehicle_types <- ["walk", "bicycle", "mini_bus", "taxi", "train"]; // no truck here
	map<string, float> km_usage <- vehicle_types as_map (each::0.0);
	map<string, int> vehicles_needed <- vehicle_types as_map (each::0);
	map<string, int> max_vehicles_needed <- vehicle_types as_map (each::0);

	// --- 12 FRANCE REGIONS ---
	// Manual coordinates (normalized 0.0 to 1.0)
	map<string, point> region_coords <- [
		"Hauts-de-France"::       {0.57, 0.13},
		"Ile-de-France"::         {0.54, 0.28},
		"Grand Est"::             {0.78, 0.30},
		"Normandie"::             {0.41, 0.27},
		"Bretagne"::              {0.20, 0.35},
		"Pays de la Loire"::      {0.32, 0.43},
		"Centre-Val de Loire"::   {0.51, 0.45},
		"Bourgogne-Franche-Comté"::{0.72, 0.48},
		"Auvergne-Rhône-Alpes"::  {0.70, 0.65},
		"PACA"::                  {0.84, 0.85},
		"Occitanie"::             {0.53, 0.85},
		"Nouvelle-Aquitaine"::    {0.38, 0.67}
	];

	// --- ARCS BETWEEN REGIONS ---
	list<string> transport_links <- [
		"Hauts-de-France:Ile-de-France",
		"Hauts-de-France:Normandie",
		"Hauts-de-France:Grand Est",
		"Normandie:Bretagne",
		"Normandie:Pays de la Loire",
		"Normandie:Ile-de-France",
		"Normandie:Centre-Val de Loire",
		"Ile-de-France:Grand Est",
		"Ile-de-France:Centre-Val de Loire",
		"Ile-de-France:Bourgogne-Franche-Comté",
		"Bretagne:Pays de la Loire",
		"Grand Est:Bourgogne-Franche-Comté",
		"Pays de la Loire:Nouvelle-Aquitaine",
		"Pays de la Loire:Centre-Val de Loire",
		"Centre-Val de Loire:Bourgogne-Franche-Comté",
		"Centre-Val de Loire:Nouvelle-Aquitaine",
		"Centre-Val de Loire:Auvergne-Rhône-Alpes",
		"Nouvelle-Aquitaine:Occitanie",
		"Nouvelle-Aquitaine:Auvergne-Rhône-Alpes",
		"Occitanie:Auvergne-Rhône-Alpes",
		"Occitanie:PACA",
		"Auvergne-Rhône-Alpes:PACA",
		"Bourgogne-Franche-Comté:Auvergne-Rhône-Alpes"
	];

	init {
		create fronteers from: shape_file_bounds;
		create forest from: shape_file_forests;
        create mountain from: shape_mountains;
        create water_source from: shape_rivers_lakes;
		
		write "World Width: " + world.shape.width + "m";
		write "World Height: " + world.shape.height + "m";
		
		float min_x <- shape.envelope.location.x - (shape.envelope.width / 2);
		float min_y <- shape.envelope.location.y - (shape.envelope.height / 2);
		
		// we create nodes manually
		loop r_name over: region_coords.keys {
			create region_node {
				name <- r_name;
				location <- {
					region_coords[r_name].x * world.shape.width,
					region_coords[r_name].y * world.shape.height
				};
			}
		}

		// arcs
		loop link over: transport_links {
			list<string> parts <- link split_with ":";
			region_node n1 <- region_node first_with (each.name = parts[0]);
			region_node n2 <- region_node first_with (each.name = parts[1]);
			if (n1 != nil and n2 != nil) {
				create transport_arc {
					shape <- line([n1.location, n2.location]);
				}
			}
		}

		create citizen number: population_size;
	}

	reflex update_metrics {
		loop v over: vehicle_types {
			if vehicles_needed[v] > max_vehicles_needed[v] { max_vehicles_needed[v] <- vehicles_needed[v]; }
			km_usage[v] <- 0.0;
			vehicles_needed[v] <- 0;
		}
	}

	reflex save_and_stop when: cycle >= simulation_duration {
		save ["Vehicle", "Peak"] to: "max_values_france.csv" rewrite: true;
		loop v over: max_vehicles_needed.keys { save [v, max_vehicles_needed[v]] to: "max_values_france.csv" rewrite: false; }
		write "Peaks saved to max_france.csv";
		do pause;
	}
}

species fronteers {
	aspect base {
		draw shape color: #transparent border: #black width: 2.0;
	}
}
species forest {
    aspect base {
        draw shape color: rgb(34, 139, 34, 100) border: #transparent;
    }
}

species mountain {
    aspect base {
        draw shape color: rgb(200, 200, 200, 150) border: #transparent;
    }
}

species water_source {
    aspect base {
        draw shape color: #blue border: #blue;
    }
}

species region_node {
	string name;
	aspect base {
		draw circle(12#km) color: #red border: #black;
		draw name at: location + {10#km, 10#km} color: #black font: font("Arial", 12, #bold);
	}
}

species transport_arc {
	aspect base {
		draw shape color: #gray width: 3#km;
	}
}


species citizen {
	// simple placeholder logic for now
	region_node home;
	region_node work_node;
	
	init {
		home <- any(region_node);
		// 15% probability of working in a different region
		work_node <- flip(0.15) ? any(region_node) : home;
		location <- home.location;
	}

	reflex commute_placeholder {
		if (flip(0.2)) {
			float dist <- location distance_to work_node.location;
			if (dist > 0) {
				// Long distance = Train
				km_usage["train"] <- km_usage["train"] + dist;
				vehicles_needed["train"] <- vehicles_needed["train"] + 1;
			} else {
				// local
				// maybe we use csv data here
				km_usage["walk"] <- km_usage["walk"] + 5.0;
				vehicles_needed["bicycle"] <- vehicles_needed["bicycle"] + 1;
			}
		}
	}
}

experiment display_france type: gui {
	output {
		display map type: java2D {
            species fronteers aspect: base;
            species forest aspect: base;
            species mountain aspect: base;
            species water_source aspect: base;
            
            species transport_arc aspect: base;
            species region_node aspect: base;
            
            graphics "Timer" {
                draw "Day: " + cycle at: {world.shape.width * 0.02, world.shape.height * 0.05} color: #black font: font("Arial", 18, #bold);
            }
        }
		display charts {
			chart "Peak Demand per Vehicle Type" type: series {
				data "Trains" value: max_vehicles_needed["train"] color: #blue;
				data "Bicycles" value: max_vehicles_needed["bicycle"] color: #green;
				data "Taxis" value: max_vehicles_needed["taxi"] color: #yellow;
			}
		}
	}
}