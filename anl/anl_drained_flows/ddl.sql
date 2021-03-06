/*
This file is part of Giswater 3
The program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.
This version of Giswater is provided by Giswater Association
*/

SET search_path = "SCHEMA_NAME", public;

DROP TABLE IF EXISTS anl_drained_flows_arc CASCADE;
CREATE TABLE anl_drained_flows_arc
(
	-- user columns
	arc_id character varying(16) NOT NULL,
	arccat_id character varying(30) NOT NULL,
	epa_shape character varying(30) NOT NULL, -- catalog of epa's swmm shapes (cat_arc)
	geom1 double precision  DEFAULT 0.00,-- according epa swmmm user's manual (cat_arc)
	geom2 double precision  DEFAULT 0.00,-- according epa swmmm user's manual (cat_arc)
	geom3 double precision  DEFAULT 0.00,-- according epa swmmm user's manual (cat_arc)
	geom4 double precision  DEFAULT 0.00,-- according epa swmmm user's manual (cat_arc)
	length numeric(12,3) DEFAULT 0.00, -- arc length
	area double precision  DEFAULT 0.00,-- conduit's crossection area  (cat_arc)
	manning double precision  DEFAULT 0.00,-- manning's number for mannings formula (cat_mat_arc)
	full_rh double precision  DEFAULT 0.00,-- hydraulic radius at full flow for conduit crossection (m)
	slope double precision  DEFAULT 0.00,-- conduit's slope (m/m)
	full_flow numeric(12,4) DEFAULT 0.00, -- max flow for conduit according manning's formula at full capacity
	isflowreg boolean DEFAULT false, -- conduit is flow regulator: Need to be informed in combination with hasflowreg from anl_drained_flows_node table
	shape_cycles int2 DEFAULT 0, -- some value have been estimated catching closest arcs values (slope, rh or area)
	slope_cycles int2 DEFAULT 0, -- some value have been estimated catching closest arcs values (slope, rh or area)
	material_estimated boolean DEFAULT false, -- some value have been estimated catching closest arcs values (slope, rh or area)

	-- algorithm columns (results)
	drained_area numeric(12,4)  DEFAULT  0.00, -- drained area total, without runoff coefficient
	runoff_area numeric(12,4)  DEFAULT  0.00, -- efective drained area, applying runoff coefficient for each upstream subcatchment
	runoff_flow numeric(12,4)  DEFAULT  0.00, -- Total flow without upstream network limitations using runoff area values (effective areas)
	real_flow numeric(12,4) DEFAULT 0.00, -- real flow according upstream network limitations
	geom1_mod numeric(12,3) DEFAULT 0.00, -- geom1 need to solve runoff_flow
	diff numeric(12,3) DEFAULT 0.00, -- difference againts geom1_mod and geom1
	flow_fflow numeric(12,3) DEFAULT 0.00, -- ratio againts flow and full flow in order to check capacity of conduit
	fflow_vel numeric(12,3) DEFAULT 0.00, -- water velocity using full flow
	fflow_vel_time numeric(12,3) DEFAULT 0.00, -- time of transit for water on that conduit using full flow velocity
	max_runoff_time numeric(12,3) DEFAULT 0.00,  -- maximum runoff time (calculated using fflow for each conduit)
	max_runoff_length numeric(12,3) DEFAULT 0.00, -- maximum runoff length
	CONSTRAINT anl_drainedf_lows_arc_pkey PRIMARY KEY (arc_id),
	CONSTRAINT anl_drained_flows_arc_fkey FOREIGN KEY (arc_id) REFERENCES arc (arc_id) MATCH SIMPLE	ON UPDATE CASCADE ON DELETE CASCADE
);


DROP TABLE IF EXISTS anl_drained_flows_node CASCADE;
CREATE TABLE anl_drained_flows_node
(		
	-- user columns
	node_id character varying(16) NOT NULL,
	node_area double precision  DEFAULT 0.00, -- area drained on node (ha) (A)
	imperv double precision  DEFAULT  0.00, -- runoff coefficient for node area (C)
	dw_flow double precision  DEFAULT  0.00, -- dry wheater flows (m3/s)
	hasflowreg boolean DEFAULT false, -- node has flow regulator: if true, regulator must be as num_outlet - 1 -> mandatory
	flowreg_initflow double precision, -- init flow for flow regulator

	-- algorithm columns (internal)
	node_inflow double precision DEFAULT 0.00, -- inflow generated on node
	max_discharge_capacity double precision DEFAULT 0.00, -- maximun discharge capacity, adding all downstream conduit's capacities
	num_outlet integer DEFAULT 0,  -- number of downstream conduits
	num_wet_outlet integer DEFAULT 0, -- number of downstream conduits with full_flow > 0
	track_id integer DEFAULT 0, -- flag
	
	-- algorithm columns (results)
	drained_area numeric(12,4) DEFAULT  0.00,-- drained area total, without runoff coefficient
	runoff_area numeric(12,4) DEFAULT  0.00, -- efective drained area, applying runoff coefficient for each upstream subcatchment
	runoff_flow numeric(12,4) DEFAULT  0.00, -- efective flow without upstream network limitations using runoff area values
	real_flow numeric(12,4) DEFAULT 0.00, --  real flow according upstream network limitations
	max_runoff_time numeric(12,3) DEFAULT 0.00,  -- maximum runoff time (calculated using fflow for each conduit)
	max_runoff_length numeric(12,3) DEFAULT 0.00, -- maximum runoff length
	CONSTRAINT anl_drained_flows_node_pkey PRIMARY KEY (node_id),
	CONSTRAINT anl_drained_flows_node_fkey FOREIGN KEY (node_id) REFERENCES (node_id) MATCH SIMPLE ON UPDATE CASCADE ON DELETE CASCADE
);



CREATE TABLE anl_drained_flows_result_cat (
result_id varchar(30) PRIMARY KEY,
descript text,
cur_user text,
tstamp timestamp DEFAULT now());


DROP TABLE IF EXISTS selector_drained_flows;
CREATE TABLE selector_drained_flows(
result_id varchar(30) NOT NULL,
cur_user text NOT NULL,
CONSTRAINT selector_drained_flows_pkey PRIMARY KEY (result_id, cur_user)
);


DROP TABLE IF EXISTS anl_drained_flows_result_node CASCADE;
CREATE TABLE anl_drained_flows_result_node(
id serial PRIMARY KEY, 
result_id varchar(30) NOT NULL,
node_id character varying(16) NOT NULL,
node_area double precision,
imperv double precision,
dw_flow double precision,
hasflowreg boolean,
flowreg_initflow double precision,
node_inflow double precision,
max_discharge_capacity double precision,
num_outlet integer,
num_wet_outlet integer,
track_id integer,
drained_area numeric(12,4),
runoff_area numeric(12,4),
runoff_flow numeric(12,4),
real_flow numeric(12,4),
max_runoff_time numeric(12,3) DEFAULT 0.00,  -- 
max_runoff_length numeric(12,3) DEFAULT 0.00,  -- 
CONSTRAINT anl_drained_flows_node_fkey FOREIGN KEY (result_id)
REFERENCES anl_drained_flows_result_cat (result_id) MATCH SIMPLE ON UPDATE CASCADE ON DELETE CASCADE);


DROP TABLE IF EXISTS anl_drained_flows_result_arc CASCADE;
CREATE TABLE anl_drained_flows_result_arc(
id serial PRIMARY KEY,
result_id character varying(30) NOT NULL,
arc_id character varying(16) NOT NULL,
arccat_id character varying(30) NOT NULL,
epa_shape character varying(30) NOT NULL, 
geom1 double precision,
geom2 double precision,
geom3 double precision,
geom4 double precision,
length double precision,
area double precision,
manning double precision,
full_rh double precision,
slope double precision,
fflow numeric(12,4),
isflowreg boolean,
shape_cycles int2,
slope_cycles int2,
material_estimated boolean,
drained_area numeric(12,4),
runoff_area numeric(12,4),
runoff_flow numeric(12,4),
real_flow numeric(12,4),
geom1_mod numeric(12,3),
diff numeric(12,3),
flow_fflow numeric(12,3) DEFAULT 0.00,
fflow_vel numeric(12,3) DEFAULT 0.00,
fflow_vel_time numeric(12,3) DEFAULT 0.00,
max_runoff_time numeric(12,3) DEFAULT 0.00, 
max_runoff_length numeric(12,3) DEFAULT 0.00, 
CONSTRAINT anl_drained_flows_result_arc_fkey FOREIGN KEY (result_id) REFERENCES anl_drained_flows_result_cat (result_id) MATCH SIMPLE ON UPDATE CASCADE ON DELETE CASCADE
);