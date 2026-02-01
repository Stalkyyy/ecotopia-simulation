/**
* Name: FranceTransportSimulation
*/

model FranceTransportSimulation

global {
	string shp_path <- "../../includes/shapefiles/";
	file shp_bounds <- file(shp_path + "boundaries_france.shp");
	//file shp_forests <- file(shp_path + "forests_france_light.shp");
	//file shp_rivers_lakes <- file(shp_path + "rivers_france_light.shp");
	//file shp_mountains <- file(shp_path + "mountains_france_1300m.shp");
	
	geometry shape <- envelope(shp_bounds); // has to be named "shape"
	
	float step <- 1 #day;
	int simulation_duration <- 365;
	int population_size <- 10000;
	bool debug_write <- population_size = 1; // debug when population size 1
	
	int real_population; // 65M, init from CSV regions
	float scaling_factor; // init from CSV regions
	
	int train_capacity <- 500; // max
	list<string> vehicle_types <- ["train"]; // we omit the rest for now for France
	map<string, float> km_usage <- vehicle_types as_map (each::0.0);
	map<string, float> vehicles_needed <- vehicle_types as_map (each::0.0);
	
	map<string, point> region_coords <- [];
    map<string, int> region_populations <- [];

    init {
    	create fronteers from: shp_bounds;
    	
    	// Nodes
    	matrix data <- matrix(csv_file("../../includes/data/regions_france.csv"));
    	loop i from: 0 to: data.rows - 1 {
    		string r_name <- string(data[0, i]);
    		region_coords[r_name] <- {float(data[1, i]), float(data[2, i])};
    		region_populations[r_name] <- int(data[3, i]);
    		create region_node {
    			name <- r_name;
    			location <- {region_coords[r_name].x * world.shape.width, region_coords[r_name].y * world.shape.height};
    			population <- region_populations[r_name];
    		}
    	}
    	real_population <- sum(region_populations.values);
    	scaling_factor <- real_population / float(population_size);
    	write "CSV Loaded:\nFrance Pop: " + real_population+ "\nSimulation Pop: " + population_size;
    	
    	// Arcs
    	matrix link_data <- matrix(csv_file("../../includes/data/region_links_france.csv"));
    	loop i from: 1 to: link_data.rows - 1 {
	        region_node node_a <- region_node first_with (each.name = string(link_data[0, i]));
	        region_node node_b <- region_node first_with (each.name = string(link_data[1, i]));
	        
	        if (node_a != nil and node_b != nil) {
	            create transport_link {
	                start_node <- node_a;
	                end_node <- node_b;
	                shape <- line([node_a.location, node_b.location]);
	            }
	        }
	    }
    }
}

species region_node {
	string name;
	int population;
	aspect base {
		draw circle(12#km) color: #red border: #black;
		draw name at: location + {10#km, 10#km} color: #black font: font("Arial", 12, #bold);
	}
}

species transport_link {
	region_node start_node;
	region_node end_node;
	
	aspect base {
		draw link(start_node, end_node) color: #blue width: 2.0;
	}
}

species fronteers { aspect base { draw shape color: #transparent border: #black width: 2.0; } }

experiment show_france type: gui {
	output {
		display map type: java2D {
			species fronteers aspect: base;
			species region_node aspect: base;
			species transport_link aspect: base;
		}
	}
}