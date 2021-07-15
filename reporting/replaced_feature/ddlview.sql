/*
This file is part of Giswater 3
The program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This version of Giswater is provided by Giswater Association
*/


SET search_path = SCHEMA_NAME, public, pg_catalog;


-- 2021/7/15
CREATE VIEW v_report_replaced_feature AS
SELECT log_message::json->>'description' as description , log_message::json->>'workcat' as workcat, log_message::json->>'sector' as sector, concat(log_message::json->>'length', ' m') as length, log_message::json->>'oldCatalog' as old, log_message::json->>'newCatalog' as new, tstamp::date as date FROM audit_log_data where fid=143



