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
intensity expressed in mm/h
SELECT SCHEMA_NAME.gw_fct_anl_drained_flows($${"data":{"parameters":{"resultId":"test1", "intensity":100}}}$$) 

-- fid: 367


INSTRUCTIONS
------------
Algorithm works with two tables and specific columns:
	- anl_drained_arc table: arc_id, full_flow, isflowreg
	- anl_drained_node table: node_id, node_area, imperv, dw_flow, hasflowreg, flowreg_initflow

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



BEFOR START
-----------

-- fill anl_drained_arc table
-------------------------------
DELETE FROM anl_drained_flows_arc;
INSERT INTO anl_drained_flows_arc (arc_id, arccat_id, epa_shape, geom1, geom2, geom3, geom4, area, manning, slope, isflowreg)
SELECT arc_id, arccat_id, shape, geom1, geom2, geom3, geom4, area, n, slope, false FROM v_edit_arc a
	LEFT JOIN cat_arc ON arccat_id = id 
	LEFT JOIN cat_arc_shape s ON shape=s.id 
	LEFT JOIN cat_mat_arc m ON a.matcat_id = m.id;
-- check:
SELECT * FROM anl_drained_flows_arc order by 1;


-- update anl_drained_arc, full_rh values
-----------------------------------------
UPDATE anl_drained_flows_arc d SET full_rh = 0.5*geom1/2 WHERE epa_shape = 'CIRCULAR'; -- {{hr =0.5*(geom1/2)}}
UPDATE anl_drained_flows_arc d SET full_rh = geom1*geom2/(geom1*2 + geom2*2) WHERE epa_shape = 'RECT_CLOSED';  --{{hr = geom1*geom2/(geom1*2+geom*2}}
UPDATE anl_drained_flows_arc d SET full_rh = 0.579*(geom1/3) WHERE epa_shape = 'EGG'; -- 
-- check: SELECT * FROM anl_drained_flows_arc;


-- update anl_drained_arc, full_flow values for conduits according manning's formula
------------------------------------------------------------------------------------
UPDATE anl_drained_flows_arc d SET full_flow = (1/manning)*((full_rh)^(0.666667))*(slope^(0.5))*area where slope > 0;
UPDATE anl_drained_flows_arc d SET full_flow = (1/manning)*((full_rh)^(0.666667))*((0.00001)^(0.5))*area where slope < 0;
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
SELECT node_id, CASE WHEN area is null then 0 else area END, CASE WHEN imperv IS NULL THEN 0 ELSE imperv END, false,  0 FROM v_edit_node n
	LEFT JOIN inp_subcatchment ON outlet_id = node_id;
-- check: SELECT * FROM anl_drained_flows_node;


-- configure flow regulators
----------------------------
-- node 237
UPDATE anl_drained_flows_node SET hasflowreg = true, flowreg_initflow = 0.2 where node_id  = '237';
UPDATE anl_drained_flows_arc SET isflowreg  = true WHERE arc_id  = '300';

-- node 238
UPDATE anl_drained_flows_node SET hasflowreg = true, flowreg_initflow = 0.25 where node_id  = '238';
UPDATE anl_drained_flows_arc SET isflowreg  = true WHERE arc_id  = '342';


-- EXECUTE
---------- 
SELECT SCHEMA_NAME.gw_fct_anl_drained_flows($${
"data":{"parameters":{"resultId":"test1", "intensity":100}
}}$$) -- intensity expressed in mm/h

TO CHECK:
SELECT * FROM anl_drained_flows_arc ORDER BY arc_id;
SELECT * FROM anl_drained_flows_node ORDER BY node_id;

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

BEGIN

	-- search path
	SET search_path = "SCHEMA_NAME", public;

	-- select version
	SELECT giswater INTO v_version FROM sys_version order by 1 desc limit 1;
	
	-- get input values
	v_intensity := ((p_data ->>'data')::json->>'parameters')::json->>'intensity';
	v_result_id:= ((p_data ->>'data')::json->>'parameters')::json->>'resultId';

	-- reset storage tables
	DELETE FROM anl_arc WHERE result_id = v_result AND fid = v_fid;
	DELETE FROM anl_node WHERE result_id = v_result AND fid = v_fid;
	DELETE FROM audit_check_data WHERE fid=v_fid AND cur_user=current_user;
	
	-- reset algoritm tables
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

	
	-- Check arcs without full_flow
	SELECT count(*) INTO v_count FROM anl_drained_flows_arc WHERE full_flow is null or full_flow = 0;
	IF v_count > 0 THEN
		INSERT INTO audit_check_data (fid, result_id, criticity, error_message)
		VALUES (v_fid, v_result_id, 2, concat('WARNING: There is/are ',v_count,' arcs without full_flow values.'));
	ELSE
		INSERT INTO audit_check_data (fid, result_id, criticity, error_message)
		VALUES (v_fid, v_result_id, 1, 'INFO: No arc(s) without full_flow values found.');
	END IF;

		
	-- node with flow regulator
	FOR rec_node IN SELECT * FROM anl_drained_flows_node WHERE hasflowreg is true
	LOOP

		-- count number of not wet conduits
		SELECT count(*) INTO v_count FROM anl_drained_flows_arc JOIN v_edit_arc USING (arc_id) WHERE node_1 = rec_node.node_id AND full_flow = 0 OR full_flow is NULL;
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
		(SELECT node_1 as node_id, count(*) AS ct FROM anl_drained_flows_arc JOIN v_edit_arc USING (arc_id) WHERE full_flow > 0 GROUP BY node_1) a WHERE a.node_id = n.node_id;

	-- Compute total capacity of the pipes exiting from the node
	UPDATE anl_drained_flows_node n SET max_discharge_capacity = mdc FROM 
		(SELECT node_1 as node_id, sum(full_flow) AS mdc FROM anl_drained_flows_arc JOIN v_edit_arc USING (arc_id) GROUP BY node_1) a WHERE a.node_id = n.node_id;
	
	-- Compute the tributary area using DFS
	FOR v_node_id IN SELECT node_id FROM anl_drained_flows_node
	LOOP
		v_row = v_row + 1;

		-- Call function
		PERFORM gw_fct_anl_drained_flows_recursive(v_node_id, v_row, v_intensity);

	END LOOP;

	-- store results
	INSERT INTO anl_node (node_id, fid, result_id, descript, the_geom)
	SELECT node_id, v_fid, v_result_id, concat('{"node_inflow":',node_inflow,'"max_discharge_capacity":',max_discharge_capacity,',"drained_area":',drained_area,',"runoff_area":',runoff_area,',"runoff_flow":',runoff_flow,',"real_flow":',real_flow,'}'), 
	the_geom 
	FROM anl_drained_flows_node
	JOIN node USING (node_id);

	INSERT INTO anl_arc (arc_id, arccat_id, fid, result_id, descript, the_geom)
	SELECT d.arc_id, d.arccat_id, v_fid, v_result_id, concat('{"full_flow":',full_flow,',"drained_area":',drained_area,',"runoff_area":',runoff_area,',"runoff_flow":',runoff_flow,',"real_flow":',real_flow,'}') ,
	the_geom
	FROM anl_drained_flows_arc d
	JOIN arc USING (arc_id);

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
	v_result = null;
	SELECT jsonb_agg(features.feature) INTO v_result
	FROM (
  	SELECT jsonb_build_object(
     'type',       'Feature',
    'geometry',   ST_AsGeoJSON(the_geom)::jsonb,
    'properties', to_jsonb(row) - 'the_geom'
  	) AS feature
  	FROM (SELECT id, arc_id, arccat_id, descript, the_geom, fid, result_id
  	FROM  anl_arc WHERE result_id=v_result_id AND fid=v_fid) row) features;


	v_result := COALESCE(v_result, '{}'); 
	v_result_line = concat ('{"geometryType":"LineString", "features":',v_result,'}'); 

	-- Control nulls
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
