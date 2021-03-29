/*
This file is part of Giswater 3
The program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This version of Giswater is provided by Giswater Association
*/

--FUNCTION CODE: 3010


CREATE OR REPLACE FUNCTION ud.gw_fct_anl_drained_flows(p_data json)
RETURNS json AS

$BODY$

/*
EXAMPLE
-------
SELECT ud.gw_fct_anl_drained_flows($${"data":{"parameters":{"resultId":"test1", "intensity":100, "returnArcLayer":false,}}}$$) 
resultId: Id to store as many results as you like on anl_arc & anl_node tables (fid = 367)
intensity: expressed in mm/h
returnArcLayer: To add temporal table on ToC to visualize results of algorithm

-- fid: 367


INSTRUCTIONS
------------
DELETE FROM anl_drained_flows_node;
DELETE FROM anl_drained_flows_arc;


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
CHECK FUNCTION anl_drained_flows_data is ready to work with data 

SELECT * FROM anl_drained_flows_arc

-- EXECUTE
---------- 

The algorithm uses v_edit_data & v_edit_node information. If you are looking to use ti with scenarios and psectors, the only you need is activate it before run

use v_edit_arc without any psector
DELETE FROM selector_psector WHERE cur_user = current_user;

use v_edit_arc without all psector's
INSERT INTO selector_psector SELECT psector_id, current_user FROM plan_psector
ON CONFLICT (psector_id, cur_user) DO NOTHING;


SELECT ud.gw_fct_anl_drained_flows($${"data":{"parameters":{"resultId":"test_flood", "intensity":100, "hydrologyScenario":0}}}$$) -- intensity expressed in mm/h


TO CHECK:
SELECT * FROM anl_drained_flows_arc ORDER BY diff desc
SELECT * FROM anl_drained_flows_node ORDER BY node_flooding desc;

SELECT * FROM anl_drained_flows_result_arc ORDER BY arc_id;
SELECT * FROM anl_drained_flows_result_node ORDER BY arc_id;

UPDATE ud.anl_drained_flows_node set node_area = 1, imperv = 50

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
v_hydrologyscenario integer;

BEGIN

	-- search path
	SET search_path = "ud", public;

	-- select version
	SELECT giswater INTO v_version FROM sys_version order by 1 desc limit 1;
	
	-- get input values
	v_intensity := ((p_data ->>'data')::json->>'parameters')::json->>'intensity';
	v_result_id:= ((p_data ->>'data')::json->>'parameters')::json->>'resultId';
	v_returnarc:= ((p_data ->>'data')::json->>'parameters')::json->>'returnArcLayer';
	v_hydrologyscenario:= ((p_data ->>'data')::json->>'parameters')::json->>'hydrologyScenario';

	-- reset data
	PERFORM gw_fct_anl_drained_flows_data('{"data":"test"}'::json);

	-- reset storage tables
	DELETE FROM anl_arc WHERE result_id = v_result_id AND fid = v_fid;
	DELETE FROM anl_node WHERE result_id = v_result_id AND fid = v_fid;
	DELETE FROM anl_drained_flows_result_cat WHERE result_id = v_result_id;

	-- reset anl drained flows selector
	DELETE FROM selector_drained_flows WHERE cur_user = current_user;
	INSERT INTO selector_drained_flows VALUES (v_result_id, current_user);

	-- save psector selector
	DELETE FROM temp_table WHERE fid=287 AND cur_user=current_user;
	INSERT INTO temp_table (fid, text_column)  
	SELECT 287, (array_agg(psector_id)) FROM selector_psector WHERE cur_user=current_user;

	-- upsert anl_drained_flows_result_cat
	INSERT INTO anl_drained_flows_result_cat VALUES (v_result_id, current_user) ON CONFLICT (result_id) DO NOTHING;

	-- reset hydrology scenario selector
	DELETE FROM selector_inp_hydrology WHERE cur_user = current_user;
	INSERT INTO selector_inp_hydrology VALUES (v_hydrologyscenario, current_user);

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

	IF v_hydrologyscenario > 0 THEN

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
		
	END IF;

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
	SELECT arc_id, geom1, fflow, (((runoff_flow*manning*((2::double precision)^(2::double precision/3::double precision))) /(((abs(slope/100))^0.5)*pi()))^(3::double precision/8::double precision))::numeric(12,3)*2 as geom1_mod, runoff_flow
	FROM anl_drained_flows_arc where slope > 0 or slope < 0) a )b
	where geom1_mod is not null
	ORDER BY diff desc, 1 desc) a
	WHERE anl_drained_flows_arc.arc_id = a.arc_id;

	-- clean geom1_mod and diff
	UPDATE anl_drained_flows_arc SET geom1_mod = null, diff = null where manning is null or slope is null or runoff_flow is null;

	-- update node_inflow
	UPDATE anl_drained_flows_node SET node_inflow= (node_area*(imperv/100)*v_intensity/360)::numeric(12,4);

	-- update node_flooding 
	UPDATE anl_drained_flows_node d SET node_flooding = (node_inflow+entry-exit) FROM
	(SELECT * FROM
	(SELECT node_id, sum(d.real_flow) as entry FROM anl_drained_flows_node n JOIN arc a ON node_2 = n.node_id JOIN anl_drained_flows_arc d USING (arc_id) group by node_id)a
	JOIN
	(SELECT node_id, sum(d.real_flow) as exit FROM anl_drained_flows_node n JOIN arc a ON node_1 = n.node_id JOIN anl_drained_flows_arc d USING (arc_id) group by node_id)b
	USING (node_id)
	) a
	WHERE d.node_id = a.node_id;

	UPDATE anl_drained_flows_node SET node_flooding = 0 where node_flooding IS NULL;

	-- store results
	INSERT INTO anl_drained_flows_result_node 
	(result_id, node_id, node_area, imperv, dw_flow, hasflowreg, flowreg_initflow, node_inflow, max_discharge_capacity, num_outlet, num_wet_outlet, 
	track_id, drained_area, runoff_area, runoff_flow, real_flow, max_runoff_time, max_runoff_length, node_flooding)
	SELECT v_result_id, node_id, node_area, imperv, dw_flow, hasflowreg, flowreg_initflow, node_inflow, max_discharge_capacity, num_outlet, num_wet_outlet, 
	track_id, drained_area, runoff_area, runoff_flow, real_flow, max_runoff_time,  max_runoff_length, node_flooding
	FROM anl_drained_flows_node;

	INSERT INTO anl_drained_flows_result_arc 
	(result_id,arc_id,arccat_id,epa_shape,geom1,geom2,geom3,geom4,length,area,manning,full_rh,slope,fflow,isflowreg, shape_cycles, slope_cycles,
	drained_area,runoff_area,runoff_flow,real_flow,geom1_mod,diff,flow_fflow,fflow_vel,fflow_vel_time,max_runoff_time,max_runoff_length)
	SELECT 
	v_result_id,arc_id,arccat_id,epa_shape,geom1,geom2,geom3,geom4,length,area,manning,full_rh,slope,fflow,isflowreg, shape_cycles, slope_cycles,
	drained_area,runoff_area,runoff_flow,real_flow,geom1_mod,diff,flow_fflow,fflow_vel,fflow_vel_time,max_runoff_time,max_runoff_length
	FROM anl_drained_flows_arc;

	-- restore psector selector
	INSERT INTO selector_psector (psector_id, cur_user)
	select unnest(text_column::integer[]), current_user from temp_table where fid=287 and cur_user=current_user
	ON CONFLICT (psector_id, cur_user) DO NOTHING;
		
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