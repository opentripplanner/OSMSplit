-- Copyright 2011, OpenPlans
--
-- Licensed under the GNU Lesser General Public License 3.0 or any
-- later version. See lgpl-3.0.txt for details.

-- Segment OSM ways by intersection to create a routable network

create table street_segments (
       id serial primary key,
       way_id bigint references ways,
       node_from bigint references nodes,
       node_to bigint references nodes ,
       geom geometry,

       --these columns are temporary and are used for building the conflated street data

       name text,
       alt_name text,
       name_1 text,
       oneway text,
       access text,
       maxspeed text,
       junction text,
       highway text
);

-- Intersections are nodes shared by two or more wys

create temporary table intersections(node_id bigint);
insert into intersections select node_id from way_nodes 
       group by node_id having count(way_id) > 1;

-- This table is the same as the way_nodes tables,but adds a column
-- to note whether the node is an intersectoin
create temporary table way_nodes_with_intersection(
       node_id bigint, 
       way_id bigint, 
       sequence_id integer, 
       intersection boolean);

insert into way_nodes_with_intersection 
       select way_nodes.node_id, way_id, sequence_id, intersections.node_id is not null as intersection 
       from nodes, way_nodes 
       left join intersections on intersections.node_id = way_nodes.node_id 
       where way_nodes.node_id=nodes.id;

drop table intersections;

-- First and last nodes of ways are treated as intersections
update way_nodes_with_intersection as o 
       set intersection = true 
       where 
       sequence_id = (
                   select min(x.sequence_id) from way_nodes as x 
                          where x.way_id = o.way_id) 
       or 
       sequence_id = (
                   select max(x.sequence_id) from way_nodes as x 
                          where x.way_id = o.way_id);

-- Fill the street segments table

insert into street_segments (way_id, node_from, node_to, geom, name) 
--This subselect is responsible for getting the geometry
select g.way_id, node_from, node_to, st_makeline(geom order by g.sequence_id), 'Unnamed road' from 
       way_nodes_with_intersection as g, 
       nodes, 

-- and this one gets a from and to node id and sequence number where
-- from and to are intersections and no nodes between from and to are
-- intersections
(select f.way_id, f.node_id as node_from, t.node_id as node_to, f.sequence_id as f_seq, t.sequence_id as t_seq from 
       way_nodes_with_intersection as f, way_nodes_with_intersection as t
       where 
       t.way_id = f.way_id and 
       f.intersection = true and
       t.intersection = true and
       f.sequence_id < t.sequence_id and 
       not exists (select between_wn.node_id as x
         from way_nodes_with_intersection as between_wn
         where 
         between_wn.way_id = f.way_id and
         between_wn.intersection = true and
         between_wn.sequence_id > f.sequence_id and 
         between_wn.sequence_id < t.sequence_id)) as rest_q
       where 
       nodes.id = g.node_id and 
       g.way_id = rest_q.way_id and 
       g.sequence_id >= f_seq and 
       g.sequence_id <= t_seq group by g.way_id, node_from, node_to;

drop table way_nodes_with_intersection;

-- create a table to hold joined streets
create table streets_conflated (
       id serial primary key,
       name text not null,
       alt_name text,
       highway text not null,
       geom geometry,
       length float not null);

-- fill in the name/highway/alt_name

update street_segments set
       access = (select v from way_tags
           where way_tags.way_id = street_segments.way_id and k = 'access'),

       alt_name = (select v from way_tags
           where way_tags.way_id = street_segments.way_id and k = 'alt_name'),

       highway = (select v from way_tags
           where way_tags.way_id = street_segments.way_id and k = 'highway'),

       junction = (select v from way_tags
           where way_tags.way_id = street_segments.way_id and k = 'junction'),

       maxspeed = (select v from way_tags
           where way_tags.way_id = street_segments.way_id and k = 'maxspeed'),

       name = (select v from way_tags
           where way_tags.way_id = street_segments.way_id and k = 'name'),

       name_1 = (select v from way_tags
           where way_tags.way_id = street_segments.way_id and k = 'name_1'),

       oneway = (select v from way_tags
           where way_tags.way_id = street_segments.way_id and k = 'oneway');



update street_segments set name = 'Unnamed street' where name is null;

-- load turn restrictions
create table turn_restrictions (
       osm_restriction_id bigint not null references relations,
       segment_from integer not null references street_segments,
       segment_to integer not null references street_segments,
       node integer not null references nodes,
       type text);

insert into turn_restrictions 
select tags.relation_id, seg1.id, seg2.id, via.member_id, tags.v from
       relation_tags as tags, 
       relation_members as via, 
       relation_members as from_relation, 
       relation_members as to_relation, 
       street_segments as seg1,
       street_segments as seg2
       where
       tags.k = 'restriction' and 
       tags.relation_id = via.relation_id and
       via.relation_id = from_relation.relation_id and
       from_relation.relation_id = to_relation.relation_id and
       via.member_role='via' and via.member_type='N' and
       from_relation.member_role = 'from' and from_relation.member_type='W' and
       to_relation.member_role = 'to' and to_relation.member_type='W' and
       seg1.way_id = from_relation.member_id and
       seg2.way_id = to_relation.member_id and
       (seg1.node_from = via.member_id or seg1.node_to = via.member_id) and 
       (seg2.node_from = via.member_id or seg2.node_to = via.member_id);


--alter table street_segments drop column name;
--alter table street_segments drop column highway;
--alter table street_segments drop column alt_name;