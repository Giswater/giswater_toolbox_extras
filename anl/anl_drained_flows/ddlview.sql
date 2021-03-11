/*
This file is part of Giswater 3
The program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This version of Giswater is provided by Giswater Association
*/

SET search_path = "ud", public;

DROP VIEW IF EXISTS v_anl_drained_flows_result_arc;
CREATE OR REPLACE VIEW v_anl_drained_flows_result_arc AS
SELECT d.*, the_geom
FROM selector_drained_flows s, anl_drained_flows_result_arc d
JOIN arc USING (arc_id)
WHERE s.result_id = d.result_id AND s.cur_user = current_user;


DROP VIEW IF EXISTS v_anl_drained_flows_result_node;
CREATE OR REPLACE VIEW v_anl_drained_flows_result_node AS
SELECT d.*, the_geom
FROM selector_drained_flows s, anl_drained_flows_result_node d
JOIN node USING (node_id)
WHERE s.result_id = d.result_id AND s.cur_user = current_user;

DROP VIEW IF EXISTS v_anl_drained_flows_arc;
CREATE OR REPLACE VIEW v_anl_drained_flows_arc AS
SELECT d.*, the_geom
FROM anl_drained_flows_arc d
JOIN arc USING (arc_id);


DROP VIEW IF EXISTS v_anl_drained_flows_node;
CREATE OR REPLACE VIEW v_anl_drained_flows_node AS
SELECT d.*, the_geom
FROM anl_drained_flows_node d
JOIN node USING (node_id);