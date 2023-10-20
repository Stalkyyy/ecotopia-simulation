/**
* Name: Demography bloc (MOSIMA)
* Authors: Maël Franceschetti, Cédric Herpson, Jean-Daniel Kant
* Mail: firstname.lastname@lip6.fr
*/

model Demography

import "../API/API.gaml"

/**
 * We define here the global variables of the bloc. Some are needed for the displays (charts, series...).
 */
global{
	/* Setup */ 
	int nb_ticks_per_year <- 12; // here, one tick is one month
	string female_gender <- "F";
	string male_gender <- "M";
	
	/* Input data (data for 2018, source : INSEE) */ 
	map<string, float> init_gender_distrib <- [male_gender ::0.4839825904115131, female_gender ::0.516017409588487];
	map<string, map<int, float>> init_age_distrib <- [ // initial ages distribution for each gender
		male_gender::
			[0:: 0.011246078139754524, 1:: 0.011563507250731558,2:: 0.0118803946738059,3:: 0.012202603383924327,4:: 0.012428136735409517,
			5:: 0.01274887970179125,6:: 0.012829145103372373,7:: 0.013214380794168635,8:: 0.013103780870036804,9:: 0.013220721729029548,10:: 0.01305021749565893,
			11:: 0.013243504484936854,12:: 0.012990982330299935,13:: 0.012940732811326757,14:: 0.012899054706813812,15:: 0.013051428327441415,16:: 0.013302484738341641,
			17:: 0.013534295296699193,18:: 0.012700988118394494,19:: 0.01246423864092417,20:: 0.011994212861359602,21:: 0.011965152898579934,22:: 0.011743443226407859,
			23:: 0.011260735577121461,24:: 0.011188340582126498,25:: 0.011595307517018958,26:: 0.011740957834854335,27:: 0.011965598994499796,28:: 0.011932683488412739,
			29:: 0.012126225389644871,30:: 0.012126798941541839,31:: 0.012334297272266839, 32:: 0.012312151796245051,33:: 0.012245970280133899,34:: 0.012098216938676309,
			35:: 0.012917472095505313,36:: 0.013088103784853035,37:: 0.013266510288804092,38:: 0.01259207698595929,39:: 0.012391620597969276,40:: 0.012484504141283676,
			41:: 0.012152417592939703,42:: 0.012575826348878555,43:: 0.013250291515717633,44:: 0.013908760957430181,45:: 0.014267358349011746,46:: 0.014220454549437545,
			47:: 0.013875781723354571,48:: 0.013646106052613509,49:: 0.013414072446296025,50:: 0.013399892968843228,51:: 0.013687115013246659,52:: 0.013682367278099542,
			53:: 0.013758044264504929,54:: 0.01352212325088578,55:: 0.013051810695372727,56:: 0.013049771399739066,57:: 0.012904280401875069,58:: 0.012819904545032347,
			59:: 0.01245283133097338,60:: 0.012353192620872477,61:: 0.012149103737535005,62:: 0.011966937282259386,63:: 0.011910378692419572,64:: 0.011648647843436902,
			65:: 0.011760713511305424,66:: 0.011449657199183581,67:: 0.011835785081819568,68:: 0.011553852460465945,69:: 0.011484197768978712,70:: 0.011170209969383482,
			71:: 0.010400949419573447,72:: 0.007681994788006456,73:: 0.007462547459427975,74:: 0.0071687614322036965,75:: 0.006549484703450568,76:: 0.005707733566662742,
			77:: 0.005779395689789358,78:: 0.005880882511558266,79:: 0.005601817649689478,80:: 0.005304813359043328,81:: 0.00508147862316318,82:: 0.0046540868679398354,
			83:: 0.004455956551531965,84:: 0.004000651937322886,85:: 0.0037777314333683255,86:: 0.0033336429451443815,87:: 0.002951848565729924,88:: 0.00241321960648923,
			89:: 0.00204726163222992,90:: 0.001690544216310637,91:: 0.0013617077953828117,92:: 0.0010938590594991586,93:: 0.0008259784596212295,94:: 0.0006241519198773491,
			95:: 0.0004483901274511975,96:: 0.0003380132512792995,97:: 0.00022473675162828995,98:: 9.09398396635672e-05,99:: 5.056815891593593e-05,100:: 2.9251146745324e-05,
			101:: 1.6155045097907698e-05,102:: 1.1375445956514889e-05,103:: 1.201272584203393e-05,104:: 6.78703078077779e-06,105:: 1.3446605584451773e-05],
		female_gender::
			[0:: 0.010151326399736623,1:: 0.010389695933002142,2:: 0.010642350902188038,3:: 0.011065534526942273,4:: 0.011152621891527995,
			5:: 0.01137114722092086,6:: 0.011561340765266619,7:: 0.011877861794205325,8:: 0.011710381495255981,9:: 0.011801085047595606,10:: 0.011703657179184673,
			11:: 0.011903623396220732,12:: 0.011610502987210171,13:: 0.011571173209655328,14:: 0.011565076496417344,15:: 0.011630018446741565,16:: 0.011790087055087868,
			17:: 0.01189492661410184,18:: 0.01123014578436786,19:: 0.011132030541425194,20:: 0.010744739821567135,21:: 0.010839149219208281,22:: 0.010721309315789782,
			23:: 0.010456132175786653,24:: 0.010435032766247352,25:: 0.010900325552532569,26:: 0.011087679941203776,27:: 0.011357011214246513,28:: 0.011578913644599634,
			29:: 0.011801174705143223,30:: 0.011914442073633234,31:: 0.012168800536223861,32:: 0.01215454498615269,33:: 0.012053530815837061,34:: 0.011912170749093592,
			35:: 0.012639472775366123,36:: 0.012775064873212871,37:: 0.012951660356169988,38:: 0.012221937576111787,39:: 0.01192409520292671,40:: 0.011955116714402338,
			41:: 0.011657931829899788,42:: 0.011963903154068844,43:: 0.012597064755343081,44:: 0.013302878856036636,45:: 0.013554577478047947,46:: 0.013478906507858842,
			47:: 0.013231063160395082,48:: 0.013078794758691493,49:: 0.01295213852975728,50:: 0.012886150574710858,51:: 0.013207303910276464,52:: 0.013250070560489975,
			53:: 0.01343772380765324,54:: 0.013260231749219949,55:: 0.012821597140426313,56:: 0.012872761714266656,57:: 0.012841202257505324,58:: 0.012827006479132564,
			59:: 0.012593089937398709,60:: 0.012533467668233123,61:: 0.012474263800956419,62:: 0.012402418219465658,63:: 0.012313268731284735,64:: 0.012081533856542903,
			65:: 0.012279946009420258,66:: 0.011954010937981723,67:: 0.012344439672006392,68:: 0.012144832085160803,69:: 0.012074480796130332,70:: 0.01181829929673815,
			71:: 0.01118259739828142,72:: 0.008427480731696442,73:: 0.008218907390089111,74:: 0.007989802470077391,75:: 0.0073526959367079875,76:: 0.006577486894158548,
			77:: 0.006845981363423522,78:: 0.007212112902043869,79:: 0.0070157927586109205,80:: 0.006868545179573906,81:: 0.006801780192448132,82:: 0.0065583300648176255,
			83:: 0.006523004991056361,84:: 0.006087657825675364,85:: 0.006054663848152152,86:: 0.005622036295048883,87:: 0.005298820835888075,88:: 0.004561686365226835,
			89:: 0.00416145507266266,90:: 0.003607849601974283,91:: 0.0031861602696803396,92:: 0.0027087039427683597,93:: 0.0022212956280708456,94:: 0.001823425317593931,
			95:: 0.0014579811535053173,96:: 0.0011475867236538009,97:: 0.0008539881410559484,98:: 0.00037327425658053524,99:: 0.00023074864171803943,100:: 0.000144049793171992,
			101:: 8.601147401431388e-05,102:: 6.48224069273964e-05,103:: 6.20729088004621e-05,104:: 3.711822471361287e-05,105:: 5.182206252287015e-05]
	];
	map<string, map<int, float>> death_proba <- [ // probabilities to die in a year for each gender (per individual)
  		male_gender::
		    [0:: 0.003600,1:: 0.000260,5:: 0.000080,10:: 0.000090,15:: 0.000270,20:: 0.000590,25:: 0.000650,30:: 0.000820,
		    35:: 0.001170,40:: 0.001650,45:: 0.002670,50:: 0.004290,55:: 0.006900,60:: 0.010700,65:: 0.014900,70:: 0.024900,
		    80:: 0.073500,90:: 0.215000,105:: 1.0],
	  	female_gender::[0:: 0.0029,1:: 0.00022,5:: 0.000070,10:: 0.000070,15:: 0.000130,20:: 0.000190,25:: 0.000250,
	  		30:: 0.000340,35:: 0.000510,40:: 0.000890,45:: 0.001430,50:: 0.002280,55:: 0.003500,60:: 0.005000,65:: 0.006900,
		    70:: 0.012800,80:: 0.048500,90:: 0.171000,105:: 1.0]
	]; 
	map<int, float> birth_proba <- [ // probabilities to give birth in a year (per female)
		  0:: 0.0,15:: 0.00457,20:: 0.0401,25:: 0.10859,30:: 0.12673,35:: 0.06878,40:: 0.01817,45:: 0.00124,50:: 0.0
	];
	
	/* Parameters */ 
	float coeff_birth <- 1.0; // a parameter that can be used to increase or decrease the birth probability
	float coeff_death <- 1.0; // a parameter that can be used to increase or decrease the death probability
	int nb_init_individuals <- 10000; // pop size
	
	/* Counters & Stats */
	int nb_inds -> {length(individual)};
	float births <- 0; // counter, accumulate the total number of births
	float deaths <- 0; // counter, accumulate the total number of deaths
	
	init{ // a security added to avoid launching an experiment without the other blocs
		if (length(coordinator) = 0){
			error "Coordinator agent not found. Ensure you launched the experiment from the Main model";
			// If you see this error when trying to run an experiment, this means the coordinator agent does not exist.
			// Ensure you launched the experiment from the Main model (and not from the bloc model containing the experiment).
		}
	}
}


/**
 * We define here the content of the demography (or "resident") bloc as a species.
 * We implement the methods of the API. Some are empty (do nothing) because this bloc do not have consumption nor production.
 * We also add methods specific to this bloc to handle the births and deaths in the population.
 */
species residents parent:bloc{
	string name <- "residents";
	bool enabled <- false; // true to activate the demography (births, deaths), else false.
	
	action setup{
		do init_population;
	}
	
	action tick(list<human> pop){
		do collect_last_tick_data;
		if(enabled){
			do update_births;
			do update_deaths;
			do increment_age;
		}
	}
	
	list<string> get_input_resources_labels{ 
		return [];
	}
	
	list<string> get_output_resources_labels{
		return [];
	}
	
	production_agent get_producer{
		return nil;
	}
	
	action collect_last_tick_data{ // update stats & measures
		int nb_men <- individual count(not dead(each) and each.gender = male_gender);
		int nb_woman <-  individual count(not dead(each)) - nb_men;
	}
	
	action population_activity(list<human> pop){
		// do nothing
	}
	
	action set_external_producer(string product, production_agent prod_agent){
		// do nothing
	}
	
	action init_population{
		create individual number:nb_init_individuals{
			gender <- rnd_choice(init_gender_distrib); // override gender, pick a gender with respect to the real distribution
			age <- rnd_choice(init_age_distrib[gender]);  // pick an initial age with respect to the real distribution and gender
			do update_demog_probas;
		}
	}

	action update_births{
		int new_births <- 0;
		ask individual{
			if(ticks_before_birthday<=0){ // check only once a year
				if(gender = female_gender and flip(p_birth)){ // women can have children
					new_births <- new_births + 1;
				}
			}
		}
		int nb_f <- individual count(each.gender=female_gender and not(dead(each)));
		create individual number:new_births;
		births <- births + new_births;
	}
	
	action update_deaths{
		ask individual{
			if(ticks_before_birthday<=0){ // check only once a year
				if(flip(p_death)){ // every individual has a chance to die every month, or die by reaching max_age
					deaths <- deaths +1;
					do die;
				}
			}
		}
	}
	
	action increment_age{
		ask individual{
			if(ticks_before_birthday<=0){ // if the current tick is the individual birth date, increment the age
				age <- age +1;
				ticks_before_birthday <- nb_ticks_per_year;
				do update_demog_probas; // update the death and birth probabilities
			}
			else{
				ticks_before_birthday <- ticks_before_birthday -1;
			}
		}
	}

}

/**
 * We define the agents used in the demography bloc. We here extends the 'human' species of the API to add some functionalities.
 * Be careful to define features that will only be called within the demography block, in order to respect the API.
 * 
 * The demography of our population will here be based on death and birth probabilities.
 * These probabilities will depend on somme attributes of the individuals (age, gender ...).
 * We propose some formulas for these probabilities, based on INSEE data. These are rough estimates.
 */
species individual parent:human{
	float p_death <- 0.0;
	float p_birth <- 0.0;
	int ticks_before_birthday <- 0;
	int delay_next_child <- 0;
	int child <- 0;
	
	init{
		gender <- one_of ([female_gender, male_gender]); // pick a gender randomly
	    ticks_before_birthday <- rnd(nb_ticks_per_year); // set a random birth date in the year (uniformly)
	    // set initial birth & death probabilities :
	    p_birth <- get_p_birth(); 
		p_death <- get_p_death();
	}
	
	float get_p_death{ // compute monthly death probability of an individual
		int age_cat <- get_age_category(death_proba[gender].keys);
		float p_death <-  death_proba[gender][age_cat];
		return  p_death * coeff_death;
	}
	
	int get_age_category(list<int> ages_categories){
		int age_cat <- max(ages_categories where (each <= age)); // get the last age category with a lower bound inferior to the age
		return age_cat;
	}
	
	float get_p_birth{
		if(gender = male_gender){ // male don't give birth
			return 0.0;
		}
		int age_cat <- get_age_category(birth_proba.keys);
		float p_birth <-  birth_proba[age_cat];
		return p_birth * coeff_birth;
	}
	
	action update_demog_probas{
		p_birth <- get_p_birth();
		p_death <- get_p_death();
	}
}

/**
 * We define here the experiment and the displays related to demography. 
 * We will then be able to run this experiment from the Main code of the simulation, with all the blocs connected.
 * 
 * Note : experiment car inherit another experiment, but we can't combine displays from multiple experiments at the same time. 
 * If needed, a new experiment combining all those displays should be added, for example in the Main code of the simulation.
 */
experiment run_demography type: gui {
	parameter "Initial number of individuals" var: nb_init_individuals min: 0 category: "Initialisation";
	parameter "Coefficient for birth probability" var: coeff_birth min: 0.0 max: 10.0 category: "Demography";
	parameter "Coefficient for death probability" var: coeff_death min: 0.0 max: 10.0 category: "Demography";
	parameter "Number of ticks per year" var: nb_ticks_per_year min:1 category: "Simulation";

	output {
		display Population_information {
			chart "Gender evolution" type: series size: {0.5,0.5} position: {0, 0} {
				data "number_of_man" value: individual count(not dead(each) and each.gender = male_gender) color: #red;
				data "number_of_woman" value: individual count(not dead(each) and each.gender = female_gender) color: #blue;
				data "total_individuals" value: individual count(not dead(each)) color: #black;
			}
			chart "Age Pyramid" type: histogram background: #lightgray size: {0.5,0.5} position: {0, 0.5} {
				data "]0;15]" value: individual count (not dead(each) and each.age <= 15) color:#blue;
				data "]15;30]" value: individual count (not dead(each) and (each.age > 15) and (each.age <= 30)) color:#blue;
				data "]30;45]" value: individual count (not dead(each) and (each.age > 30) and (each.age <= 45)) color:#blue;
				data "]45;60]" value: individual count (not dead(each) and (each.age > 45) and (each.age <= 60)) color:#blue;
				data "]60;75]" value: individual count (not dead(each) and (each.age > 60) and (each.age <= 75)) color:#blue;
				data "]75;90]" value: individual count (not dead(each) and (each.age > 75) and (each.age <= 90)) color:#blue;
				data "]90;105]" value: individual count (not dead(each) and (each.age > 90) and (each.age <= 105)) color:#blue;
			}
			chart "Births and deaths" type: series size: {0.5,0.5} position: {0.5, 0} {
				data "number_of_births" value: births color: #green;
				data "number_of_deaths" value: deaths color: #black;
			}
		}
	}
}




