/**
* Name: FranceTransportSimulation
*/

model FranceTransportSimulation

global {
	string shp_path <- "../../includes/shapefiles/";
	file shp_bounds <- file(shp_path + "boundaries_france.shp");
	file shp_forests <- file(shp_path + "forests_france_light.shp");
	file shp_rivers_lakes <- file(shp_path + "rivers_france_light.shp");
	file shp_mountains <- file(shp_path + "mountains_france_1300m.shp");
	
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
	
	float total_km_accumulated <- 0.0;
    float peak_km_day <- 0.0;
    int max_trains_needed <- 0;
	
	map<string, point> region_coords <- [];
    map<string, int> region_populations <- [];
    
    graph transport_network; // To do calculations
    
    map<string, float> city_mobility_profile;
    
    // 0.06+0.02+0.03+0.10+0.04+0.04+0.15+0.30+0.02+0.07+0.02+0.15
    // Reflects vacation, but trains don't move that much
    //list<float> monthly_ratios <- [0.06, 0.02, 0.03, 0.10, 0.04, 0.04, 0.15, 0.30, 0.02, 0.07, 0.02, 0.15];
    // flatter
    list<float> monthly_ratios <- [0.07, 0.05, 0.05, 0.09, 0.06, 0.06, 0.12, 0.20, 0.05, 0.08, 0.05, 0.12];
    float max_ratio <- max(monthly_ratios);

    float get_probability_for_day(int day) {
        float year_progress <- day / 365 * 11;
        int index_a <- int(floor(year_progress));
        int index_b <- (index_a + 1) mod 12;
        float fraction <- year_progress - index_a;
        
        // Linear interpolation: y = y0 + (y1 - y0) * fraction
        return monthly_ratios[index_a] + (monthly_ratios[index_b] - monthly_ratios[index_a]) * fraction;
    }

	// ----------
	//    INIT
	// ----------
    init {
    	create fronteers from: shp_bounds;
    	create mountain from: shp_mountains;
    	create forest from: shp_forests;
    	create water_source from: shp_rivers_lakes;
    	
    	
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
	    transport_network <- as_edge_graph(transport_link);
	    ask transport_link {write "Link from " + start_node.name + " to " + end_node.name + " length: " + (shape.perimeter / 1000) + " km";}
	    
	    
	    // Loading scale 3 data
	    matrix<string> city_data <- matrix<string>(csv_file("city_profile.csv"));
	    if (data != nil and data.rows > 0) {
	    	loop i from: 0 to: data.rows - 1 {
	    		string key <- data[0, i];
	    		float val <- float(data[1, i]);
	    		if key != "parameter" {
	    			city_mobility_profile[key] <- val;
	    		}
	    	}
	    }
	    create citizen number: population_size;
	    
	}
	
    reflex calculate_railway_infrastructure_usage {
    	km_usage["train"] <- 0.0;
    	vehicles_needed["train"] <- 0;
    	
    	ask transport_link { // loop over all links
    		if (daily_passengers > 0) {
    			int trains_on_segment <- ceil((daily_passengers * scaling_factor) / train_capacity);
    			vehicles_needed["train"] <- vehicles_needed["train"] + trains_on_segment;
    			km_usage["train"] <- km_usage["train"] + (trains_on_segment * shape.perimeter);
    			daily_passengers <- 0.0;
    		}
    	}
    	total_km_accumulated <- total_km_accumulated + km_usage["train"];
        if (km_usage["train"] > peak_km_day) { peak_km_day <- km_usage["train"]; }
        if (vehicles_needed["train"] > max_trains_needed) { max_trains_needed <- vehicles_needed["train"]; }
    }
    
    reflex stop_simulation when: cycle >= simulation_duration {
    	string csv_str <- "france_transport_results.csv";
        save ["Metric", "Value"] to: csv_str rewrite: true;
        save ["total_km_year", total_km_accumulated] to: csv_str rewrite: false;
        save ["peak_km_single_day", peak_km_day] to: csv_str rewrite: false;
        save ["max_trains_required", max_trains_needed] to: csv_str rewrite: false;
        write "Saved to " + csv_str; 
    	do pause;
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
	float daily_passengers <- 0.0;
	
	aspect base {
		rgb link_color <- hsb(0.66 * (1 - min(1.0, daily_passengers / (population_size/30))), 1.0, 1.0);
        draw shape color: link_color; 
        draw "sim " + string(int(daily_passengers)) + " (real " + string(int(daily_passengers * scaling_factor)) + ")" at: shape.centroid color: #black font: font("Arial", 6);
	}
}

species fronteers { aspect base { draw shape color: #transparent border: #black width: 2.0; } }
species mountain { aspect base { draw shape color: rgb(200, 200, 200, 150); } }
species forest { aspect base { draw shape color: rgb(34, 139, 34, 100) border: #transparent; } }
species water_source { aspect base { draw shape color: #blue border: #blue; } }


// data holder
species trip skills: [moving] {
	string type;
	region_node destination;
	int duration;
}

species citizen {
	region_node home_region;
	string activity <- "local";
	map<int, trip> travel_plan;
	
	trip active_trip <- nil;
	int remaining_days <- 0;
	
	init {
		home_region <- one_of(region_node);
		location <- home_region.location;
		if debug_write {write "Home region: " + home_region.name;}
		do plan_yearly_travel;
	}
	
	action plan_yearly_travel {
		// Work trips: ~1.1 / year, on average 1.2 days long
		int num_professional_trips <- poisson(1.1);
		loop times: num_professional_trips {
			loop i from: 1 to: 50 {
				int work_day <- rnd(0, 365);
				if (travel_plan[work_day] = nil) {
					create trip {
						type <- "work";
						destination <- one_of (region_node - myself.home_region);
						// random duration with mean 1.2: mostly 1 day, sometimes 2
                		duration <- flip(0.2) ? 2 : 1;
						myself.travel_plan[work_day] <- self;
					}
					break;
				}
			}
		}
		if debug_write {write "[Work] " + num_professional_trips + "x";}
		
		// Misc trips: 1 / month (instead of /week of CDC), on average 5.2 days long
		int num_misc_trips <- poisson(12);
        int trips_created <- 0;
        loop while: trips_created < num_misc_trips {
            int candidate_day <- rnd(0, 364);
            float p <- world.get_probability_for_day(candidate_day);
            
            // accept day if random float < probability, divided by max_ratio to normalize
            if (rnd(0.0, max_ratio) <= p) {
                if (travel_plan[candidate_day] = nil) {
                    create trip {
                        type <- "misc";
                        destination <- one_of(region_node - myself.home_region);
                        duration <- poisson(4.2) + 1;
                        myself.travel_plan[candidate_day] <- self;                        
                    }
                    trips_created <- trips_created + 1;
                }
            }
        }
		if debug_write {write "[Misc] " + num_misc_trips + "x\nDays: " + travel_plan;}
		
		// Leisure trips: 0.5 / week (half of them are on scale 3)
		int num_leisure_trips <- poisson(26);
		loop times: num_leisure_trips {
			loop i from: 1 to: 500 {
				int leisure_day <- rnd(0, 365);
				if (travel_plan[leisure_day] = nil) {
					create trip {
						type <- "leisure";
					    //destination <- one_of(region_node - myself.home_region); // We suppose it's on scale 1.
					    destination <- (region_node - myself.home_region) closest_to(myself) ;
						duration <- 1;
						myself.travel_plan[leisure_day] <- self;
					}
					break;
				}
			}
		}
	}
	
	reflex manage_travel {
        // Starting new trip
        if (active_trip = nil and travel_plan[cycle] != nil) {
            active_trip <- travel_plan[cycle];
            remaining_days <- active_trip.duration;
            activity <- active_trip.type;
            location <- active_trip.destination.location;
        	if debug_write {write "Day " + cycle + ", travelling to " + active_trip.destination.name;}
            
            // Register infrastructure usage on departure
            do execute_trip(home_region, active_trip.destination);
            
            if debug_write { write "Starting " + activity + " trip to " + active_trip.destination.name + " for " + remaining_days + " days"; }
        } 
        
        // Already on a trip
        if (active_trip != nil) {
            remaining_days <- remaining_days - 1;
            
            // Trip ends today
            if (remaining_days <= 0) {
                if debug_write { write "Trip ended. Returning home to " + home_region.name; }
                
                do execute_trip(active_trip.destination, home_region);
                
                location <- home_region.location;
                active_trip <- nil;
                activity <- "local";
            }
        }
    }
	
	action execute_trip(region_node origin, region_node destination) {
		if (origin != destination) {
			path travel_path <- path_between(transport_network, origin, destination);
			if (travel_path != nil) {
				list<transport_link> used_segments <- list<transport_link> (travel_path.edges);
				ask used_segments {
					daily_passengers <- daily_passengers + 1;
				}
			}
		}
	}
	aspect base {
		if debug_write{
			draw circle(10000) color: #yellow;	
		}
    }
}

experiment france_simulation type: gui {
	output {
		display map type: java2D {
			species fronteers aspect: base;
			species mountain aspect: base;
			species forest aspect: base;
			species water_source aspect: base;
			
			species region_node aspect: base;
			species transport_link aspect: base;
			species citizen aspect: base;
			
			graphics "Timer" {
				draw "Day: " + cycle at: {world.shape.width * 0.02, world.shape.height * 0.05} color: #black font: font("Arial", 18, #bold);
			}
		}
		display charts refresh: every(1#cycles) type: java2D {
			chart "Population Activity Distribution" type: series size: {1.0, 0.5} position: {0, 0} y_log_scale: true {
				data "At home" value: citizen count (each.activity = "local") color: #green;
				data "Work Trip" value: citizen count (each.activity = "work") color: #red;
				data "Misc Trip" value: citizen count (each.activity = "misc") color: #blue;
			}
			chart "Cumulative km usage / day" type: series size: {0.5, 0.5} position: {0, 0.5} y_log_scale: false {
				data "Train" value: km_usage["train"] color: #blue;
			}
			chart "Vehicles needed" type: series size: {0.5, 0.5} position: {0.5, 0.5} {
				data "Trains" value: vehicles_needed["train"] color: #blue;
			}
		}
	}
}