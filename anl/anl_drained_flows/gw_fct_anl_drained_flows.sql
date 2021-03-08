/*
This file is part of Giswater 3
The program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This version of Giswater is provided by Giswater Association
*/

--FUNCTION CODE: 3010


CREATE OR REPLACE FUNCTION SCHEMA_NAME.gw_fct_anl_drained_flows(p_data json)
RETURNS json AS

$BODY$

/*
EXAMPLE
-------
SELECT SCHEMA_NAME.gw_fct_anl_drained_flows($${"data":{"parameters":{"resultId":"test1", "intensity":100, "returnArcLayer":false,}}}$$) 
resultId: Id to store as many results as you like on anl_arc & anl_node tables (fid = 367)
intensity: expressed in mm/h
returnArcLayer: To add temporal table on ToC to visualize results of algorithm

-- fid: 367


INSTRUCTIONS
------------
Algorithm works with two tables and specific columns:
	- anl_drained_arc table: arc_id, full_flow, isflowreg
	- anl_drained_node table: node_id, node_area, imperv, dw_flow, hasflowreg, flowreg_initflow

The propagation of drained parameters has two special characteristics:
	1) NODE RULES: Drainage parameters distribution on nodes whith more than one outlet conduit

	- If max_flow of all outlet conduits is provided (wet conduits)
		- If node has flowregulator
			- flowreg_initflow in combination with mannings capacity weightweing
		
		- Else
			- Mannings capacity weightweing
		
	- Else (If there is some conduit without max_flow):
		- For non-wet conduits -> Linear distribution (wet conduits / total conduits)
		- For wet conduits, mannings capacity weightweing


	2) ARC RULES: Flow limitation in terms of arc maximun mannings capacity
	- Real flow is maximun againts (conduit max flow and flow provided for the upstream node)



BEFOR START
-----------
SELECT * FROM anl_drained_flows_arc

-- fill anl_drained_arc table
-------------------------------
DELETE FROM anl_drained_flows_arc;
INSERT INTO anl_drained_flows_arc (arc_id, arccat_id, epa_shape, geom1, geom2, geom3, geom4, length, area, manning, slope, isflowreg)
SELECT arc_id, arccat_id, shape, geom1, geom2, geom3, geom4, st_length(the_geom), area, n, slope, false FROM v_edit_arc a
	LEFT JOIN cat_arc ON arccat_id = id 
	LEFT JOIN cat_arc_shape s ON shape=s.id 
	LEFT JOIN cat_mat_arc m ON a.matcat_id = m.id;
-- check:
SELECT * FROM anl_drained_flows_arc WHERE epa_shape  ='RECTANGULAR';


-- update anl_drained_arc, full_rh values
-----------------------------------------
UPDATE anl_drained_flows_arc d SET area = (geom1/2)*(geom1/2)*pi() WHERE epa_shape = 'CIRCULAR'; -- {{hr =0.5*(geom1/2)}}
UPDATE anl_drained_flows_arc d SET full_rh = 0.5*geom1/2 WHERE epa_shape = 'CIRCULAR'; -- {{hr =0.5*(geom1/2)}}

SELECT DISTINCT (shape) FROM cat_arc JOIN arc ON arccat_id = id WHERE sector_id =28

UPDATE anl_drained_flows_arc d SET area = geom1*geom2 WHERE epa_shape IN ('RECT_OBERT' , 'RECTANGULAR', 'MODBASKETHANDLE'); -- {{area = geom1*geom2}}
UPDATE anl_drained_flows_arc d SET full_rh = geom1*geom2/(geom1*2 + geom2*2) WHERE epa_shape IN ('RECT_OBERT' , 'RECTANGULAR', 'MODBASKETHANDLE');  --{{hr = geom1*geom2/(geom1*2+geom*2}}

UPDATE anl_drained_flows_arc d SET area = 4.594*((geom1/3)*(geom1/3)) WHERE epa_shape = 'OVOIDE'; -- 
UPDATE anl_drained_flows_arc d SET full_rh = 0.579*(geom1/3) WHERE epa_shape = 'OVOIDE'; -- 
-- check: 
SELECT * FROM anl_drained_flows_arc;

UPDATE anl_drained_flows_arc set area=0, full_rh=0 where arccat_id  like'NC%'


---------------------------------------------------------------------------------------------------------------------
START SECTION OF ESTIMATED DATA
Estimating conduit's data getting upstream values and downstream values
MAYBE NEED TO BE PASSED VARIOUS TIMES IN ORDER TO GET AND RE GET VALUES. 
The number of times executed is shape_cycles and slope_cycles. This cycles takes information about how far is data
---------------------------------------------------------------------------------------------------------------------

-- shape upstream
UPDATE anl_drained_flows_arc d SET shape_cycles = shape_cycles + 1, area = upstream_area, full_rh = upstream_full_rh 
FROM(
	SELECT a.arc_id, area, full_rh, upstream_area, upstream_full_rh FROM (
		SELECT a.arc_id, upstream_arc, full_rh AS upstream_full_rh, area AS upstream_area FROM (
			SELECT arc_id, upstream_arc FROM (
				SELECT a.arc_id, a1.arc_id upstream_arc FROM v_edit_arc a
				JOIN v_edit_arc a1 ON a.node_1 = a1.node_2
				)a
			) a
		JOIN anl_drained_flows_arc b ON b.arc_id = a.upstream_arc order by 1
	)a
	JOIN anl_drained_flows_arc USING (arc_id)
	WHERE area = 0 and upstream_area > 0
)a WHERE d.area = 0
AND d.arc_id = a.arc_id;


-- shape downstream
UPDATE anl_drained_flows_arc d SET shape_cycles = shape_cycles + 1, area = downstream_area, full_rh = downstream_full_rh 
FROM(
	SELECT a.arc_id, area, full_rh, downstream_area, downstream_full_rh FROM (
		SELECT a.arc_id, downstream_arc, full_rh AS downstream_full_rh, area AS downstream_area FROM (
			SELECT arc_id, downstream_arc FROM (
				SELECT a.arc_id, a1.arc_id downstream_arc FROM v_edit_arc a
				JOIN v_edit_arc a1 ON a.node_2 = a1.node_1
				)a
			) a
		JOIN anl_drained_flows_arc b ON b.arc_id = a.downstream_arc order by 1
	)a
	JOIN anl_drained_flows_arc USING (arc_id)
	WHERE area = 0 and downstream_area > 0
)a WHERE d.area = 0
AND d.arc_id = a.arc_id;



-- slope upstream
UPDATE anl_drained_flows_arc d SET slope_cycles = slope_cycles + 1, slope = upstream_slope 
FROM(
	SELECT a.arc_id, slope, upstream_slope FROM (
		SELECT a.arc_id, upstream_arc, slope AS upstream_slope FROM (
			SELECT arc_id, upstream_arc FROM (
				SELECT a.arc_id, a1.arc_id upstream_arc FROM v_edit_arc a
				JOIN v_edit_arc a1 ON a.node_1 = a1.node_2
				)a
			) a
		JOIN anl_drained_flows_arc b ON b.arc_id = a.upstream_arc order by 1
	)a
	JOIN anl_drained_flows_arc USING (arc_id)
	WHERE slope IS NULL AND upstream_slope IS NOT NULL
)a WHERE d.slope is null
AND d.arc_id = a.arc_id;


-- slope downstream
UPDATE anl_drained_flows_arc d SET slope_cycles = slope_cycles + 1, slope = downstream_slope 
FROM(
	SELECT a.arc_id, slope, downstream_slope FROM (
		SELECT a.arc_id, downstream_arc, slope AS downstream_slope FROM (
			SELECT arc_id, downstream_arc FROM (
				SELECT a.arc_id, a1.arc_id downstream_arc FROM v_edit_arc a
				JOIN v_edit_arc a1 ON a.node_2 = a1.node_1
				)a
			) a
		JOIN anl_drained_flows_arc b ON b.arc_id = a.downstream_arc order by 1
	)a
	JOIN anl_drained_flows_arc USING (arc_id)
	WHERE slope IS NULL AND downstream_slope IS NOT NULL
)a WHERE d.slope is null
AND d.arc_id = a.arc_id;

-- not cero slopes
UPDATE anl_drained_flows_arc SET slope = 0.002 WHERE slope = 0;

-- not null manning
UPDATE anl_drained_flows_arc d SET material_estimated = true, manning = 0.014 WHERE manning IS NULL;


-- comprovation
SELECT * FROM anl_drained_flows_arc WHERE full_rh = 0 or slope is null or area = 0


------------------------------------------------------------------------
END SECTION OF ESTIMATED DATA
------------------------------------------------------------------------


-- update anl_drained_arc, full_flow values for conduits according manning's formula
------------------------------------------------------------------------------------
UPDATE anl_drained_flows_arc d SET fflow = (1/manning)*((full_rh)^(0.666667))*(slope^(0.5))*area where slope > 0;
UPDATE anl_drained_flows_arc d SET fflow = (1/manning)*((full_rh)^(0.666667))*((0.00001)^(0.5))*area where slope < 0;
-- check: SELECT * FROM anl_drained_flows_arc;


-- update anl_drained_arc, full_flow values for force main conduits (according pump station)
--------------------------------------------------------------------------------------------
UPDATE anl_drained_flows_arc d SET full_flow = 0.2 WHERE epa_shape = 'FORCE_MAIN' AND arc_id::integer IN (245);
-- check: SELECT * FROM anl_drained_flows_arc;


-- re-update anl_drained_arc, full_flow values ONLY for VIRTUAL ARCS (using full_flow from downstream arc)
----------------------------------------------------------------------------------------------------------
UPDATE anl_drained_flows_arc f SET full_flow = a.full_flow FROM (
	SELECT a1.arc_id, full_flow FROM v_edit_arc a1 	
	JOIN v_edit_arc a2 ON a1.node_2 = a2.node_1 
	JOIN anl_drained_flows_arc d ON a2.arc_id = d.arc_id
	JOIN cat_feature_arc f1 ON f1.id = a1.arc_type
	JOIN cat_feature_arc f2 ON f2.id = a2.arc_type
	WHERE f1.type = 'VARC' AND f2.type != 'VARC'
	) a WHERE f.arc_id  =a.arc_id;
-- check: SELECT * FROM anl_drained_flows_arc;


-- insert anl_drained_node table
--------------------------------
DELETE FROM anl_drained_flows_node;
INSERT INTO anl_drained_flows_node (node_id, node_area, imperv, hasflowreg, flowreg_initflow)
SELECT node_id FROM v_edit_node;

-- check: 
SELECT * FROM anl_drained_flows_node;


-- configure flow regulators
----------------------------
-- node 237
UPDATE anl_drained_flows_node SET hasflowreg = true, flowreg_initflow = 0.25 where node_id  = '237';
UPDATE anl_drained_flows_arc SET isflowreg  = true WHERE arc_id  = '300';

-- node 238
UPDATE anl_drained_flows_node SET hasflowreg = true, flowreg_initflow = 0.2 where node_id  = '238';
UPDATE anl_drained_flows_arc SET isflowreg  = true WHERE arc_id  = '342';


-- EXECUTE
---------- 
SELECT SCHEMA_NAME.gw_fct_anl_drained_flows($${"data":{"parameters":{"resultId":"test_xavi", "intensity":100, "hydrologyScenario":6}}}$$) -- intensity expressed in mm/h

SELECT * FROM SCHEMA_NAME.cat_hydrology

TO CHECK:
SELECT * FROM anl_drained_flows_arc ORDER BY arc_id
SELECT * FROM anl_drained_flows_node ORDER BY node_id;
SELECT * FROM anl_drained_flows_result_arc ORDER BY arc_id;
SELECT * FROM anl_drained_flows_result_node ORDER BY arc_id;
*/

DECLARE

--system
v_error_context text;
v_fid integer = 367;
v_version text;

-- algorithm
v_intensity double precision = 0;
v_node_id varchar(16);
v_row integer = 0;
v_num_outlet integer = 0;
v_num_wet_outlet integer = 0;
v_max_discharge_capacity double precision = 0;
v_result_id text;

-- result
rec_node record;
v_count integer = 0;
v_result text;
v_result_info json;
v_result_line json;
v_returnarc boolean = false;
v_hydrologyScenario integer;

BEGIN

	-- search path
	SET search_path = "SCHEMA_NAME", public;

	-- select version
	SELECT giswater INTO v_version FROM sys_version order by 1 desc limit 1;
	
	-- get input values
	v_intensity := ((p_data ->>'data')::json->>'parameters')::json->>'intensity';
	v_result_id:= ((p_data ->>'data')::json->>'parameters')::json->>'resultId';
	v_returnarc:= ((p_data ->>'data')::json->>'parameters')::json->>'returnArcLayer';
	v_hydrologyScenario:= ((p_data ->>'data')::json->>'parameters')::json->>'hydrologyScenario';


	-- reset storage tables
	DELETE FROM anl_arc WHERE result_id = v_result_id AND fid = v_fid;
	DELETE FROM anl_node WHERE result_id = v_result_id AND fid = v_fid;
	DELETE FROM anl_drained_flows_result_cat WHERE result_id = v_result_id;

	-- reset anl drained flows selector
	DELETE FROM selector_drained_flows WHERE cur_user = current_user;
	INSERT INTO selector_drained_flows VALUES (v_result_id, current_user);

	-- upsert anl_drained_flows_result_cat
	INSERT INTO anl_drained_flows_result_cat VALUES (v_result_id, current_user) ON CONFLICT (result_id) DO NOTHING;

	-- reset hydrology scenario selector
	DELETE FROM selector_inp_hydrology WHERE cur_user = current_user;
	INSERT INTO selector_inp_hydrology VALUES (v_hydrologyScenario, current_user);

	-- update algoritm tables
	UPDATE anl_drained_flows_node SET 
		node_inflow = 0, 
		max_discharge_capacity = 0,
		num_outlet = 0,
		num_wet_outlet = 0,
		track_id = 0,
		drained_area = 0,
		runoff_area = 0,
		runoff_flow = 0,
		real_flow = 0;

	-- update using hidrology scenario
	UPDATE anl_drained_flows_node n SET node_area = area, imperv = a.imperv FROM 
	(SELECT node_id, 
	CASE WHEN sum(area)::numeric(12,4) is null then 0 else sum(area)::numeric(12,4) END as area, 
	CASE WHEN (sum(area*imperv)/sum(area))::numeric(12,4) IS NULL THEN 0 ELSE (sum(area*imperv)/sum(area))::numeric(12,4) END as imperv, 
	false, 
	0 
	FROM v_edit_node n
	LEFT JOIN v_edit_inp_subcatchment ON outlet_id = node_id
	GROUP BY node_id)a
	WHERE n.node_id = a.node_id;

	UPDATE anl_drained_flows_arc SET 
		drained_area = 0, 
		runoff_area = 0,
		runoff_flow = 0,
		real_flow = 0;

	-- Header
	INSERT INTO audit_check_data (fid, result_id, criticity, error_message) VALUES (v_fid, v_result_id, 4, concat('DRAINED FLOWS ALGORITHM'));
	INSERT INTO audit_check_data (fid, result_id, criticity, error_message) VALUES (v_fid, v_result_id, 4, '-------------------------------------');

	INSERT INTO audit_check_data (fid, result_id, criticity, error_message) VALUES (v_fid, v_result_id, 3, 'CRITICAL ERRORS');
	INSERT INTO audit_check_data (fid, result_id, criticity, error_message) VALUES (v_fid, v_result_id, 3, '----------------------');

	INSERT INTO audit_check_data (fid, result_id, criticity, error_message) VALUES (v_fid, v_result_id, 2, 'WARNINGS');
	INSERT INTO audit_check_data (fid, result_id, criticity, error_message) VALUES (v_fid, v_result_id, 2, '--------------');

	INSERT INTO audit_check_data (fid, result_id, criticity, error_message) VALUES (v_fid, v_result_id, 1, 'INFO');
	INSERT INTO audit_check_data (fid, result_id, criticity, error_message) VALUES (v_fid, v_result_id, 1, '-------');

	
	-- Check arcs without fflow
	SELECT count(*) INTO v_count FROM anl_drained_flows_arc WHERE fflow is null or fflow = 0;
	IF v_count > 0 THEN
		INSERT INTO audit_check_data (fid, result_id, criticity, error_message)
		VALUES (v_fid, v_result_id, 2, concat('WARNING: There is/are ',v_count,' arcs without fflow values.'));
	ELSE
		INSERT INTO audit_check_data (fid, result_id, criticity, error_message)
		VALUES (v_fid, v_result_id, 1, 'INFO: No arc(s) without fflow values found.');
	END IF;

		
	-- node with flow regulator
	FOR rec_node IN SELECT * FROM anl_drained_flows_node WHERE hasflowreg is true
	LOOP

		-- count number of not wet conduits
		SELECT count(*) INTO v_count FROM anl_drained_flows_arc JOIN v_edit_arc USING (arc_id) WHERE node_1 = rec_node.node_id AND fflow = 0 OR fflow is NULL;
		IF v_count >0 THEN
			INSERT INTO audit_check_data (fid, result_id, criticity, error_message)
			VALUES (v_fid, v_result_id, 3, concat('ERROR: There is/are ',v_count,' outlet arcs without max_flow values on node ',rec_node.node_id,' as floregulator.'));
		ELSE
			INSERT INTO audit_check_data (fid, result_id, criticity, error_message)
			VALUES (v_fid, v_result_id, 1, concat('INFO: All outlet arcs on node flowregulator ',rec_node.node_id,' has max_flow values.'));
		END IF;
		
		-- count number of main conduits
		SELECT count(*) INTO v_count FROM anl_drained_flows_arc JOIN v_edit_arc USING (arc_id) WHERE node_1 = rec_node.node_id AND isflowreg is false;

		IF v_count != 1 THEN
			INSERT INTO audit_check_data (fid, result_id, criticity, error_message)
			VALUES (v_fid, v_result_id, 3, concat('ERROR: There is/are ',v_count,' arcs as main downstream conduit (isflowregulator = false) on node ',rec_node.node_id,' as floregulator.'));
		ELSE
			INSERT INTO audit_check_data (fid, result_id, criticity, error_message)
			VALUES (v_fid, v_result_id, 1, concat('INFO: Node ',rec_node.node_id,' has  ONE main downstream conduit (isflowregulator = false).'));
		END IF;

	END LOOP;
	
	-- Count number of pipes draining the node
	UPDATE anl_drained_flows_node n SET num_outlet = ct FROM 
		(SELECT node_1 as node_id, count(*) AS ct FROM v_edit_arc GROUP BY node_1) a WHERE a.node_id = n.node_id;
	
	-- Count number of wet pipes draining the node
	UPDATE anl_drained_flows_node n SET num_wet_outlet = ct FROM 
		(SELECT node_1 as node_id, count(*) AS ct FROM anl_drained_flows_arc JOIN v_edit_arc USING (arc_id) WHERE fflow > 0 GROUP BY node_1) a WHERE a.node_id = n.node_id;

	-- Compute total capacity of the pipes exiting from the node
	UPDATE anl_drained_flows_node n SET max_discharge_capacity = mdc FROM 
		(SELECT node_1 as node_id, sum(fflow) AS mdc FROM anl_drained_flows_arc JOIN v_edit_arc USING (arc_id) GROUP BY node_1) a WHERE a.node_id = n.node_id;
	
	-- Compute the tributary area using DFS
	FOR v_node_id IN SELECT node_id FROM anl_drained_flows_node
	LOOP
		v_row = v_row + 1;

		-- Call function
		PERFORM gw_fct_anl_drained_flows_recursive(v_node_id, v_row, v_intensity);

	END LOOP;
	

	-- update geom1_mod value
	UPDATE anl_drained_flows_arc SET geom1_mod = a.geom1_mod, diff = a.diff FROM (
	SELECT *, (geom1_mod-geom1)::numeric (12,2) as diff FROM (
	SELECT arc_id, geom1, case when geom1_mod < geom1 then geom1 else geom1_mod end as geom1_mod FROM (
	SELECT arc_id, geom1, fflow, (((runoff_flow*manning*((2::double precision)^(2::double precision/3::double precision))) /(((abs(slope))^0.5)*pi()))^(3::double precision/8::double precision))::numeric(12,3)*2 as geom1_mod, runoff_flow
	FROM anl_drained_flows_arc where slope > 0 or slope < 0) a )b
	where geom1_mod is not null
	ORDER BY diff desc, 1 desc) a
	WHERE anl_drained_flows_arc.arc_id = a.arc_id;

	-- clean geom1_mod and diff
	UPDATE anl_drained_flows_arc SET geom1_mod = null, diff = null where manning is null or slope is null or runoff_flow is null;

	
	-- store results
	INSERT INTO anl_drained_flows_result_node 
	(result_id, node_id, node_area, imperv, dw_flow, hasflowreg, flowreg_initflow, node_inflow, max_discharge_capacity, num_outlet, num_wet_outlet, 
	track_id, drained_area, runoff_area, runoff_flow, real_flow, max_runoff_time, max_runoff_length)
	SELECT v_result_id, node_id, node_area, imperv, dw_flow, hasflowreg, flowreg_initflow, node_inflow, max_discharge_capacity, num_outlet, num_wet_outlet, 
	track_id, drained_area, runoff_area, runoff_flow, real_flow, max_runoff_time,  max_runoff_length
	FROM anl_drained_flows_node;

	INSERT INTO anl_drained_flows_result_arc 
	(result_id,arc_id,arccat_id,epa_shape,geom1,geom2,geom3,geom4,length,area,manning,full_rh,slope,fflow,isflowreg, shape_cycles, slope_cycles,
	drained_area,runoff_area,runoff_flow,real_flow,geom1_mod,diff,flow_fflow,fflow_vel,fflow_vel_time,max_runoff_time,max_runoff_length)
	SELECT 
	v_result_id,arc_id,arccat_id,epa_shape,geom1,geom2,geom3,geom4,length,area,manning,full_rh,slope,fflow,isflowreg, shape_cycles, slope_cycles,
	drained_area,runoff_area,runoff_flow,real_flow,geom1_mod,diff,flow_fflow,fflow_vel,fflow_vel_time,max_runoff_time,max_runoff_length
	FROM anl_drained_flows_arc;
	
	
	-- insert spacers for log
	INSERT INTO audit_check_data (fid, result_id, criticity, error_message) VALUES (v_fid, v_result_id, 4, '');
	INSERT INTO audit_check_data (fid, result_id, criticity, error_message) VALUES (v_fid, v_result_id, 3, '');
	INSERT INTO audit_check_data (fid, result_id, criticity, error_message) VALUES (v_fid, v_result_id, 2, '');
	INSERT INTO audit_check_data (fid, result_id, criticity, error_message) VALUES (v_fid, v_result_id, 1, '');
	
	-- info
	SELECT array_to_json(array_agg(row_to_json(row))) INTO v_result
	FROM (SELECT id, error_message as message FROM audit_check_data WHERE cur_user="current_user"() AND fid=v_fid order by criticity desc, id asc) row;
	v_result := COALESCE(v_result, '{}'); 
	v_result_info = concat ('{"geometryType":"", "values":',v_result, '}');

	--lines
	IF v_returnarc THEN
		v_result = null;
		SELECT json_agg(features.feature) INTO v_result
		FROM (
		SELECT json_build_object(
		 'type',       'Feature',
		'geometry',   ST_AsGeoJSON(the_geom)::json,
		'properties', to_json(row)
		) AS feature
		FROM (SELECT arc_id, arccat_id, result_id, descript, the_geom
		FROM  anl_arc WHERE result_id=v_result_id AND fid=v_fid) row) features;
		v_result_line = concat ('{"geometryType":"LineString", "features":',v_result,'}'); 

	END IF;

	-- Control nulls
	v_result := COALESCE(v_result, '{}'); 
	v_result_info := COALESCE(v_result_info, '{}'); 
	v_result_line := COALESCE(v_result_line, '{}'); 
	
	-- Return
	RETURN ('{"status":"Accepted", "message":{"level":1, "text":"Analysis done successfully"}, "version":"'||v_version||'"'||
             ',"body":{"form":{}'||
		     ',"data":{ "info":'||v_result_info||','||
				'"line":'||v_result_line||','||
				'"setVisibleLayers":""}'||
		       '}'||
	    '}')::json; 

	EXCEPTION WHEN OTHERS THEN
	GET STACKED DIAGNOSTICS v_error_context = PG_EXCEPTION_CONTEXT;
	RETURN ('{"status":"Failed", "SQLERR":' || to_json(SQLERRM) || ',"SQLSTATE":' || to_json(SQLSTATE) ||',"SQLCONTEXT":' || to_json(v_error_context) || '}')::json;

		
END;$BODY$
  LANGUAGE plpgsql VOLATILE
  COST 100;
