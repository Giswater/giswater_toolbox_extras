/*
This file is part of Giswater 3
The program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This version of Giswater is provided by Giswater Association
*/

SET search_path = "SCHEMA_NAME", public;


CREATE VIEW v_anl_drained_flows_arc AS
SELECT d.*, the_geom
FROM anl_drained_flows_arc d
JOIN arc USING (arc_id);


CREATE VIEW v_anl_drained_flows_node AS
SELECT d.*, the_geom
FROM anl_drained_flows_node d
JOIN node USING (node_id);