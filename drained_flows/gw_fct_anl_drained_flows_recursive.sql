/*
This file is part of Giswater 3
The program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This version of Giswater is provided by Giswater Association
*/

--FUNCTION CODE: 3012

CREATE OR REPLACE FUNCTION SCHEMA_NAME.gw_fct_anl_drained_flows_recursive( p_node character varying, p_row integer, p_intensity double precision)
  RETURNS json AS
  
$BODY$

/*
SELECT gw_fct_anl_drained_flows(100);
*/

DECLARE

-- node parameters
v_track_id integer = 0;
v_max_capacity double precision= 0.00;
v_num_outlet double precision = 0;
v_num_wet_outlet double precision = 0;
v_node_drained_area double precision = 0.00;
v_node_runoff_area double precision = 0.00;
v_node_runoff_flow double precision = 0.00;
v_imperv double precision = 0.00;


-- upstream parameters
v_ups_drained_area double precision = 0.00;
v_ups_runoff_area double precision = 0.00;
v_ups_runoff_flow double precision = 0.00;
v_ups_real_flow double precision = 0.00;
v_hasflowreg boolean = FALSE;
v_flowreg_initflow  double precision = 0.00;
v_weight double precision = 0.00; 

-- arc parameters
v_arc_capacity double precision = 0.00;
rec_arc record;
v_flowreg double precision = 0.00;

-- return parameters
v_tot_drained_area double precision = 0.00; 
v_tot_runoff_area double precision = 0.00;
v_tot_runoff_flow double precision = 0.00;
v_tot_real_flow double precision = 0.00;
v_return json;


BEGIN

	-- Search path
	SET search_path = "SCHEMA_NAME", public;

	-- Get values from anl_drained_flows_node
	SELECT track_id, node_area, imperv INTO v_track_id, v_node_drained_area, v_imperv FROM anl_drained_flows_node WHERE node_id = p_node;

	-- Null controls
	IF v_node_drained_area = NULL THEN v_node_drained_area = 0; END IF;
	IF v_imperv = NULL THEN v_imperv = 0; END IF;

	-- Compute node runoff area and node flow
	v_node_runoff_area = v_node_drained_area * v_imperv/100::numeric;
	v_node_runoff_flow = (v_node_runoff_area) * p_intensity / 360::numeric;

	

	--	Compute area
	IF (v_track_id = 0) THEN
	
		-- Update tracking value
		UPDATE anl_drained_flows_node SET track_id = p_row WHERE node_id = p_node;
		
		-- Loop for all the upstream nodes
		FOR rec_arc IN SELECT arc_id, full_flow, node_1 FROM arc a JOIN anl_drained_flows_arc d USING (arc_id) WHERE node_2 = p_node
		LOOP

			--raise notice ' NODE: % , ARC: %', p_node, rec_arc.arc_id;
		
			-- Get max discharge capacity of the upstream node
			SELECT max_discharge_capacity INTO v_max_capacity FROM anl_drained_flows_node WHERE node_id = rec_arc.node_1;
			IF v_max_capacity = NULL THEN v_max_capacity = 0; END IF;

			-- Getting Total number of upstream arcs (wet and total) from upstream node
			SELECT num_outlet::numeric, num_wet_outlet::numeric INTO v_num_outlet, v_num_wet_outlet FROM anl_drained_flows_node WHERE node_id = rec_arc.node_1;
			
			-- Getting flowregulator parameters
			SELECT hasflowreg, flowreg_initflow INTO v_hasflowreg, v_flowreg_initflow FROM anl_drained_flows_node WHERE node_id = rec_arc.node_1;
						
			-- Getting drained values from upstream node
			v_ups_drained_area := (gw_fct_anl_drained_flows_recursive(rec_arc.node_1, p_row, p_intensity)->>'drainedArea')::double precision;
			v_ups_runoff_area :=  (gw_fct_anl_drained_flows_recursive(rec_arc.node_1, p_row, p_intensity)->>'runoffArea')::double precision;
			v_ups_runoff_flow :=  (gw_fct_anl_drained_flows_recursive(rec_arc.node_1, p_row, p_intensity)->>'runoffFlow')::double precision;
			v_ups_real_flow := (gw_fct_anl_drained_flows_recursive(rec_arc.node_1, p_row, p_intensity)->>'realFlow')::double precision;
			
			-- Check flow data availability for the current pipe
			IF ((v_max_capacity > 0.0) AND (rec_arc.full_flow > 0.0)) THEN

				-- Check flow availability for the other pipes
				IF ((v_num_outlet > 1) AND (v_max_capacity <> rec_arc.full_flow)) THEN 
				
					-- Node has flowregulator
					IF v_hasflowreg THEN
						
						-- Get weightweing parameters
						v_flowreg = (SELECT CASE WHEN isflowreg IS TRUE THEN 0 ELSE 1 END FROM anl_drained_flows_arc WHERE arc_id = rec_arc.arc_id);
						
						-- Runoff flow: calculate drained parameters without limitations on upstream network:
						
						-- There is no weightweing. All flow from node flows trough current arc					
						IF v_ups_runoff_flow < v_flowreg_initflow THEN
						
							v_ups_drained_area := v_ups_drained_area * v_flowreg;
							v_ups_runoff_area := v_ups_runoff_area * v_flowreg;
							v_ups_runoff_flow := v_ups_runoff_flow * v_flowreg;
						
						-- Special weightweing (initflow) and (arc max flow / max discharge capacity)
						ELSE					
						
							-- Arc as flow regulator
							IF v_flowreg = 0 THEN

								-- factor for flow regulators
								v_weight := (((rec_arc.full_flow + v_flowreg_initflow) / v_max_capacity) * (v_ups_runoff_flow - v_flowreg_initflow)) / v_ups_runoff_flow;
								v_ups_drained_area := v_ups_drained_area * v_weight;
								v_ups_runoff_area := v_ups_runoff_area * v_weight;
								v_ups_runoff_flow := v_ups_runoff_flow * v_weight;
																		
							-- Arc not flow regulator
							ELSE
								-- factor for normal conduits
								v_weight := ((((rec_arc.full_flow - v_flowreg_initflow) / v_max_capacity) * (v_ups_runoff_flow - v_flowreg_initflow) + v_flowreg_initflow) / v_ups_runoff_flow);
								v_ups_drained_area := v_ups_drained_area * v_weight ;
								v_ups_runoff_area := v_ups_runoff_area * v_weight ;
								v_ups_runoff_flow := v_ups_runoff_flow * v_weight;
							END IF;
						END IF;
						
						-- Real flow: calculate drained parameters with limitations on upstream network:
						
						-- There is no weightweing. All flow from node flows trough current arc					
						IF v_ups_real_flow < v_flowreg_initflow THEN
				
							v_ups_real_flow := v_ups_real_flow * v_flowreg;
						
						-- special weightweing (initflow) and (arc max flow / max discharge capacity)
						ELSE													
							-- conduit as flow regulator
							IF v_flowreg = 0 THEN

								-- factor for flow regulators
								v_weight := (((rec_arc.full_flow + v_flowreg_initflow) / v_max_capacity) * (v_ups_real_flow - v_flowreg_initflow)) / v_ups_real_flow;
								v_ups_real_flow := v_ups_real_flow * v_weight;

								raise notice 'FLOW REGULATOR ------------------> arc_id %, weight % , ups_runoff_flow %, ups_real_flow %', rec_arc.arc_id, v_weight, v_ups_runoff_flow, v_ups_real_flow;
										
							-- conduit as normal flow
							ELSE 

								-- factor for normal conduits
								v_weight := ((((rec_arc.full_flow - v_flowreg_initflow) / v_max_capacity) * (v_ups_real_flow - v_flowreg_initflow) + v_flowreg_initflow) / v_ups_real_flow);
								v_ups_real_flow := v_ups_real_flow * v_weight;

								raise notice 'NORMAL CONDUIT ------------------>  arc_id %, weight %, ups_drained_area %, ups_runoff_area %, ups_runoff_flow %, ups_real_flow %', 
								rec_arc.arc_id, v_weight, v_ups_drained_area, v_ups_runoff_area, v_ups_runoff_flow,  v_ups_real_flow;

							END IF;
						END IF;
				
								
					-- Node has more than one outlets, but there is no flowregulator detected: weightweing (wet oulet / total outlet) and (arc max flow / max capacity)
					ELSE
			
						v_ups_drained_area := (v_num_wet_outlet / v_num_outlet) * (rec_arc.full_flow / v_max_capacity) * v_ups_drained_area;
						v_ups_runoff_area := (v_num_wet_outlet / v_num_outlet) * (rec_arc.full_flow / v_max_capacity) * v_ups_runoff_area;
						v_ups_runoff_flow := (v_num_wet_outlet / v_num_outlet) * (rec_arc.full_flow / v_max_capacity) * v_ups_runoff_flow;
						v_ups_real_flow := (v_num_wet_outlet / v_num_outlet) * (rec_arc.full_flow / v_max_capacity) * v_ups_real_flow;

					END IF;

				-- If whole flow comes from upstream node to current arc (num outlet = 1 or v_max_capacity = rec_arc.full_flow)
				ELSE
					v_num_outlet := GREATEST(v_num_outlet, 1);
					v_ups_drained_area := v_ups_drained_area / v_num_outlet;
					v_ups_runoff_area := v_ups_runoff_area / v_num_outlet;
					v_ups_runoff_flow := v_ups_runoff_flow / v_num_outlet;
					v_ups_real_flow := v_ups_real_flow / v_num_outlet;
					
				END IF;
				
			-- If there is no data compute with full flow without weightweing capacity
			ELSE
				v_num_outlet := GREATEST(v_num_outlet, 1);
				v_ups_drained_area := v_ups_drained_area / v_num_outlet;
				v_ups_runoff_area := v_ups_runoff_area / v_num_outlet;
				v_ups_runoff_flow := v_ups_runoff_flow / v_num_outlet;
				v_ups_real_flow := v_ups_real_flow / v_num_outlet;
	
			END IF;

			-- Real flow is limited by arc capacity
			IF (rec_arc.full_flow > 0) THEN 
				v_ups_real_flow := LEAST(v_ups_real_flow, rec_arc.full_flow);
			END IF;

			-- Update arc table
			UPDATE anl_drained_flows_arc SET 
				drained_area = v_ups_drained_area,
				runoff_area = v_ups_runoff_area,
				runoff_flow = v_ups_runoff_flow,
				real_flow = v_ups_real_flow			
				WHERE arc_id = rec_arc.arc_id;

			-- Adding values from each arc
			v_tot_drained_area := v_tot_drained_area + v_ups_drained_area;
			v_tot_runoff_area := v_tot_runoff_area + v_ups_runoff_area;
			v_tot_runoff_flow := v_tot_runoff_flow + v_ups_runoff_flow;
			v_tot_real_flow := v_tot_real_flow + v_ups_real_flow;

		END LOOP;
		
		-- Joining values from all arcs and current node
		v_tot_drained_area := v_tot_drained_area + v_node_drained_area;
		v_tot_runoff_area := v_tot_runoff_area + v_node_runoff_area;
		v_tot_runoff_flow := v_tot_runoff_flow + v_node_runoff_flow;
		v_tot_real_flow := v_tot_real_flow + v_node_runoff_flow;

		-- Update node table
		UPDATE anl_drained_flows_node SET 
			drained_area = v_tot_drained_area,
			runoff_area = v_tot_runoff_area,
			runoff_flow = v_tot_runoff_flow,
			real_flow = v_tot_real_flow			
			WHERE node_id = p_node;		

	--	Cyclic!
	ELSIF (v_track_id = p_row) THEN

		SELECT drained_area, runoff_area, runoff_flow, real_flow INTO 
			v_tot_drained_area, v_tot_runoff_area, v_tot_runoff_flow, v_tot_real_flow
			FROM anl_drained_flows_node WHERE node_id = p_node;

	--	Previous result
	ELSE 
		SELECT drained_area, runoff_area, runoff_flow, real_flow INTO 
			v_tot_drained_area, v_tot_runoff_area, v_tot_runoff_flow, v_tot_real_flow
			FROM anl_drained_flows_node WHERE node_id = p_node;
	END IF;

	-- Returning parameters
	v_return = '{"drainedArea":'||v_tot_drained_area||',"runoffArea":'||v_tot_runoff_area||',"runoffFlow":'||v_tot_runoff_flow||',"realFlow":'||v_tot_real_flow||'}';
	RETURN v_return;

END;
$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100;
