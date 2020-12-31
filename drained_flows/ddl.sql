/*
This file is part of Giswater 3
The program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This version of Giswater is provided by Giswater Association
*/


CREATE TABLE anl_drained_flows_arc
(
	arc_id character varying(16) NOT NULL,
	area double precision  DEFAULT 0.00,-- area en m2 del conducte
	wetper double precision  DEFAULT 0.00,-- perimetre mullat del coducte
	slope double precision  DEFAULT 0.00,-- pendent del conducte
	max_flow numeric(12,4) DEFAULT 0.00, -- cabal que pot suportar canonada segons manning a secció plena (a partir de valors anteriors)
	flowreg boolean DEFAULT false, -- es regulador de fluxe, es una variable que va de la ma del camp hasflowreg de la taula runoff_node_flow

	drained_area  double precision  DEFAULT  0.00, -- area total drenada pel arc, sense tenir en compte el coeficient de runoff
	runoff_area  double precision  DEFAULT  0.00, -- area efectiva drenada pel arc, aplicant el coefficient de runoff
	runoff_flow double precision  DEFAULT  0.00, -- cabal drenat teoric corresponent al cabal efectiu, en cas que no hi hagues limitacions de xarxa
	real_flow numeric(12,4) DEFAULT 0.00, -- cabal drenat real per culpa de les limitacions de xarxa
	CONSTRAINT anl_drainedf_lows_arc_pkey PRIMARY KEY (arc_id),
	CONSTRAINT anl_drained_flows_arc_fkey FOREIGN KEY (arc_id)
		REFERENCES arc (arc_id) MATCH SIMPLE
		ON UPDATE CASCADE ON DELETE CASCADE
)


CREATE TABLE anl_drained_flows_node
(		
	node_id character varying(16) NOT NULL,
	node_area double precision  DEFAULT 0.00,
	imperv double precision  DEFAULT  0.00,
	inhabitants integer  DEFAULT  0,
	dph double precision  DEFAULT  0.00,
	dw_flow double precision  DEFAULT  0.00,
	hasflowreg boolean DEFAULT false, -- el node disposa de reguladors de fluxe: Si és true, els reguladors de fluxe han de ser tants com num outlet menys 1 i cal identificarlos runoff_arc_flow -> condició de càlcul, es així
	flowreg_initflow double precision, -- llindar a partir del qual el(s) regulador(s) de fluxe entra en joc
	
	node_inflow numeric(12,4) DEFAULT 0.00, -- cabal generat en el node (sumatori de dph + node_area*imperv*intensity)
	max_discharge_capacity numeric(12,4) DEFAULT 0.00, -- capacitat maxima de desguas de node, sumant les capacitats de cada un dels arcs que desguassan
	num_outlet integer DEFAULT 0,  -- num total de trams sortida
	num_wet_outlet integer DEFAULT 0, -- num total de trams mullables (tenen cabal assignat)
	track_id integer DEFAULT 0, -- flag
	
	drained_area  double precision  DEFAULT  0.00, -- area total drenada pel node, sense tenir en compte el coeficient de runoff
	runoff_area  double precision  DEFAULT  0.00, -- area efectiva drenada pel node, aplicant el coefficient de runoff
	runoff_flow double precision  DEFAULT  0.00, -- cabal drenat teoric corresponent al cabal efectiu, en cas que no hi hagues limitacions de xarxa
	real_flow numeric(12,4) DEFAULT 0.00, -- cabal drenat real per culpa de les limitacions de xarxa
	
	CONSTRAINT anl_drained_flows_node_pkey PRIMARY KEY (node_id)
);