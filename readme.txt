You'll need Osmosis and the Osmosis TagTransform plugin, as well as Python, psycopg, and shapely


The plugin is at http://www.imn.htwk-leipzig.de/~cmuelle8/tagtransform.jar
and should be put in osmosis/lib/default/

Then you'll want to set up the database to hold osm data.  This assumes
that you already have a postgis database called osm.

To set up the database:
psql -d osm -f osmosis/script/pgsimple_schema_0.6.sql


To load the data:
osmosis --read-xml file=oregon.osm  --wkv keyValueList=highway.motorway,highway.motorway_link,highway.trunk,highway.trunk_link,highway.primary,highway.primary_link,highway.secondary,highway.secondary_link,highway.tertiary,highway.tertiary_link,highway.residential,highway.residential_link,highway.service,highway.track  --tt tagtransform.xml --write-pgsimp-0.6 user=osm database=osm password=osm

Then run some database creation steps:

psql -d osm -f process.sql

And finally, the street conflation step:

python conflate.py
