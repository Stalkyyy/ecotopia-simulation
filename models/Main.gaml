/**
* Name: Main (MOSIMA)
* Authors: Maël Franceschetti, Cédric Herpson, Jean-Daniel Kant
* Mail: firstname.lastname@lip6.fr
*/

model Main

import "API/API.gaml"
import "blocs/Demography.gaml"
import "blocs/Agricultural.gaml"
import "blocs/Energy.gaml"

/**
 * This is the main section of the simulation. Here, we instanciate our blocs, and launch the simulation through the coordinator.
 */
global{

	float step <- 1 #month; // the simulation step is a month
	
	init{
		// instanciate the blocs (E, A and R blocs here):
		create residents number:1;
		create agricultural number:1;
		create energy number:1;

		create coordinator number:1; // instanciate the coordinator
		ask coordinator{ 
			do register_all_blocs; // register the blocs in the coordinator
			do start; // start the simulation
		}
	}

}

