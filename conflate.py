# Copyright 2011, OpenPlans 
#
# Licensed under the GNU Lesser General Public License 3.0 or any
# later version. See lgpl-3.0.txt for details.

from datetime import datetime

from shapely.geometry import MultiLineString

from shapely.wkb import loads as loads_wkb, dumps as dumps_wkb
from shapely.wkt import loads as loads_wkt, dumps as dumps_wkt

#why on earth is this not done automatically?
from shapely import speedups
if speedups.available:
    speedups.enable()

import psycopg2

conn = psycopg2.connect(database="osm", user="osm", password="osm")

import math

def distance(long1, lat1, long2, lat2):
    """Returns the distance, in meters, between two points on the earth's
    surface identified by latitude, longitude"""
    try:
        degrees_to_radians = math.pi/180.0

        # phi = 90 - latitude
        phi1 = (90.0 - lat1)*degrees_to_radians
        phi2 = (90.0 - lat2)*degrees_to_radians

        # theta = longitude
        theta1 = long1*degrees_to_radians
        theta2 = long2*degrees_to_radians

        cos = (math.sin(phi1)*math.sin(phi2)*math.cos(theta1 - theta2) + 
               math.cos(phi1)*math.cos(phi2))
        arc = math.acos( cos )
    except ValueError:
        import pdb;pdb.set_trace()
    return arc * 6378137

def geom_length(linestring):
    """Returns the length of a linestring in meters"""
    total = 0
    for i in range(len(linestring.coords) - 1):
        total += distance(*(linestring.coords[i] + linestring.coords[i+1]))
    return total

def load_street_segments(conn):
    cursor = conn.cursor()
    q = "SELECT id, way_id, node_from, node_to, name, highway, alt_name, ST_AsBinary(geom) from street_segments"

    segs = {}
    connected_segs = {}

    cursor.execute(q)

    for id, way_id, node_from, node_to, name, highway, alt_name, geom in cursor.fetchall():
        geom = loads_wkb(str(geom))
        name = name or ''
        segs[id] = (way_id, node_from, node_to, name, highway, alt_name)
        seg = dict(id=id,way_id=way_id,node_from=node_from,node_to=node_to,name=name,highway=highway,alt_name=alt_name, geom=geom)
        for node in (node_from, node_to):
            if not node in connected_segs:
                connected_segs[node] = []
            connected_segs[node].append(seg)

    return segs, connected_segs

def crosses_any(segs, new_seg):
    geom = new_seg['geom']
    for seg in segs:
        seg_geom = seg['geom']
        if seg_geom.crosses(geom):
            return True
    return False

def conflate(conn): 
    cursor = conn.cursor()
    segs, connected_segs = load_street_segments(conn)
    visited = set()

    to_insert = []
    from time import time

    start = time()
    for id, (way_id, node_from, node_to, name, highway, alt_name) in segs.iteritems():
        #for each segment, compute the connected segments with the same name, alt_name, and highway values

        if id in visited:
            continue

        q = [node_to, node_from]
        group_segs = []

        i = 0
        visited_from_this_node = []
        while q:
            i += 1
            node = q.pop()
            for seg in connected_segs[node]:
                if seg['id'] in visited:
                    continue
                if seg['name'] == name and seg['highway'] == highway and seg['alt_name'] == alt_name:
                    if not crosses_any(visited_from_this_node, seg):
                        visited.add(seg['id'])
                        visited_from_this_node.append(seg)
                        group_segs.append(seg)
                        q.append(seg['node_from'])
                        q.append(seg['node_to'])

        if not group_segs:
            continue

        group_geoms = [seg['geom'] for seg in group_segs]
        geom = MultiLineString(group_geoms)

        length = sum(geom_length(geom) for geom in group_geoms)
        to_insert.append((name, alt_name, highway, "SRID=4326;" + dumps_wkt(geom), length))

    q = "insert into streets_conflated(name, alt_name, highway, geom, length) values (%s,%s,%s,%s,%s)"
    cursor.executemany(q, to_insert)
    conn.commit()

conflate(conn)
