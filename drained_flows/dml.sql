/*
This file is part of Giswater 3
The program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This version of Giswater is provided by Giswater Association
*/


SET search_path = 'SCHEMA_NAME', public;


-- fprocess
INSERT INTO sys_fprocess VALUES (367, 'Drained flows', 'ud', NULL, 'anl_drained_flows toolbox extra tools')
ON CONFLICT (fid) DO NOTHING;

-- functions
INSERT INTO sys_function(id, function_name, project_type, function_type, input_params, return_type, descript, sys_role, source)
VALUES (3014,'gw_fct_anl_drained_flows', 'ud', 'function', '???', '???', 'Function to analyze drained flows', 'role_epa', 'anl_drained_flows toolbox extra tools') 
ON CONFLICT (function_name, project_type) DO NOTHING;

INSERT INTO sys_function(id, function_name, project_type, function_type, input_params, return_type, descript, sys_role, source)
VALUES (3015,'gw_fct_anl_drained_flows_recursive', 'ud', 'function', '???', '???', 'Auxiliar function to analyze drained flows', 'role_epa', 'anl_drained_flows toolbox extra tools') 
ON CONFLICT (function_name, project_type) DO NOTHING;

INSERT INTO config_toolbox 
VALUES (3014, 'Drained flows', TRUE, '{"featureType":[]}', '[{"widgetname":"intensity", "label":"Rainfall intensity:", "widgettype":"text", "datatype":"numeric","layoutname":"grl_option_parameters","layoutorder":1,"value":""},
							     {"widgetname":"resultId", "label":"Result name:", "widgettype":"text", "datatype":"text", "layoutname":"grl_option_parameters", "layoutorder":2,"value":""},
								 {"widgetname":"returnArcLayer", "label":"Add temp layer on ToC:", "widgettype":"check", "datatype":"boolean", "layoutname":"grl_option_parameters", "layoutorder":3,"value":"false"}]', null, true)

ON CONFLICT (id) DO NOTHING;


-- TO DO
--INSERT INTO sys_table (anl_drained_flows_arc);
--INSERT INTO sys_table (anl_drained_flows_node);
--INSERT INTO sys_table (v_anl_drained_flows_arc);
--INSERT INTO sys_table (v_anl_drained_flows_node);