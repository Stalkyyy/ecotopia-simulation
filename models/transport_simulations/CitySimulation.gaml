/**
* Name: CitySimulation
* Based on the internal empty template. 
* Author: Victor Fleiser / Thomas Marchand
* Tags: 
*/


model CitySimulation


/* But: Avoir des valeurs sur le nombre de véhicules nécessaires en fonction du nombre de personne  */

global {

	geometry shape <- square(4#km);
	point center <- {2000, 2000};
	
    // -----------------------
    // TIME CONFIGURATION
    // -----------------------
    int tick_per_day <- 24;
    int simulation_duration <- 168; // 1 week
    int hour <- cycle mod tick_per_day;
    float step <- 1 #hour;

    // -----------------------
    // CITY GEOMETRY (meters)
    // -----------------------
    float city_radius <- 1000.0;
    float surroundings_radius <- 2000.0;
    city city_agent;
    bus_system bus_agent;
    train_system train_agent; 

    // -----------------------
    // POPULATION
    // -----------------------
    int population_size <- 10000;	// Also the number of agents used
    float display_ratio <- 1.0; // set <1.0 to hide a fraction of the agents visually
    bool debug_write <- population_size = 1; // debug when setting population size to 1

    // -----------------------
    // VEHICLE TYPES
    // -----------------------
    list<string> vehicle_types <- ["walk", "bicycle", "mini_bus", "taxi", "train"];

    // km usage per tick per vehicle
    map<string, float> km_usage <- vehicle_types as_map (each::0.0);
    map<string, float> total_km_usage <- vehicle_types as_map (each::0.0);

    // vehicles needed per tick
    map<string, int> vehicles_needed <- vehicle_types as_map (each::0);
    
    
    map<string, int> max_vehicles_needed <- vehicle_types as_map (each::0);

    // -----------------------
    // TRAIN STATION
    // -----------------------
    point train_station <- center;

    // -----------------------
    // DAY / NIGHT COLOR
    // -----------------------
   	bool is_night {
   		if (current_date.hour >= 6 and current_date.hour <= 18) {
            return false; // daylight
        } else {
            return true; // night
        }
   	}

    // -----------------------
    // INIT
    // -----------------------
    init {
    	create city;
    	city_agent <- any(city);
    	
    	create bus_system;
    	bus_agent <- any(bus_system);
    	
    	create train_system;
    	train_agent <- any(train_system);
        create citizen number: population_size;
    }

    // -----------------------
    // RESET METRICS EACH TICK
    // -----------------------
    reflex reset_metrics {
    	// check for peaks before reset
    	loop v over: vehicle_types {
    		total_km_usage[v] <- total_km_usage[v] + km_usage[v];
    		if (vehicles_needed[v] > max_vehicles_needed[v]) {
    			max_vehicles_needed[v] <- vehicles_needed[v];
    		}
	        km_usage[v] <- 0.0;
	        vehicles_needed[v] <- 0;
    	}
		// reset bus arc flows every tick
		loop k over: bus_agent.bus_arc_flow.keys {
		    bus_agent.bus_arc_flow[k] <- 0;
		}
		
		// we reset trains inside train
    }

    // -----------------------
    // STOP AFTER 1 WEEK
    // -----------------------
	reflex stop_simulation when: cycle >= simulation_duration {
	    float pop_size_safe <- (population_size = 0) ? 1.0 : float(population_size);
	
	    float peak_taxis_per_10k_citizens <- (max_vehicles_needed["taxi"] / pop_size_safe) * 10000.0;
	    float peak_bikes_per_10k_citizens <- (max_vehicles_needed["bicycle"] / pop_size_safe) * 10000.0;
	    float peak_minibus_fleet_per_10k <- (max_vehicles_needed["mini_bus"] / pop_size_safe) * 10000.0;
	    float peak_trains_fleet_per_10k <- (max_vehicles_needed["train"] / pop_size_safe) * 10000.0;
	    
	
	    // header
	    save ["parameter", "value"] to: "city_profile.csv" rewrite: true;
	    
	    // append data
	    save ["peak_taxis_per_10k", peak_taxis_per_10k_citizens] to: "city_profile.csv" rewrite: false;
	    save ["peak_bikes_per_10k", peak_bikes_per_10k_citizens] to: "city_profile.csv" rewrite: false;
	    save ["peak_minibus_fleet_per_10k", peak_minibus_fleet_per_10k] to: "city_profile.csv" rewrite: false;
	    save ["peak_trains_fleet_per_10k", peak_trains_fleet_per_10k] to: "city_profile.csv" rewrite: false;
	    
	    loop v over: vehicle_types {
	        save ["total_km_" + v, total_km_usage[v]] to: "city_profile.csv" rewrite: false;
    	}
	    write "Simulation finished. Profile saved to city_profile.csv";
	    do pause;
	}
}

species citizen {

    // -----------------------
    // ATTRIBUTES
    // -----------------------
    point home;
    point work;
    point errand_location <- nil;
    point leisure_location <- nil;

    string activity <- "sleep"; // sleep, idle, work, leisure, errand
    string current_vehicle <- "walk";

    bool visible_agent;
    
    map<int, list<string>> weekly_plan; 
    
    bool is_working_today <- false;
    bool is_errand_today <- false;
    
    string leisure_type; // "external", "outskirts", "home"
    int leisure_start_hour <- -1;
    int leisure_end_hour <- -1;
    
    int start_work_hour <- -1;
    int end_work_hour <- -1;
    int errand_start_hour <- -1;
    int errand_end_hour <- -1;
    int wake_up_hour <- -1;
    int bed_time_hour <- -1;
    
    
    // helper: check if [s2, e2] overlaps with existing [s1, e1]
    bool overlaps(int s1, int e1, int s2, int e2) {
        if (s1 = -1 or s2 = -1) { return false; }
        return (s2 < e1 and e2 > s1);
    }
    

    // -----------------------
    // INIT
    // -----------------------
    init {
        home <- city_agent.get_random_position_in_city();
        work <- city_agent.get_random_position_in_city();
        //write home;
        location <- home;
        visible_agent <- (rnd(1.0) <= display_ratio);
        
        do plan_weekly_schedule;
        do prepare_daily_variables;
        
        activity <- "sleep";
    }
    
    // We decide what we do (work, errand) on each day at the start
    action plan_weekly_schedule {
        // Work days: 3.5 days/week avg -> 3 or 4 days
        int nb_work_days <- flip(0.5) ? 3 : 4;
        list<float> day_weights <- [1.0, 1.0, 0.4, 1.0, 1.0, 0.2, 0.05]; // less work on sunday etc
        list<int> possible_days <- [0, 1, 2, 3, 4, 5, 6];
        list<int> my_work_days <- [];
        loop while: length(my_work_days) < nb_work_days {
	        int candidate <- rnd_choice(day_weights);
	        if !(candidate in my_work_days) {
	            my_work_days << candidate;
	        }
	    }
        
		// Errand day (0.5 per week per person -> half the pop has 1 errand)
        int my_errand_day <- -1;
        if (flip(0.5)) {
            list<int> non_work_days <- possible_days - my_work_days;
            if (length(non_work_days) > 0) {
                my_errand_day <- any(non_work_days);
            }
        }

        // fill plan map
        loop d from: 0 to: 6 {
            list<string> day_tasks <- [];
            if (d in my_work_days) { day_tasks << "work"; }
            if (d = my_errand_day) { day_tasks << "errand"; }
            
            weekly_plan[d] <- day_tasks;
        }
        if debug_write {write my_work_days + weekly_plan;}
    }
    
    // executed everyday when the citizen wakes up, decides the time when he works/errand/loisir
    action prepare_daily_variables {
        int day_index <- (current_date.day - 1) mod 7;
        list<string> today_tasks <- weekly_plan[day_index];
        
        is_working_today <- ("work" in today_tasks);
        is_errand_today <- ("errand" in today_tasks);
        
        start_work_hour <- -1; end_work_hour <- -1;
        errand_start_hour <- -1; errand_end_hour <- -1;
        leisure_start_hour <- -1; leisure_end_hour <- -1;
        
        
        wake_up_hour <- int(max(6, min(11, gauss(9.0, 1.0))));
        float raw_bedtime <- gauss(23.5, 2.0);
        bed_time_hour <- int(max(20, raw_bedtime));
        if debug_write {write "bedtime: " + bed_time_hour;}
        if (bed_time_hour >= (wake_up_hour + 24)) { bed_time_hour <- wake_up_hour + 23; }
        
        // Work: 5h
        if (is_working_today) {
            loop i from: 1 to: 30 {
                int start_t <- int(gauss(9.5, 1.5));
                int end_t <- start_t + 5;
                if (start_t >= wake_up_hour and end_t <= bed_time_hour) {
                    start_work_hour <- start_t;
                    end_work_hour <- end_t;
                    break;
                }
            }
            if debug_write {write "work: " + start_work_hour + " - " + end_work_hour;}
        }
        
        // Errand: 1~2h
        if (is_errand_today) {
            loop i from: 1 to: 30 {
                int dur <- flip(0.5) ? 1 : 2;
                int start_t <- int(gauss(15.0, 3.0));
                int end_t <- start_t + dur;
                
                if (start_t >= wake_up_hour and end_t <= bed_time_hour) {
                    if (!overlaps(start_work_hour, end_work_hour, start_t, end_t)) {
                        errand_start_hour <- start_t;
                        errand_end_hour <- end_t;
                        break;
                    }
                }
            }
            if errand_start_hour = -1 {
            	write "[WARNING] Could not find place for errand ";
            }
            if debug_write {write "errand: " + errand_start_hour + " - " + errand_end_hour;}
        }
        
        // Leisure: 1~5h (2h avg)
        float leisure_roll <- rnd(1.0);
        if (leisure_roll < 0.5) { leisure_type <- "external"; }
        else if (leisure_roll < 0.8) { leisure_type <- "outskirts"; }
        else { leisure_type <- "home"; }

        loop i from: 1 to: 300 {
        	int dur <- int(min(max(1, gauss(2.0, 2.0))), 5);
            int start_t <- int(gauss(17.0, 3.0)); // à 17h
            int end_t <- start_t + dur;
            
            if (start_t >= wake_up_hour and end_t <= bed_time_hour) {
                bool conflict_work <- overlaps(start_work_hour, end_work_hour, start_t, end_t);
                bool conflict_errand <- overlaps(errand_start_hour, errand_end_hour, start_t, end_t);
                
                if (!conflict_work and !conflict_errand) {
                    leisure_start_hour <- start_t;
                    leisure_end_hour <- end_t;
                    break;
                }
            }
        }
        if leisure_start_hour = -1 {
        	write "[WARNING] Could not find place for leisure";
        }
        if debug_write{write "leisure: " + leisure_start_hour + " - " + leisure_end_hour + ", type: " + leisure_type;}
        
        if (leisure_type = "outskirts") {
            float dist <- rnd(city_radius, surroundings_radius);
            float angle <- rnd(360.0);
            leisure_location <- {center.x + dist * cos(angle), center.y + dist * sin(angle)};
        } else if (leisure_type = "external") { // we move to the train station (mini ville scale)
        	leisure_location <- train_station;
        } else {
            leisure_location <- home;
        }
    }
    
    
    
    // -----------------------
    // ACTIVITY LOGIC
    // -----------------------
    
    reflex wake_up when: current_date.hour = wake_up_hour and activity = "sleep" {
        activity <- "idle";
        do prepare_daily_variables;
    }
    
    reflex go_to_work when: is_working_today and current_date.hour = start_work_hour and activity != "work" {
        activity <- "work";
        do add_travel_to_total(vehicle_usage(location, work, create_vehicle_choice_initial_usage()));
        location <- work;
    }
    reflex leave_work when: is_working_today and current_date.hour = end_work_hour and activity = "work" {
        activity <- "idle";
        do add_travel_to_total(vehicle_usage(location, home, create_vehicle_choice_initial_usage()));
        location <- home;
    }
    
    reflex start_errand when: is_errand_today and current_date.hour = errand_start_hour and activity = "idle" {
        activity <- "errand";
        errand_location <- city_agent.get_random_position_in_city();
        do add_travel_to_total(vehicle_usage(location, errand_location, create_vehicle_choice_initial_usage()));
        location <- errand_location;
    }
    reflex end_errand when: is_errand_today and current_date.hour = errand_end_hour and activity = "errand" {
        activity <- "idle";
        do add_travel_to_total(vehicle_usage(location, home, create_vehicle_choice_initial_usage()));
        location <- home; 
        errand_location <- nil;
    }
    
    reflex start_leisure when: current_date.hour = leisure_start_hour and activity = "idle" {
        activity <- "leisure";
        if (leisure_type = "outskirts") {
            do add_travel_to_total(vehicle_usage(location, leisure_location, create_vehicle_choice_initial_usage()));
            location <- leisure_location;
        } else if (leisure_type = "external") {
        	do add_travel_to_total(vehicle_usage(location, leisure_location, create_vehicle_choice_initial_usage()));
        	ask train_agent { do register_passenger_out; }
        	location <- point(rnd(2000.0)+1000, rnd(1000.0)+4200); // only train station distance, other location to visualize
        }
    }
    reflex end_leisure when: current_date.hour = leisure_end_hour and activity = "leisure" {
        activity <- "idle";
        if (location != home) {
        	if leisure_type = "external" { // we are outside (to visualize) but we should travel from the train station
        		ask train_agent { do register_passenger_in; }
        		location <- leisure_location; // tp to train station first
        		do add_travel_to_total(vehicle_usage(location, home, create_vehicle_choice_initial_usage()));
        		location <- home;
        	} else {
        		do add_travel_to_total(vehicle_usage(location, home, create_vehicle_choice_initial_usage()));
            	location <- home;	
        	}
        }
        leisure_location <- nil;
    }
    
    reflex go_to_sleep when: current_date.hour = (bed_time_hour mod 24) and activity != "sleep" {
        if (location != home) {
            do add_travel_to_total(vehicle_usage(location, home, create_vehicle_choice_initial_usage()));
            location <- home;
        }
        activity <- "sleep";
    }
    

    // -----------------------
    // SIMPLE PLACEHOLDER TRAVEL LOGIC
    // -----------------------
    
    map<string, float> create_vehicle_choice_initial_usage {
    	// initialisation : 0 km pour tous les véhicules
    	map<string, float> usage;
    	loop vehicle over: vehicle_types{
    		usage[vehicle] <- 0.0;
    	}
    	return usage;
    }
    
    map<string, float> vehicle_usage (point start, point end, map<string, float> usage) {
    	// renvoie la quantité d'utilisation de chaque véhicule
    	// règles simples basées sur la distance pour déterminer le(s) véhicule(s) utilisé(s)
    	
    	float distance <- distance_to(start, end);
    	// test si la distance est très courte -> marche à pied
    	if distance <= 100 {
    		usage["walk"] <- usage["walk"] + distance;
    		return usage;
    	}
    	// test si la distance est courte -> marche à pied + vélo
    	if distance <= 500 {
    		float distance_walked <- 50.0;
    		usage["walk"] <- usage["walk"] + distance_walked;
    		usage["bicycle"] <- usage["bicycle"] + distance - distance_walked;
    		return usage;
    	}
    	// test si un bus serait intéressant à utiliser :
    	// si distance(start, stop le plus proche de start) + distance(end, stop le plus proche de end)
    	// est plus proche que distance(start, end)
		if (bus_agent.should_use_bus(start, end)) {
		    int bus_stop_start <- bus_agent.closest_bus_stop_index(start);
		    int bus_stop_end <- bus_agent.closest_bus_stop_index(end);
		    // ajout de la distance parcourue en bus (+ notice au système de bus pour qu'ils puissent traquer l'utilisation des bus)
			// on cherche à présent les déplacements start->stop->stop->end
		    float bus_distance <- bus_agent.register_bus_flow(bus_stop_start, bus_stop_end); // not used here
//		    usage["mini_bus"] <- usage["mini_bus"] + bus_distance;						// nope, this would not take into account the fact that citizens share the busses
		    usage <- vehicle_usage(start, bus_agent.bus_stops[bus_stop_start], usage);
		    usage <- vehicle_usage(bus_agent.bus_stops[bus_stop_end], end, usage);
		    return usage;
		}
		// sinon : random entre taxi et vélo+marche
		bool prend_taxi <- (rnd(1.0) <= 0.03);	// prend le taxi dans 3% des cas (je pense que les ecotopiens prendrait le taxi très rarement pour une distance si basse (échelle 3))
		if prend_taxi {
			usage["taxi"] <- usage["taxi"] + distance;
	    	return usage;
    	}
		float distance_walked <- 50.0;
		usage["walk"] <- usage["walk"] + distance_walked;
		usage["bicycle"] <- usage["bicycle"] + distance - distance_walked;
		return usage;
    }
    
    action add_travel_to_total (map<string, float> usage){
    	// add to each vehicle's total usage this tick
    	loop vehicle over: vehicle_types{
    		km_usage[vehicle] <- km_usage[vehicle] + (usage[vehicle] / #km); // div nb km
    	}
    	// update the number of vehicles needed (mini_buses are handled by the bus class directly)
    	if usage["bicycle"] > 0 {
    		vehicles_needed["bicycle"] <- vehicles_needed["bicycle"] + 1;
    	}
    	if usage["taxi"] > 0 {
    		vehicles_needed["taxi"] <- vehicles_needed["taxi"] + 1;
    	}
    }

    // -----------------------
    // DISPLAY COLOR BY ACTIVITY
    // -----------------------
    rgb agent_color {
        switch activity {
            match "sleep"   { return rgb(120, 120, 255); } // Blue
            match "idle"   { return rgb(155, 155, 155); } // Gray
            match "work"    { return rgb(255, 80, 80); }  // Red
            match "errand"  { return rgb(255, 200, 80); } // Orange/Yellow
            match "leisure" { return rgb(80, 255, 120); } // Green
            default {return rgb(200, 200, 200);}
        }
    }

    aspect base {
        if (visible_agent) {
            draw circle(10) color: agent_color();
        }
    }
}



species train_system {
	// TRAIN SYSTEM
	// To track the number of trains we would need for people going outside the city
	// We don't calculate distances at this scale
	
	int train_capacity <- 500; // the max capacity here
	int outbound_passengers <- 0;
	int inbound_passengers <- 0;
	
	// "50% des loisirs se feront dans un espace naturel accessible : point d’eau (lac, rivière, mer...), forêt, montagne.
	// Par défaut, si aucune de ces zones n’est accessible à proximité (< 2h de trajet),
	// on choisira une destination en extérieur en dehors de la mini-ville de résidence."
	// -> We suppose outside the city here, since there aren't that many places with beach etc and we suppose lake, forest, mountain is outside.
	
	action register_passenger_out {
		outbound_passengers <- outbound_passengers + 1;
	}
	
	action register_passenger_in {
		inbound_passengers <- inbound_passengers + 1;
	}
	
	reflex compute_train_fleet {
		// min 1 train/h, more if needed
		int trains_out <- 0;
		int trains_in <- 0;
		
		if (outbound_passengers > 0) {
			trains_out <- max(1, ceil(outbound_passengers / train_capacity));
		} else {
			trains_out <- 1;
		}
		
		if (inbound_passengers > 0) {
			trains_in <- max(1, ceil(inbound_passengers / train_capacity));
		} else {
			trains_in <- 1;
		}
		
		int total_trains <- trains_out + trains_in;
		
		vehicles_needed["train"] <- vehicles_needed["train"] + total_trains;
		
		km_usage["train"] <- 0.0; // not tracked at this scale
		
		// reset counters for next hour
		outbound_passengers <- 0;
		inbound_passengers <- 0;
		
	}
}



species bus_system {
	// -----------------------
	// BUS SYSTEM PARAMETERS
	// -----------------------
	int nb_bus_stops <- 8;
	float bus_ring_radius <- city_radius * 0.5;
	int mini_bus_capacity <- 20;
	
	// ordered list of bus stops (clockwise)
	list<point> bus_stops;
	
	// arc flow graph (directed)
	// key format: "i->j" where i and j are stop indices
	map<string, int> bus_arc_flow;
	float bus_arc_distance;

	init {
		// -----------------------
		// BUS STOPS INITIALIZATION
		// -----------------------
		bus_stops <- [];
		bus_arc_flow <- [];
		
		loop i from: 0 to: nb_bus_stops - 1 {
		    float angle <- (360.0 * i) / nb_bus_stops; // DEGREES
		    point p <- {
		        center.x + bus_ring_radius * cos(angle),
		        center.y + bus_ring_radius * sin(angle),
		        5
		    };
		    bus_stops << p;
		}
		
		// initialize directed arcs (i -> i+1 and reverse)
		loop i from: 0 to: nb_bus_stops - 1 {
		    int j <- (i + 1) mod nb_bus_stops;
		    bus_arc_flow[string(i) + "->" + string(j)] <- 0;
		    bus_arc_flow[string(j) + "->" + string(i)] <- 0;
		}
		
		bus_arc_distance <- distance_to(bus_stops[0], bus_stops[1]);
	}
	
	int closest_bus_stop_index (point p) {
		// version with looping, might be faster since there aren't many stops, also more accurate
	    float closest_distance <- 9000.0;
	    int closest_stop_id;
	
		loop i from: 0 to: nb_bus_stops - 1 {
			float dist <- distance_to(p, bus_stops[i]);
			if dist < closest_distance {
				closest_distance <- dist;
				closest_stop_id <- i;
			}
		}
	   
	
	    return closest_stop_id;
	}
    
    bool should_use_bus (point start, point end) {
    	// basic heuristic to estimate whether it is worth using the bus to go from start to end
    	// tests whether (the distance from start to start's closest stop + the distance from end's closest stop and the end) is shorter than the distance from start to end
	    int s_start <- closest_bus_stop_index(start);
	    int s_end <- closest_bus_stop_index(end);
	
	    point stop_start <- bus_stops[s_start];
	    point stop_end <- bus_stops[s_end];
	
	    float direct <- distance_to(start, end);
	    float bus_path <- distance_to(start, stop_start) + distance_to(stop_end, end);
	
	    return bus_path < direct;
	}
	
	float register_bus_flow (int start_stop, int end_stop) {
		// when a user takes the bus from start_stop to end_stop, we track it as +1 user on all the arcs visited on this travel
		
		int cw_steps <- (end_stop - start_stop + nb_bus_stops) mod nb_bus_stops;
	    int ccw_steps <- (start_stop - end_stop + nb_bus_stops) mod nb_bus_stops;
	
	    // choose shortest direction
	    int dir;
	    int steps;
	
	    if (cw_steps <= ccw_steps) {
	        dir <- 1;          // clockwise
	        steps <- cw_steps;
	    } else {
	        dir <- -1;         // counter-clockwise
	        steps <- ccw_steps;
	    }
	
	    int i <- start_stop;
	    float distance <- 0.0;
	
	    loop k from: 1 to: steps {
	
	        int j <- (i + dir + nb_bus_stops) mod nb_bus_stops;
	
	        string arc <- string(i) + "->" + string(j);
	        bus_arc_flow[arc] <- bus_arc_flow[arc] + 1;
	
	        i <- j;
	        distance <- distance + bus_arc_distance;
	    }
	
	    return distance;
	}
	
	reflex compute_bus_fleet {
		// TODO: THIS REFLEX NEEDS TO BE EXECUTED LAST (AFTER THE CITIZEN'S REFLEX TO MOVE)		// right now it seems to always execute last (maybe because created before ?)
		// computes the number of mini-buses needed for this tick, based on the most used arc and the bus capacity

	    int max_arc_flow <- 0;
	
	    loop v over: bus_arc_flow.values {
	        if (v > max_arc_flow) {
	            max_arc_flow <- v;
	        }
	    }
		
	    vehicles_needed["mini_bus"] <- ceil(max_arc_flow / mini_bus_capacity) * 2;	// times 2 because we need buses going both ways
	    km_usage["mini_bus"] <- (vehicles_needed["mini_bus"] * (nb_bus_stops-1) * bus_arc_distance) / #km;	// distance totale = distance pour un tour complet multiplié par le nombre de bus utilisés ce tick
	}
	
	aspect base {

	    // draw bus arcs
	    loop i from: 0 to: nb_bus_stops - 1 {
	        int j <- (i + 1) mod nb_bus_stops;
	
	        draw line([
	            bus_stops[i],
	            bus_stops[j]
	        ]) color: rgb(80, 80, 220) width: 2;
	    }
	
	    // draw bus stops
	    loop i from: 0 to: nb_bus_stops - 1 {
	        draw circle(10)
	            at: bus_stops[i]
	            color: rgb(0, 0, 180)
	            border: true;
	    }
	}
}

species city {
	
	point get_random_position_in_city {
		return any_point_in (circle(city_radius));
	}
	
	point get_random_position_in_city_and_surroundings {
		return any_point_in (circle(surroundings_radius));
	}

	init {
		location <- center;
	}
	
	aspect base {
        // surroundings
        draw circle(surroundings_radius) at: location + {0,0,-3} color: rgb(150,200,150) border: true;

        // city core
        draw circle(city_radius) at: location + {0,0,-2} color: rgb(240,240,240) border: true;

        // train station
        draw circle(15) at: {train_station.x, train_station.y, 10} color: rgb(255,0,0);
    }
}


experiment city_simulation type: gui {

    output {

        display city_display background: (is_night() ? rgb(178,178,178) : rgb(255,255,255)) axes: true {
//        	light #ambient intensity: 20;
//			light #default intensity:(is_night() ? 127 : 255);

            
			species city aspect: base;
			species bus_system aspect: base;
            species citizen aspect: base;
            graphics "Time Display" {
                string time_str <- "Day " + current_date.day + " - " + (current_date.hour < 10 ? "0" : "") + current_date.hour + ":00";
                
                draw time_str at: {100, 100} color: #black font: font("Helvetica", 80, #bold);
                draw "Outside City" at: {1600, 5400} color: #black font: font("Helvetica", 20, #bold);
            }
        }

        display chart refresh: every(1#cycles) {
	        // -----------------------
	        // GRAPH 1: ACTIVITY DISTRIBUTION
	        // -----------------------
	        chart "Population Activity Distribution" type: series size: {1.0, 0.5} position: {0, 0} {
	            data "Sleep" value: citizen count (each.activity = "sleep") color: rgb(120, 120, 255);
	            data "Idle" value: citizen count (each.activity = "idle") color: rgb(155, 155, 155);
	            data "Work" value: citizen count (each.activity = "work") color: rgb(255, 80, 80);
	            data "Errand" value: citizen count (each.activity = "errand") color: rgb(255, 200, 80);
	            data "Leisure" value: citizen count (each.activity = "leisure") color: rgb(80, 255, 120);
	        }

	        // -----------------------
	        // GRAPH 2: KM USAGE
	        // -----------------------
	        chart "Vehicle km usage per tick" type: series size: {0.5, 0.5} position: {0, 0.5} y_log_scale:true {
	            data "Walk" value: km_usage["walk"];
	            data "Bicycle" value: km_usage["bicycle"];
	            data "Mini-bus" value: km_usage["mini_bus"];
	            data "Taxi" value: km_usage["taxi"];
	            data "Train" value: km_usage["train"] color: #black;
	        }
	        
	        // -----------------------
	        // GRAPH 3: VEHICLES NEEDED
	        // -----------------------
	        chart "Vehicles needed per tick" type: series size: {0.5, 0.5} position: {0.5, 0.5} y_log_scale:true {
	            data "Walk" value: vehicles_needed["walk"];
	            data "Bicycle" value: vehicles_needed["bicycle"];
	            data "Mini-bus" value: vehicles_needed["mini_bus"];
	            data "Taxi" value: vehicles_needed["taxi"];
	            data "Train" value: vehicles_needed["train"] color: #black;
	        }
        }
        monitor "Time" value: "Day " + string(current_date.day) + "   " + string(current_date.hour) + ":" + string(current_date.minute);

    }
}

