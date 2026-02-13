# Mosima project : Ecotopia

## Table of contents

- [Mosima project : Ecotopia](#mosima-project--ecotopia)
    - [Table of contents](#table-of-contents)
    - [Overview](#overview)
    - [Notes](#notes)
    - [Core blocs modeled](#core-blocs-modeled)
    - [Requirements](#requirements)
    - [Run the simulation](#run-the-simulation)

## Overview

This project implements the core structure of a multi-agents simulation that aims to scientifically assess an alternative sustainable society over a 50-100 year time horizon.
The proposed normative approach makes it possible to experiment with models of fictive societies _a priori_ perceived as "ideal" which that could inspire our current world, while maintaining a scientific approach.

The book Ecotopia, written by Ernest Callenbach in 1975, describes a utopian society centred on respect for nature and individual and social well-being in which the primary objective is no longer development but the maintenance of ecological balance.
As climate change looms, the society described within Ecotopia presents an interesting test-case.

https://github.com/user-attachments/assets/311e0185-0be0-4a69-a2ae-8107c82f7aee

The project is written using the [GAMA platform](https://gama-platform.org/).

This project builds upon a base framework provided by the [Ecotopia MWI project](https://gitlab.com/ecotopia/mwi).

## Notes
- The model is calibrated to France 2022 for initial orders of magnitude.
- Results should be interpreted as scenario exploration, not forecasts.
- This is a college project developed over multiple months by a team of 11 students. 

## Core blocs modeled
- Demography : population dynamics, consumption needs, births/deaths...
- Agriculture : food and cotton production, stocks, fertilizer effects...
- Energy : production mix, maintenance cycles, demand allocation...
- Transport : energy and material requirements...
- Urbanism : housing capacity, land constraints...
- Ecosystem : water/land/wood stocks and regeneration...

## Requirements
- [GAMA platform](https://gama-platform.org/)

## Run the simulation
1. Open GAMA.
2. Import this folder as a GAMA project.
3. Open `models/Main.gaml`.
4. Run the desired experiment.
