/*
This file is part of Giswater 3
The program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This version of Giswater is provided by Giswater Association
*/

--FUNCTION CODE: 3009

CREATE OR REPLACE FUNCTION ud_sample.gw_fct_anl_drainedflows_recursive( p_node character varying, p_nrow integer, p_intensity double precision)
  RETURNS double precision AS
  
$BODY$

DECLARE
v_track_id integer = 0;
v_area double precision = 0.0;
v_imperv double precision = 0.0;

v_runoff_area double precision = 0.0;
v_flow double precision = 0.0;

v_node_flow double precision = 0.0;
v_total_capacity double precision;
v_arc_capacity double precision;
v_runoff_arc_flow double precision = 0.0;
v_narcs integer;
v_nwetarcs integer;

rec_arc record;


BEGIN

	-- search path
	SET search_path = "ud_sample", public;

--	Check if the node is already computed
	SELECT first_track_id INTO v_track_id FROM runoff_node_flow WHERE node_id = p_node;

--	First its own area (in Ha!)
	SELECT area, imperv INTO v_area, v_imperv FROM subcatchment WHERE node_id = p_node;

--	Check existing subcatchment
	IF (v_area ISNULL) THEN
		v_area = 0.0;
	END IF;

--	Convert area into runoff area and flow
	v_runoff_area = v_area * v_imperv;
	v_node_flow = v_area * v_imperv * p_intensity;

--	Compute area
	IF (v_track_id = 0) THEN
	
--		Update tracking value
		UPDATE runoff_node_flow SET first_track_id = p_nrow WHERE node_id = p_node;
		
--		Loop for all the upstream nodes
		FOR rec_arc IN SELECT arc_id, flow, node_1 FROM arc WHERE node_2 = p_node
		LOOP

--			Total capacity of the upstream node
			SELECT total_capacity INTO v_total_capacity FROM runoff_node_flow WHERE node_id = rec_arc.node_1;

--			Total number of upstream arcs (wet and total)
			SELECT num_outlet, num_wet_outlet INTO v_narcs, v_nwetarcs FROM runoff_node_flow WHERE node_id = rec_arc.node_1;

--			Check flow data availability for the current pipe
			IF ((v_total_capacity > 0.0) AND (rec_arc.flow > 0.0)) THEN

--				Check flow availability for the other pipes
				IF ((v_narcs > 1) AND (v_total_capacity <> rec_arc.flow)) THEN 
					v_runoff_arc_flow := gw_fct_anl_hydraulics_recursive(rec_arc.node_1, p_nrow, p_intensity);
					v_runoff_arc_flow := (v_nwetarcs::numeric / v_narcs::numeric) * (rec_arc.flow / v_total_capacity) * v_runoff_arc_flow;
					
				ELSIF (v_narcs = 1) THEN
					v_runoff_arc_flow := (rec_arc.flow / v_total_capacity) * gw_fct_anl_hydraulics_recursive(rec_arc.node_1, p_nrow, p_intensity);
				ELSE
					v_narcs := GREATEST(v_narcs, 1);
					v_runoff_arc_flow = gw_fct_anl_hydraulics_recursive(rec_arc.node_1, p_nrow, p_intensity) / v_narcs;
				END IF;
			ELSE

--				If there is no data compute with full flow without limitations
				IF (v_narcs > 0) THEN
					v_runoff_arc_flow = gw_fct_anl_hydraulics_recursive(rec_arc.node_1, p_nrow, p_intensity) / v_narcs;
				ELSE
					v_runoff_arc_flow = gw_fct_anl_hydraulics_recursive(rec_arc.node_1, p_nrow, p_intensity);
				END IF;
				
			END IF;

--			Max flow is limited by arc capacity
			IF (rec_arc.flow > 0) THEN 
				v_runoff_arc_flow := LEAST(v_runoff_arc_flow, rec_arc.flow);
			END IF;

--			Update arc flow
			UPDATE runoff_arc_flow SET flow = v_runoff_arc_flow WHERE arc_id = rec_arc.arc_id;

--			Total node area			
			v_node_flow := v_node_flow + v_runoff_arc_flow;

		END LOOP;
		
--		Fill node tables
		UPDATE runoff_node_flow SET maxflow = v_node_flow WHERE node_id = p_node;		

--	Cyclic!
	ELSIF (v_track_id = p_nrow) THEN

		SELECT maxflow INTO v_node_flow FROM runoff_node_flow WHERE node_id = p_node;

--	Previous result
	ELSE 
		SELECT maxflow INTO v_node_flow FROM runoff_node_flow WHERE node_id = p_node;
	END IF;

--	Return total area
	RETURN v_node_flow;

END;
$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100;
