/*
This file is part of Giswater 3
The program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This version of Giswater is provided by Giswater Association
*/


SET search_path = 'ud_sample', public;


INSERT INTO sys_function(id, function_name, project_type, function_type, input_params, return_type, descript, sys_role, source)
VALUES (3007,'anl_drained_flows', 'ud', 'function', '???', '???', 'Function to analyze drained flows', 'role_epa', 'toolbox extras drained_flows') 
ON CONFLICT (function_name, project_type) DO NOTHING;


INSERT INTO sys_function(id, function_name, project_type, function_type, input_params, return_type, descript, sys_role, source)
VALUES (3009,'anl_drained_flows_recursive', 'ud', 'function', '???', '???', 'Auxiliar function to analyze drained flows', 'role_epa', 'toolbox extras drained_flows') 
ON CONFLICT (function_name, project_type) DO NOTHING;