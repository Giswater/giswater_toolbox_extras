/*
This file is part of Giswater 3
The program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This version of Giswater is provided by Giswater Association
*/

--FUNCTION CODE: 3007


CREATE OR REPLACE FUNCTION ud_sample.gw_fct_anl_drainedflows()
  RETURNS void AS
  
$BODY$

DECLARE
node_id_var varchar(16);
arc_id_var varchar(16);
index_point integer;
point_aux geometry;
num_row integer = 0;
flow_node double precision;
total_capacity double precision;
arc_capacity double precision;
rec_table record;
num_pipes integer;
num_wet_pipes integer;

BEGIN

	-- search path
	SET search_path = "ud_sample", public;

--	Create table for arc results
	DROP TABLE IF EXISTS anl_drainedflows_arc CASCADE;
	CREATE TABLE anl_drainedflows_arc
	(
		arc_id character varying(16) NOT NULL,
		area -- area en m2 del conducte
		wetper -- perimetre mullat del coducte
		slope -- pendent del conducte
		maxflow numeric(12,4) DEFAULT 0.00, -- cabal que pot suportar canonada segons manning a secció plena (a partir de valors anteriors)
		isflowreg boolean DEFAULT false, -- es regulador de fluxe, es una variable que va de la ma del camp hasflowreg de la taula runoff_node_flow

		flow numeric(12,4) DEFAULT 0.00, -- cabal real traspassat
		CONSTRAINT runoff_arc_flow_pkey PRIMARY KEY (arc_id),
		CONSTRAINT runoff_arc_flow_arc_id_fkey FOREIGN KEY (arc_id)
			REFERENCES arc (arc_id) MATCH SIMPLE
			ON UPDATE CASCADE ON DELETE CASCADE
	)
	WITH (
		OIDS=FALSE
	);
	
--	Create the temporal table for computing
	DROP TABLE IF EXISTS anl_drainedflows_node CASCADE;
	CREATE TEMP TABLE anl_drainedflows_node
	(		
		node_id character varying(16) NOT NULL,
		nodearea double precision  DEFAULT 0
		imperv double precision  DEFAULT 0
		intensity double precision  DEFAULT 0
		wwflow double precision  DEFAULT 0
		inhabitants integer  DEFAULT 0
		dph double precision  DEFAULT 0
		dwflow double precision  DEFAULT 0
		totalflow numeric(12,4) DEFAULT 0.00, -- cabal generat en el node
		hasflowreg boolean DEFAULT false, -- el node disposa de reguladors de fluxe: Si és true, els reguladors de fluxe han de ser tants com noutlet menys 1 i cal identificarlos runoff_arc_flow -> condició de càlcul, es així
		flowreqinit double precision, -- llindar a partir del qual el(s) regulador(s) de fluxe entra en joc
		
		capacityflow numeric(12,4) DEFAULT 0.00, -- capacitat maxima de desguas de node, sumant les capacitats de cada un dels arcs que desguassan
		noutlet integer DEFAULT 0,  -- num total de trams sortida
		nwetoutlet integer DEFAULT 0, -- num total de trams mullables (tenen cabal assignat)
		ftrack_id integer DEFAULT 0, -- flag
		CONSTRAINT runoff_node_flow_pkey PRIMARY KEY (node_id)
	);


--	Copy nodes into new area table
	FOR node_id_var IN SELECT node_id FROM node
	LOOP

--		Count number of pipes draining the node
		SELECT count(*) INTO num_pipes FROM arc WHERE node_1 = node_id_var;

--		Count number of pipes draining the node
		SELECT count(*) INTO num_wet_pipes FROM arc WHERE node_1 = node_id_var AND flow > 0.0;

--		Compute total capacity of the pipes exiting from the node
		SELECT sum(flow) INTO total_capacity FROM arc WHERE node_1 = node_id_var;

--		Compute total capacity of the pipes exiting from the node
		SELECT sum(flow) INTO total_capacity FROM arc WHERE node_1 = node_id_var;
		INSERT INTO runoff_node_flow VALUES(node_id_var, 0.0, 0, total_capacity, num_pipes, num_wet_pipes);

	END LOOP;

--	Copy arcs into new area table
	FOR arc_id_var IN SELECT arc_id FROM arc
	LOOP

--		Insert into nodes area table
		INSERT INTO runoff_arc_flow VALUES(arc_id_var, 0.0);

	END LOOP;


--	Compute the tributary area using DFS
	FOR node_id_var IN SELECT node_id FROM runoff_node_flow
	LOOP
		num_row = num_row + 1;

--		Call function
		flow_node := gw_fct_anl_hydraulics_recursive(node_id_var, num_row, intensity);

	END LOOP;
		
END;$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100;
