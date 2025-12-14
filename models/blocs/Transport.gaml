/**
* Name: Transport
* Based on the internal empty template. 
* Author: Victor Fleiser / Thomas Marchand
* Tags: 
*/

model Transport

import "../API/API.gaml"

/**
 * We define here the global variables and data of the bloc. Some are needed for the displays (charts, series...).
 */
global{

	/* Setup */
	list<string> production_inputs_T <- ["kWh energy"];
	list<string> production_outputs_T <- [
		"km/person_scale_1",
		"km/person_scale_2",
		"km/person_scale_3",
		"km/kg_scale_1",
		"km/kg_scale_2",
		"km/kg_scale_3"
	];
	list<string> production_emissions_T <- ["gCO2e emissions"];
	
	/* DATA */
	list<string> vehicles <- ["truck", "train", "taxi", "minibus", "bicycle", "walk"];
	
	// TODO: not real values -> change to the real values
	// TODO: also maybe read them from a csv or something
	map<string, map<string, float>> vehicle_data <- [
		"truck"::[
			"quantity"::1000, // number of vehicles available in france
			"capacity"::5000, // in kg (on average, not always full)
			"consumption"::1000, // in kWh per km
			"lifetime"::600, // in months
			"emissions"::1000 // GES per km
		],
		"train"::[
			"quantity"::1000, // number of vehicles available in france
			"capacity"::100, // in persons (on average, not always full)
			"consumption"::1000, // in kWh per km
			"lifetime"::600, // in months
			"emissions"::1000 // GES per km
		],
		"taxi"::[
			"quantity"::1000, // number of vehicles available in france
			"capacity"::3, // in persons (on average, not always full)
			"consumption"::1000, // in kWh per km
			"lifetime"::600, // in months
			"emissions"::1000 // GES per km
		],
		"minibus"::[
			"quantity"::1000, // number of vehicles available in france
			"capacity"::10, // in persons (on average, not always full)
			"consumption"::1000, // in kWh per km
			"lifetime"::600, // in months
			"emissions"::1000 // GES per km
		],
		"bicycle"::[
			"quantity"::10000, // number of vehicles available in france
			"capacity"::1, // in persons (on average, not always full)
			"consumption"::1000, // in kWh per km
			"lifetime"::600, // in months
			"emissions"::10 // GES per km
		],
		"walk"::[
			"quantity"::1, // number of vehicles available in france
			"capacity"::1, // in persons (on average, not always full)
			"consumption"::0, // in kWh per km
			"lifetime"::0, // in months
			"emissions"::0 // GES per km
		]
	];
	
	map<string, map<string, float>> modal_split <- [
		"km/person_scale_1" :: ["train"::0.95, "taxi"::0.05], // no taxi if we follow slides
		"km/kg_scale_1"     :: ["truck"::1.0],
		
		"km/person_scale_2" :: ["train"::0.90, "taxi"::0.10],
		"km/kg_scale_2"     :: ["truck"::1.0], 
		
		"km/person_scale_3" :: ["walk"::0.50, "taxi"::0.10, "bicycle"::0.30, "minibus"::0.10],
		"km/kg_scale_3"     :: ["truck"::1.0]
		// TODO values are kinda random, find good parameters, and maybe change by distance too
	];
	
	/* Consumption data *///TODO: remove, although useful for fake simulation without block connections
	map<string, float> indivudual_consumption_T <- [
	"km/person_scale_1"::10.0,
	"km/person_scale_2"::50.0,
	"km/person_scale_3"::500.0,
	"km/kg_scale_1"::1000.0,
	"km/kg_scale_2"::5000.0,
	"km/kg_scale_3"::5000.0
	]; // monthly consumption per individual of the population. Note : this is fake data.
	
	/* Counters & Stats *///TODO: change to the right metrics
	map<string, float> tick_production_T <- [];
	map<string, float> tick_pop_consumption_T <- [];
	map<string, float> tick_resources_used_T <- [];
	map<string, float> tick_emissions_T <- [];

	init{ // a security added to avoid launching an experiment without the other blocs
		if (length(coordinator) = 0){
			error "Coordinator agent not found. Ensure you launched the experiment from the Main model";
			// If you see this error when trying to run an experiment, this means the coordinator agent does not exist.
			// Ensure you launched the experiment from the Main model (and not from the bloc model containing the experiment).
		}
	}
}


/**
 * We define here the transport bloc as a species.
 * We implement the methods of the API.
 */
species transport parent:bloc{
	// DATA :
	
	// number of vehicules in france (all scales for now?), this number decreases when vehicles reach their end of lifetime, it increases when a new vehicle is created
	// TODO: also handle the age of the vehicles
	map<string, int> number_of_vehicles <- []; // initialized in setup()



	// CODE :

	// number of vehicles in france (all scales for now?) still available for the current tick, this number resets at the start of the tick, if it becomes negative -> new vehicles must be created to answer the demand
	// TODO: implement all the logic for resetting at each tick, and for creating new vehicles when in the negatives
	map<string, float> number_of_vehicles_available <- []; // initialized in setup()


	// name of the bloc :
	string name <- "transport";
	
	// production_agent and consumption_agent handling all production/consumption by this bloc
	transport_producer producer <- nil;
	transport_consumer consumer <- nil;
	
	// sets up the values of vaiables
	// sets up the bloc by creating the producers and consumers of the bloc (NB : these are not the other blocs but the production_agent and consumption_agent)
	action setup{
		loop v over:vehicles{
			number_of_vehicles[v] <- int(vehicle_data[v]["quantity"]);
			number_of_vehicles_available[v] <- vehicle_data[v]["quantity"];
		}

		list<transport_producer> producers <- [];
		list<transport_consumer> consumers <- [];
		create transport_producer number:1 returns:producers; // instanciate the transport production handler
		create transport_consumer number:1 returns: consumers; // instanciate the transport consumption handler
		producer <- first(producers);
		consumer <- first(consumers);
	}

	// every tick : we collect/reset the data to display from the producer and consumer
	// then we calculate the consumption in transports for the population (TODO: see if this is done here or by the Population bloc?)
	action tick(list<human> pop){
		do collect_last_tick_data();
		do population_activity(pop);
	}
	
	// action to set an other bloc to produce ressources for us (Energy Bloc as our producer of energy)
	action set_external_producer(string product, bloc bloc_agent){
		ask producer{
			do set_supplier(product, bloc_agent);
		}
	}
	
	// return the producer agent of the bloc
	production_agent get_producer{
		return producer;
	}
	
	// returns the labels for the ressources we create
	list<string> get_output_resources_labels{
		return production_outputs_T;
	}
	
	// returns the labels for the ressources we need
	list<string> get_input_resources_labels{
		return production_inputs_T;
	}

	// returns the labels for the emissions we create
	list<string> get_emissions_labels{
		return production_emissions_T;
	}
	
	// collects the data to display from the producer and consumer, then resets the values for the new tick to come
	action collect_last_tick_data{
		if(cycle > 0){ // skip it the first tick
			tick_pop_consumption_T <- consumer.get_tick_consumption(); // collect consumption behaviors
	    	tick_resources_used_T <- producer.get_tick_inputs_used(); // collect resources used
	    	tick_production_T <- producer.get_tick_outputs_produced(); // collect production
	    	tick_emissions_T <- producer.get_tick_emissions(); // collect emissions
	    	
	    	ask transport_consumer{ // prepare new tick on consumer side
	    		do reset_tick_counters;
	    	}
	    	
	    	ask transport_producer{ // prepare new tick on producer side
	    		do reset_tick_counters;
	    	}
    	}
	}
	
	// calculates the consumption in transports for the population (TODO: see if this is done here or by the Population bloc?)
	action population_activity(list<human> pop) {
		// TODO: this might be removed
    	ask pop{ // execute the consumption behavior of the population
    		ask myself.transport_consumer{
    			do consume(myself); // individuals consume transport goods
    		}
    	}
    	 
    	ask transport_consumer{ // produce the required quantities
    		ask transport_producer{
    			loop c over: myself.consumed.keys{
		    		bool ok <- produce([c::myself.consumed[c]]); // send the demands to the producer
		    		// note : in this example, we do not take into account the 'ok' signal.
		    	}
		    }
    	}
    }
	
	
	/**
	 * Agent qui s'occupe de toutes les production du bloc
	 * (I don't know if in the future there will be multiple of this agent for each scale, or if those will be sub agents of this agent)
	 */
	species transport_producer parent:production_agent{
		map<string, bloc> external_producers; // Energy Bloc 
		map<string, float> tick_resources_used <- []; // ressources used during this tick to make transport ressources (energy)
		map<string, float> tick_production <- []; // transport ressources created during this tick
		map<string, float> tick_emissions <- []; // emissions produced during this tick
		
		init{
			external_producers <- []; // external producers that provide the needed resources
		}
		
		/* Returns all the resources (energy) used for the production this tick */
		map<string, float> get_tick_inputs_used{
			return tick_resources_used;
		}
		
		/* Returns the amounts produced this tick */
		map<string, float> get_tick_outputs_produced{
			return tick_production;
		}
		
		/* Returns the amounts emitted this tick */
		map<string, float> get_tick_emissions{
			return tick_emissions;
		}
		
		/* Defines an external producer for a resource (Energy Bloc) */
		action set_supplier(string product, bloc bloc_agent){
			write name+": external producer "+bloc_agent+" set for "+product;
			external_producers[product] <- bloc_agent;
		}
		
		// reset the values for the new tick to come
		action reset_tick_counters{ // reset impact counters
			loop u over: production_inputs_T{
				tick_resources_used[u] <- 0.0; // reset resources usage
			}
			loop p over: production_outputs_T{
				tick_production[p] <- 0.0; // reset productions
			}
			loop e over: production_emissions_T{
				tick_emissions[e] <- 0.0;
			}
		}
		
		// returns the vehicle used by a person based on the distance travelled
		// TODO: improve modelisation by using accurate numbers, maybe even take the quantity of people in parameter and return a proportion of the usage for each vehicle based on the distance 
		string get_vehicle_used(float distance){
			if (distance < 0.2) {
				return "walk";
			}
			else if (distance < 1.0){
				return "bicycle";
			}
			else if (distance < 4.0){
				return "minibus";
			}
			else if (distance < 50.0){
				return "taxi";
			}
			else {
				return "train";
			}
		}
		
		// produce ressources to answer a demand in transport 
		bool produce(map<string,float> demand){
			bool global_success <- true;
			
			// Temp variable to accumulate needs of this tick
			float total_energy_needed <- 0.0;
			
			loop service over: demand.keys{
				float quantity_asked <- demand[service]; // already in km*pers or km*kg
				
				tick_production[service] <- tick_production[service] + quantity_asked; // "we have produced this service"
				
				map<string, float> split <- modal_split[service]; // get vehicle mix for this service
				
				if (split != nil) {
					loop vehicle_name over: split.keys {
						float share <- split[vehicle_name];
						float sub_quantity <- quantity_asked * share;
						
						map<string, float> specs <- vehicle_data[vehicle_name];
						
						// (Total charge * Distance) / Avg Capacity = Cumulated vehicule distances
						float vehicle_km <- sub_quantity / specs["capacity"];
						
						total_energy_needed <- total_energy_needed + (vehicle_km * specs["consumption"]);
						float emissions <- vehicle_km * specs["emissions"];
						tick_emissions["gCO2e emissions"] <- tick_emissions["gCO2e emissions"] + emissions;
					}
				}
			}
			tick_resources_used["kWh energy"] <- tick_resources_used["kWh energy"] + total_energy_needed;
			
			if (total_energy_needed > 0 and external_producers contains_key "kWh energy"){
				// Here we ask Energy for electricity. I don't know if this will be how we do it in the end.
				bool energy_ok <- external_producers["kWh energy"].producer.produce(["kWh energy"::total_energy_needed]);
				if (!energy_ok) {
					global_success <- false;
					// BAD not enough energy !! or smth
				}
			}
			
			return global_success;
		}
	}
	
	/**
	 * Species used to detail the consumption behavior of the population, related to the bloc.
	 * TODO: figure out what we should actually do here ?
	 */
	species transport_consumer parent:consumption_agent{
	
		map<string, float> consumed <- [];
		
		map<string, float> get_tick_consumption{
			return copy(consumed);
		}
		
		init{
			loop c over: production_outputs_T{
				consumed[c] <- 0;
			}
		}
		
		action reset_tick_counters{ // reset choices counters
			loop c over: consumed.keys{
				consumed[c] <- 0;
			}
		}
		
		action consume(human h){
		    loop c over: indivudual_consumption_T.keys{
		    	consumed[c] <- consumed[c]+indivudual_consumption_T[c];
		    }
	    }
	}
}

/**
 * We define here the experiment and the displays related to transport. 
 * We will then be able to run this experiment from the Main code of the simulation, with all the blocs connected.
 * 
 * Note : experiment car inherit another experiment, but we can't combine displays from multiple experiments at the same time. 
 * If needed, a new experiment combining all those displays should be added, for example in the Main code of the simulation.
 * TODO: modify it to display the data we actually want
 */
experiment run_transport type: gui {
	output {
		display Transport_information {
			chart "Population direct consumption (Demand)" type: series size: {0.5,0.5} position: {0, 0} {
			    loop c over: production_outputs_T {
			    	// show km per scale
			    	data c value: tick_pop_consumption_T[c]; 
			    }
			}
			
			chart "Total production (Service realized)" type: series size: {0.5,0.5} position: {0.5, 0} {
			    loop c over: production_outputs_T {
			    	data c value: tick_production_T[c];
			    }
			}
			
			chart "Resources usage (Energy)" type: series size: {0.5,0.5} position: {0, 0.5} {
			    loop r over: production_inputs_T {
			    	// Affiche les kWh consommés
			    	data r value: tick_resources_used_T[r] color: #red;
			    }
			}
			
			chart "Production emissions (CO2)" type: series size: {0.5,0.5} position: {0.5, 0.5} {
			    loop e over: production_emissions_T {
			    	data e value: tick_emissions_T[e] color: #black;
			    }
			}
	    }
	}
}
