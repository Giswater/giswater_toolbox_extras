/*
This file is part of Giswater 3
The program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This version of Giswater is provided by Giswater Association
*/

--FUNCTION CODE: 3011


CREATE OR REPLACE FUNCTION ud.gw_fct_anl_drained_flows_data(p_data json)
RETURNS json AS

$BODY$

/*
EXAMPLE
-------
SELECT ud.gw_fct_anl_drained_flows_data($${"data":{}}$$) 

*/


DECLARE

v_error_context text;

BEGIN
	set search_path = ud, public;

	DELETE FROM anl_drained_flows_node;
	DELETE FROM anl_drained_flows_arc;


	-- fill anl_drained_arc table
	-------------------------------
	-- WARNING: IT IS MANDATORY TO PROVIDED SLOPE AS PERCENT NOT UNITARI. KEEP SLOPE VALUES BEFORE INSERT...
	INSERT INTO anl_drained_flows_arc (arc_id, arccat_id, epa_shape, geom1, geom2, geom3, geom4, length, area, manning, slope, isflowreg)
	SELECT arc_id, arccat_id, shape, geom1, geom2, geom3, geom4, st_length(the_geom), area, n, slope*100, false FROM v_edit_arc a
		LEFT JOIN cat_arc ON arccat_id = id 
		LEFT JOIN cat_arc_shape s ON shape=s.id 
		LEFT JOIN cat_mat_arc m ON a.matcat_id = m.id;

	-- update anl_drained_arc, full_rh values
	-----------------------------------------
	UPDATE anl_drained_flows_arc d SET area = (geom1/2)*(geom1/2)*pi() WHERE epa_shape = 'CIRCULAR'; -- {{hr =0.5*(geom1/2)}}
	UPDATE anl_drained_flows_arc d SET full_rh = 0.5*geom1/2 WHERE epa_shape = 'CIRCULAR'; -- {{hr =0.5*(geom1/2)}}

	UPDATE anl_drained_flows_arc d SET area = geom1*geom2 WHERE epa_shape IN ('RECT_OPEN' , 'RECT_CLOSED', 'MODBASKETHANDLE'); -- {{area = geom1*geom2}}
	UPDATE anl_drained_flows_arc d SET full_rh = geom1*geom2/(geom1*2 + geom2*2) WHERE epa_shape IN ('RECT_OPEN' , 'RECT_CLOSED', 'MODBASKETHANDLE');  --{{hr = geom1*geom2/(geom1*2+geom*2}}

	UPDATE anl_drained_flows_arc d SET area = 4.594*((geom1/3)*(geom1/3)) WHERE epa_shape = 'OVOIDE'; -- 
	UPDATE anl_drained_flows_arc d SET full_rh = 0.579*(geom1/3) WHERE epa_shape = 'OVOIDE'; -- 

	UPDATE anl_drained_flows_arc set area=0, full_rh=0 where arccat_id  like'NC%';


	----------------------------------
	-- START SECTION OF ESTIMATED DATA

	-- shape upstream (1)
	UPDATE anl_drained_flows_arc d SET shape_cycles = upstream_shape_cycles + 1, area = upstream_area, full_rh = upstream_full_rh 
	FROM(
		SELECT a.arc_id, area, full_rh, upstream_area, upstream_full_rh, upstream_shape_cycles FROM (
			SELECT a.arc_id, upstream_arc, upstream_shape_cycles, full_rh AS upstream_full_rh, area AS upstream_area FROM (
				SELECT arc_id, upstream_arc, upstream_shape_cycles FROM (
					SELECT a.arc_id, a1.arc_id upstream_arc, an.shape_cycles as upstream_shape_cycles FROM v_edit_arc_slope4dec a
					JOIN v_edit_arc_slope4dec a1 ON a.node_1 = a1.node_2
					JOIN anl_drained_flows_arc an ON a1.arc_id = an.arc_id
					)a
				) a
			JOIN anl_drained_flows_arc b ON b.arc_id = a.upstream_arc order by 1
		)a
		JOIN anl_drained_flows_arc USING (arc_id)
		WHERE area = 0 and upstream_area > 0
	)a WHERE d.area = 0
	AND d.arc_id = a.arc_id;


	-- shape downstream (1)
	UPDATE anl_drained_flows_arc d SET shape_cycles = downstream_shape_cycles + 1, area = downstream_area, full_rh = downstream_full_rh 
	FROM(
		SELECT a.arc_id, area, full_rh, downstream_area, downstream_full_rh, downstream_shape_cycles FROM (
			SELECT a.arc_id, downstream_arc, downstream_shape_cycles, full_rh AS downstream_full_rh, area AS downstream_area FROM (
				SELECT arc_id, downstream_arc, downstream_shape_cycles FROM (
					SELECT a.arc_id, a1.arc_id downstream_arc, an.shape_cycles as downstream_shape_cycles FROM v_edit_arc_slope4dec a
					JOIN v_edit_arc_slope4dec a1 ON a.node_2 = a1.node_1
					JOIN anl_drained_flows_arc an ON a1.arc_id = an.arc_id
					)a
				) a
			JOIN anl_drained_flows_arc b ON b.arc_id = a.downstream_arc order by 1
		)a
		JOIN anl_drained_flows_arc USING (arc_id)
		WHERE area = 0 and downstream_area > 0
	)a WHERE d.area = 0
	AND d.arc_id = a.arc_id;



	-- slope upstream (1)
	UPDATE anl_drained_flows_arc d SET slope_cycles = upstream_slope_cycles + 1, slope = upstream_slope 
	FROM(
		SELECT a.arc_id, slope, upstream_slope, upstream_slope_cycles FROM (
			SELECT a.arc_id, upstream_arc, slope AS upstream_slope, upstream_slope_cycles FROM (
				SELECT arc_id, upstream_arc, upstream_slope_cycles FROM (
					SELECT a.arc_id, a1.arc_id upstream_arc ,an.slope_cycles as upstream_slope_cycles FROM v_edit_arc_slope4dec a
					JOIN v_edit_arc_slope4dec a1 ON a.node_1 = a1.node_2
					JOIN anl_drained_flows_arc an ON a1.arc_id = an.arc_id
					)a
				) a
			JOIN anl_drained_flows_arc b ON b.arc_id = a.upstream_arc order by 1
		)a
		JOIN anl_drained_flows_arc USING (arc_id)
		WHERE slope IS NULL AND upstream_slope IS NOT NULL
	)a WHERE d.slope is null
	AND d.arc_id = a.arc_id;


	-- slope downstream (1)
	UPDATE anl_drained_flows_arc d SET slope_cycles = downstream_slope_cycles + 1, slope = downstream_slope 
	FROM(
		SELECT a.arc_id, slope, downstream_slope, downstream_slope_cycles FROM (
			SELECT a.arc_id, downstream_arc, slope AS downstream_slope, downstream_slope_cycles FROM (
				SELECT arc_id, downstream_arc, downstream_slope_cycles FROM (
					SELECT a.arc_id, a1.arc_id downstream_arc, an.slope_cycles as downstream_slope_cycles FROM v_edit_arc_slope4dec a
					JOIN v_edit_arc_slope4dec a1 ON a.node_2 = a1.node_1
					JOIN anl_drained_flows_arc an ON a1.arc_id = an.arc_id
					)a
				) a
			JOIN anl_drained_flows_arc b ON b.arc_id = a.downstream_arc order by 1
		)a
		JOIN anl_drained_flows_arc USING (arc_id)
		WHERE slope IS NULL AND downstream_slope IS NOT NULL
	)a WHERE d.slope is null
	AND d.arc_id = a.arc_id;

	---- second cycle ----

	-- shape upstream (2)
	UPDATE anl_drained_flows_arc d SET shape_cycles = upstream_shape_cycles + 1, area = upstream_area, full_rh = upstream_full_rh 
	FROM(
		SELECT a.arc_id, area, full_rh, upstream_area, upstream_full_rh, upstream_shape_cycles FROM (
			SELECT a.arc_id, upstream_arc, upstream_shape_cycles, full_rh AS upstream_full_rh, area AS upstream_area FROM (
				SELECT arc_id, upstream_arc, upstream_shape_cycles FROM (
					SELECT a.arc_id, a1.arc_id upstream_arc, an.shape_cycles as upstream_shape_cycles FROM v_edit_arc_slope4dec a
					JOIN v_edit_arc_slope4dec a1 ON a.node_1 = a1.node_2
					JOIN anl_drained_flows_arc an ON a1.arc_id = an.arc_id
					)a
				) a
			JOIN anl_drained_flows_arc b ON b.arc_id = a.upstream_arc order by 1
		)a
		JOIN anl_drained_flows_arc USING (arc_id)
		WHERE area = 0 and upstream_area > 0
	)a WHERE d.area = 0
	AND d.arc_id = a.arc_id;

	-- shape downstream (2)
	UPDATE anl_drained_flows_arc d SET shape_cycles = downstream_shape_cycles + 1, area = downstream_area, full_rh = downstream_full_rh 
	FROM(
		SELECT a.arc_id, area, full_rh, downstream_area, downstream_full_rh, downstream_shape_cycles FROM (
			SELECT a.arc_id, downstream_arc, downstream_shape_cycles, full_rh AS downstream_full_rh, area AS downstream_area FROM (
				SELECT arc_id, downstream_arc, downstream_shape_cycles FROM (
					SELECT a.arc_id, a1.arc_id downstream_arc, an.shape_cycles as downstream_shape_cycles FROM v_edit_arc_slope4dec a
					JOIN v_edit_arc_slope4dec a1 ON a.node_2 = a1.node_1
					JOIN anl_drained_flows_arc an ON a1.arc_id = an.arc_id
					)a
				) a
			JOIN anl_drained_flows_arc b ON b.arc_id = a.downstream_arc order by 1
		)a
		JOIN anl_drained_flows_arc USING (arc_id)
		WHERE area = 0 and downstream_area > 0
	)a WHERE d.area = 0
	AND d.arc_id = a.arc_id;

	-- slope upstream (2)
	UPDATE anl_drained_flows_arc d SET slope_cycles = upstream_slope_cycles + 1, slope = upstream_slope 
	FROM(
		SELECT a.arc_id, slope, upstream_slope, upstream_slope_cycles FROM (
			SELECT a.arc_id, upstream_arc, slope AS upstream_slope, upstream_slope_cycles FROM (
				SELECT arc_id, upstream_arc, upstream_slope_cycles FROM (
					SELECT a.arc_id, a1.arc_id upstream_arc ,an.slope_cycles as upstream_slope_cycles FROM v_edit_arc_slope4dec a
					JOIN v_edit_arc_slope4dec a1 ON a.node_1 = a1.node_2
					JOIN anl_drained_flows_arc an ON a1.arc_id = an.arc_id
					)a
				) a
			JOIN anl_drained_flows_arc b ON b.arc_id = a.upstream_arc order by 1
		)a
		JOIN anl_drained_flows_arc USING (arc_id)
		WHERE slope IS NULL AND upstream_slope IS NOT NULL
	)a WHERE d.slope is null
	AND d.arc_id = a.arc_id;

	-- slope downstream (2)
	UPDATE anl_drained_flows_arc d SET slope_cycles = downstream_slope_cycles + 1, slope = downstream_slope 
	FROM(
		SELECT a.arc_id, slope, downstream_slope, downstream_slope_cycles FROM (
			SELECT a.arc_id, downstream_arc, slope AS downstream_slope, downstream_slope_cycles FROM (
				SELECT arc_id, downstream_arc, downstream_slope_cycles FROM (
					SELECT a.arc_id, a1.arc_id downstream_arc, an.slope_cycles as downstream_slope_cycles FROM v_edit_arc_slope4dec a
					JOIN v_edit_arc_slope4dec a1 ON a.node_2 = a1.node_1
					JOIN anl_drained_flows_arc an ON a1.arc_id = an.arc_id
					)a
				) a
			JOIN anl_drained_flows_arc b ON b.arc_id = a.downstream_arc order by 1
		)a
		JOIN anl_drained_flows_arc USING (arc_id)
		WHERE slope IS NULL AND downstream_slope IS NOT NULL
	)a WHERE d.slope is null
	AND d.arc_id = a.arc_id;

	-- not cero slopes
	UPDATE anl_drained_flows_arc SET slope = 0.001 WHERE slope < 0.001;

	-- not null manning
	UPDATE anl_drained_flows_arc d SET material_estimated = true, manning = 0.014 WHERE manning IS NULL;

	--END SECTION OF ESTIMATED DATA
	-------------------------------
	
	-- update anl_drained_arc, full_flow values for conduits according manning's formula
	------------------------------------------------------------------------------------
	UPDATE anl_drained_flows_arc d SET fflow = (1/manning)*((full_rh)^(0.666667))*(slope^(0.5))*area where slope > 0;
	UPDATE anl_drained_flows_arc d SET fflow = (1/manning)*((full_rh)^(0.666667))*((0.00001)^(0.5))*area where slope < 0;


	-- update anl_drained_arc, full_flow values for force main conduits (according pump station)
	--------------------------------------------------------------------------------------------
	UPDATE anl_drained_flows_arc d SET fflow = 0.2 WHERE epa_shape = 'FORCE_MAIN' AND arc_id::integer IN (245);


	-- re-update anl_drained_arc, full_flow values ONLY for VIRTUAL ARCS (using full_flow from downstream arc)
	----------------------------------------------------------------------------------------------------------
	UPDATE anl_drained_flows_arc f SET fflow = a.fflow FROM (
		SELECT a1.arc_id, fflow FROM v_edit_arc a1 	
		JOIN v_edit_arc a2 ON a1.node_2 = a2.node_1 
		JOIN anl_drained_flows_arc d ON a2.arc_id = d.arc_id
		JOIN cat_feature_arc f1 ON f1.id = a1.arc_type
		JOIN cat_feature_arc f2 ON f2.id = a2.arc_type
		WHERE f1.type = 'VARC' AND f2.type != 'VARC'
		) a WHERE f.arc_id  =a.arc_id;


	-- insert anl_drained_node table
	--------------------------------
	DELETE FROM anl_drained_flows_node;
	INSERT INTO anl_drained_flows_node (node_id)
	SELECT node_id FROM v_edit_node;


	-- configure flow regulators
	----------------------------
	-- node 21762
	UPDATE ud.anl_drained_flows_node SET hasflowreg = true, flowreg_initflow = 0.585 where node_id  = '21762';
	UPDATE anl_drained_flows_arc SET isflowreg  = true WHERE arc_id  = '10495';

	-- node 22644
	UPDATE ud.anl_drained_flows_node SET hasflowreg = true, flowreg_initflow = 0.3607 where node_id  = '22644';
	UPDATE anl_drained_flows_arc SET isflowreg  = true WHERE arc_id  = '11327';

	
	-- Return
	RETURN ('{"status":"Accepted", "message":{"level":1, "text":"Analysis done successfully"}, "version":""'||
             ',"body":{"form":{},"data":{} } }')::json; 

	EXCEPTION WHEN OTHERS THEN
	GET STACKED DIAGNOSTICS v_error_context = PG_EXCEPTION_CONTEXT;
	RETURN ('{"status":"Failed", "SQLERR":' || to_json(SQLERRM) || ',"SQLSTATE":' || to_json(SQLSTATE) ||',"SQLCONTEXT":' || to_json(v_error_context) || '}')::json;

		
END;$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100;