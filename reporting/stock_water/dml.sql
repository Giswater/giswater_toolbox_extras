/*
This file is part of Giswater 3
The program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This version of Giswater is provided by Giswater Association
*/


SET search_path = SCHEMA_NAME, public, pg_catalog;


-- 2021/7/15
UPDATE cat_feature SET config = gw_fct_json_object_set_key(config,'stockWaterFactor' , 1) WHERE system_id = 'PIPE';
UPDATE cat_feature SET config = gw_fct_json_object_set_key(config,'stockWaterFactor' , 0.8) WHERE system_id = 'TANK';

INSERT INTO config_param_system (parameter, value, descript) VALUES ('admin_report_stock_water', '{"price":3.45, "units":"R"}', 'Parameter to generate reports of stock water')
