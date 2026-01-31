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

    // -----------------------
    // POPULATION
    // -----------------------
    int population_size <- 10000;	// Also the number of agents used
    float display_ratio <- 1.0; // set <1.0 to hide a fraction of the agents visually

    // -----------------------
    // VEHICLE TYPES
    // -----------------------
    list<string> vehicle_types <- ["walk", "bicycle", "mini_bus", "taxi"]; // truck and train not represented in this scale

    // km usage per tick per vehicle
    map<string, float> km_usage <- [
        "walk"::0.0,
        "bicycle"::0.0,
        "mini_bus"::0.0,
        "taxi"::0.0
    ];

    // vehicles needed per tick
    map<string, int> vehicles_needed <- [
        "walk"::0,
        "bicycle"::0,
        "mini_bus"::0,
        "taxi"::0
    ];
    
    
    map<string, int> max_vehicles_needed <- ["walk"::0, "bicycle"::0, "mini_bus"::0, "taxi"::0];

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
        create citizen number: population_size;
    }

    // -----------------------
    // RESET METRICS EACH TICK
    // -----------------------
    reflex reset_metrics {
    	// check for peaks before reset
    	loop v over: vehicle_types {
    		if (vehicles_needed[v] > max_vehicles_needed[v]) {
    			max_vehicles_needed[v] <- vehicles_needed[v];
    		}
    	}
    	// reset vehicles needed and usage
    	loop v over: vehicle_types{
	        km_usage[v] <- 0.0;
	        vehicles_needed[v] <- 0;
    	}
		// reset bus arc flows every tick
		loop k over: bus_agent.bus_arc_flow.keys {
		    bus_agent.bus_arc_flow[k] <- 0;
		}
    }

    // -----------------------
    // STOP AFTER 1 WEEK
    // -----------------------
    reflex stop_simulation when: cycle >= simulation_duration {
    	save ["Vehicle Type", "Max Needed"] to: "max_values_mini_ville.csv" rewrite: true;
    	loop v over: max_vehicles_needed.keys {
    		save [v, max_vehicles_needed[v]] to: "max_values_mini_ville.csv" rewrite: false;
    	}
    	write "Simulation finished. Peaks saved to max_values.csv";
        do pause;
    }
}

species citizen {

    // -----------------------
    // ATTRIBUTES
    // -----------------------
    point home;
    point work;

    string activity <- "sleep"; // sleep, work, leisure, travel
    string current_vehicle <- "walk";

    bool visible_agent;
    
    // Schedule
    bool is_working_today <- false;
    int start_work_hour <- -1;
    int end_work_hour <- -1;
    
    int wake_up_hour <- -1; // non workers wake up hour
    int bed_time_hour <- -1;
    

    // -----------------------
    // INIT
    // -----------------------
    init {
        home <- city_agent.get_random_position_in_city();
        work <- city_agent.get_random_position_in_city();
        location <- home;
        visible_agent <- (rnd(1.0) <= display_ratio);
        
        do plan_daily_schedule;
    }
    
    action plan_daily_schedule {
    	// bedtime: gradual 20~23h
    	bed_time_hour <- int(max(20, min(23, gauss(21.5, 1.5))));
    	
    	// Work/Leisure (0.5 <- 3.5 days per week of work on average)
    	if (flip(0.5)) {
    		is_working_today <- true;
    		
    		// gaussian distribution for start time
    		// IRL the peaks are at 7:00 and 17:00 but ecotopia -> 5.5h / day -> 9:15 to 14:45 -> simplification 9:30 to 14:30
    		float start_time <- gauss(9.5, 1.5);
    		start_work_hour <- int(max(4, min(14, start_time))); // clamp 4am~2pm
    		
    		// Work duration ~5h
    		end_work_hour <- start_work_hour + 5; 
    		
    	} else {
    		is_working_today <- false;
    		
    		// mean 9:00, min 6:00, max 11:00
    		wake_up_hour <- int(max(6, min(11, gauss(9.0, 1.0))));
    	}
    }
    
    
    // -----------------------
    // DAILY PLANNER
    // -----------------------
    //reflex plan_the_day when: current_date.hour = 0 {
    //	activity <- "sleep";
    //	
    //	// 3.5 days per week on average -> 0.5 probability
    //	if (flip(0.5)) {
    //		is_working_today <- true;
    //		
    //		// gaussian distribution for start time
    //		// IRL the peaks are at 7:00 and 17:00 but ecotopia -> 5.5h / day -> 9:30 to 14:30
    //		// avg: 09:30 std: 1.5 hours (
    //		float start_time <- gauss(8.5, 1.5);
    //		start_work_hour <- int(max(4, min(14, start_time))); // clamp 4am~2pm
    //		
    //		// work for 5.5h ≈ 6
    //		end_work_hour <- start_work_hour + 6; // suppose it's exactly 6, it will look like a gaussian anyway
    //	} else {
    //		is_working_today <- false;
    //		activity <- "leisure"; // TODO travel sometimes ?
    //	}
    //}
    
    reflex new_day_planning when: current_date.hour = 0 {
    	do plan_daily_schedule;
    }
    

    // -----------------------
    // SIMPLE PLACEHOLDER ACTIVITY LOGIC
    // -----------------------
    //reflex update_activity {
    //    if (current_date.hour < 7) {
    //        activity <- "sleep";
    //    } else if (current_date.hour >= 8 and current_date.hour <= 17) {
    //        activity <- "work";
    //    } else {
    //        activity <- "leisure";
    //    }
    //}
    
    // -----------------------
    // ACTIVITY LOGIC
    // -----------------------
    
    // sleep -> leisure
    reflex wake_up_leisure when: !is_working_today and current_date.hour = wake_up_hour and activity = "sleep" {
    	activity <- "leisure";
    }
    
    // home -> work
    reflex commute_to_work when: is_working_today and current_date.hour = start_work_hour and location = home {
    	activity <- "work";
    	
    	do add_travel_to_total(vehicle_usage(home, work, create_vehicle_choice_initial_usage()));
    	location <- work;
    }
    
    // work -> home
    reflex commute_to_home when: is_working_today and current_date.hour = end_work_hour and location = work {
    	activity <- "leisure";
    	
    	do add_travel_to_total(vehicle_usage(work, home, create_vehicle_choice_initial_usage()));
    	location <- home;
    }
    
    // leisure -> sleep
    reflex go_to_sleep when: current_date.hour = bed_time_hour and activity != "sleep" {
    	activity <- "sleep";
    	// Note: We don't need to teleport home because 'commute_to_home' already sent them home.
    	// If they are strictly "leisure" agents, they are at home (or we assume they are).
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
		bool prend_taxi <- (rnd(1.0) <= 0.05);	// prend le taxi dans 5% des cas (je pense que les ecotopiens prendrait le taxi très rarement pour une distance si basse (échelle 3))
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
    		km_usage[vehicle] <- km_usage[vehicle] + usage[vehicle];
    	}
    	// update the number of vehicles needed (mini_buses are handled by the bus class directly)
    	if usage["bicycle"] > 0 {
    		vehicles_needed["bicycle"] <- vehicles_needed["bicycle"] + 1;
    	}
    	if usage["taxi"] > 0 {
    		vehicles_needed["taxi"] <- vehicles_needed["taxi"] + 1;
    	}
    }
    
//  reflex travel when: activity = "work" and location != work {
//
//      do add_travel_to_total(vehicle_usage(location, work, create_vehicle_choice_initial_usage()));
//     
//      location <- work;
//  }

    // -----------------------
    // DISPLAY COLOR BY ACTIVITY
    // -----------------------
    rgb agent_color {
        switch activity {
            match "sleep" {return rgb(120, 120, 255);}
            match "work" {return rgb(255, 80, 80);}
            match "leisure" {return rgb(80, 255, 120);}
            match "travel" {return rgb(255, 200, 80);}
            default {return rgb(200, 200, 200);}
        }
    }

    aspect base {
        if (visible_agent) {
            draw circle(5) color: agent_color();
        }
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
	    km_usage["mini_bus"] <- vehicles_needed["mini_bus"] * (nb_bus_stops-1) * bus_arc_distance;	// distance totale = distance pour un tour complet multiplié par le nombre de bus utilisés ce tick
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
        draw circle(surroundings_radius) at: location + {0,0,-3} color: rgb(200,255,200) border: true;

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
            }
        }

        display chart refresh: every(1#cycles) {
	        // -----------------------
	        // GRAPH 1: ACTIVITY DISTRIBUTION
	        // -----------------------
	        chart "Population Activity Distribution" type: series size: {1.0, 0.5} position: {0, 0} {
	            data "Sleep" value: citizen count (each.activity = "sleep") color: rgb(120, 120, 255);
	            data "Work" value: citizen count (each.activity = "work") color: rgb(255, 80, 80);
	            data "Leisure" value: citizen count (each.activity = "leisure") color: rgb(80, 255, 120);
	            data "Travel" value: citizen count (each.activity = "travel") color: rgb(255, 200, 80);
	        }

	        // -----------------------
	        // GRAPH 2: KM USAGE
	        // -----------------------
	        chart "Vehicle km usage per tick" type: series size: {0.5, 0.5} position: {0, 0.5} {
	            data "Walk" value: km_usage["walk"];
	            data "Bicycle" value: km_usage["bicycle"];
	            data "Mini-bus" value: km_usage["mini_bus"];
	            data "Taxi" value: km_usage["taxi"];
	        }
	        
	        // -----------------------
	        // GRAPH 3: VEHICLES NEEDED
	        // -----------------------
	        chart "Vehicles needed per tick" type: series size: {0.5, 0.5} position: {0.5, 0.5} y_log_scale:true {
	            data "Walk" value: vehicles_needed["walk"];
	            data "Bicycle" value: vehicles_needed["bicycle"];
	            data "Mini-bus" value: vehicles_needed["mini_bus"];
	            data "Taxi" value: vehicles_needed["taxi"];
	        }
        }
        monitor "Time" value: "Day " + string(current_date.day) + "   " + string(current_date.hour) + ":" + string(current_date.minute);

    }
}

