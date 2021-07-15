/*
This file is part of Giswater 3
The program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This version of Giswater is provided by Giswater Association
*/


SET search_path = SCHEMA_NAME, public, pg_catalog;


-- 2021/7/15
CREATE VIEW v_report_stock_water as
SELECT descript, m3::numeric(12,2), (m3*price)::numeric(12,2) as cost FROM 
(SELECT concat ('Arccat: ', arccat_id) as descript, sum(st_length(the_geom))*wsf*pi()*(dint/2000)^2 as m3 FROM arc
JOIN cat_arc c ON arccat_id = c.id
JOIN (SELECT id, (config->>'stockWaterFactor')::numeric wsf FROM cat_feature where config->>'stockWaterFactor' is not null) b ON b.id = c.arctype_id
WHERE state  = 1
group by arccat_id, dint, wsf
UNION
SELECT concat ('Reservoir: ', node_id),  diameter*(maxlevel-minlevel)*wsf as m3 FROM node
JOIN cat_node c ON nodecat_id = c.id
JOIN (SELECT id, (config->>'stockWaterFactor')::numeric wsf FROM cat_feature where config->>'stockWaterFactor' is not null) b ON b.id = c.nodetype_id
JOIN inp_tank USING (node_id)
ORDER BY 1) a, (SELECT (value::json->>'price')::numeric as price,  (value::json->>'units') as units FROM config_param_system WHERE parameter='admin_report_stock_water') b


