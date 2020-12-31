/*
This file is part of Giswater 3
The program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This version of Giswater is provided by Giswater Association
*/

--FUNCTION CODE: 3010


CREATE OR REPLACE FUNCTION ud_sample.gw_fct_anl_drained_flows(p_intensity)
  RETURNS void AS

$BODY$

/*

INSTRUCTIONS
------------
Before to execute this function anl_drained tables must be filled at least with:
arc table: arc_id, max_flow, isflowreg
node table: node_id, node_area, imperv, hasflowreg, flowreg_initflow

The propagation of drained parameters has two special characteristics:

1) Drainage parameters distribution on nodes whith more than one outlet conduit

	- If max_flow of all outlet conduits is provided (wet conduits)
		- If node has flowregulator
			- flowreg_initflow in combination with mannings capacity weightweing
		
		- Else
			- Mannings capacity weightweing
		
	- Else (If there is some conduit without max_flow):
		- For non-wet conduits -> Linear distribution (wet conduits / total conduits)
		- For wet conduits, mannings capacity weightweing


2) Flow limitation in terms of arc maximun mannings capacity
	- Real flow is maximun againts (conduit max flow and flow provided for the upstream node)

*/


DECLARE
v_node_id varchar(16);
v_row integer = 0;
v_num_outlet integer= 0;
v_num_wet_outlet integer= 0;

BEGIN

	-- search path
	SET search_path = "ud_sample", public;
	
	
	--	Filling anl_drained_flows_node table
	FOR v_node_id IN SELECT node_id FROM node
	LOOP

		-- Count number of pipes draining the node
		SELECT count(*) INTO v_num_outlet FROM arc WHERE node_1 = v_node_id;

		-- Count number of wet pipes draining the node
		SELECT count(*) INTO v_num_wet_outlet FROM arc WHERE node_1 = v_node_id AND flow > 0.0;

		-- Compute total capacity of the pipes exiting from the node
		SELECT sum(flow) INTO v_max_discharge_capacity FROM arc WHERE node_1 = v_node_id;
		
		INSERT INTO anl_drained_flows_node VALUES(node_id_var, 0.0, 0, v_max_discharge_capacity, v_num_outlet, v_num_wet_outlet);

	END LOOP;
	
	--	Compute the tributary area using DFS
	FOR v_node_id IN SELECT node_id FROM anl_drained_flows_node
	LOOP
		v_row = v_row + 1;

		-- Call function
		PERFORM gw_fct_anl_drained_flows_recursive(v_node_id, v_row, p_intensity);

	END LOOP;
		
END;$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100;
