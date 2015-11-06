## About

This Ruby script is used to convert a set of [GTFS](https://developers.google.com/transit/gtfs/reference) files into a SQLite database + GeoJSONs needed by the [Transit Map](https://github.com/vasile/transit-map) web application that animates vehicles on a map based on timetables and network.

The script was tested on OSX machines with Ruby 1.9.x

## Install

- clone / download the copy of the repo on your machine
- install required Ruby Gems

`bundle install`

## Setup

- create a folder inside **./gtfs-data** and name it with your project information
  - the name of the folder can contain letters, digits, +, - characters only
- in this folder unzip the GTFS dataset
  - not sure where to get GTFS data ? Check http://www.gtfs-data-exchange.com/
- edit the Rakefile and change the PROJECT_NAME constant with the folder name, i.e. **sfmta**
- you are ready to parse the GTFS data if you have this [folder structure](http://screencast.com/t/E78YDBuE) and running `rake -T` shows the available tasks: http://screencast.com/t/9bt3i3lfL


## Parse GTFS data

In a terminal window run the following Rake tasks:

	cd /path/to/GTFS-viz

	# Initialize folders and the SQLite DB
	rake setup:init	
	
	# Fill the DB tables defined in ./inc/gtfs_mapping.yml
	rake parse:gtfs_2_sqlite
	
	# Generate GeoJSON files from shapes.txt and stops.txt
	# If the shapes.txt is missing from the GTFS dataset, generate one based on stops.txt
	rake parse:shapes_2_geojson
	rake parse:stops_2_geojson
	
	# Generate KML files from shapes.txt and stops.txt
	rake parse:gtfs_2_kml
  	
	# Find the position of the stops along the shapes, store them in ./tmp/sfmta/trips_shapes.json
	rake parse:stops_interpolate
  	
	# Update DB trips and stop_times
	rake parse:stops_trips_update

Check the contents of ./tmp/sfmta - http://screencast.com/t/V3r5TZBn0m
- gtfs.db - SQLite DB tables of calendar.txt, routes.txt, stop_times.txt, stops.txt, trips.txt
- gtfs_shapes.geojson, gtfs_stops.geojson - GeoJSON files of shapes.txt, stops.txt
- gtfs_shapes.kml, gtfs_stops.kml - KML (Google Earth) files of shapes.txt, stops.txt

## Visualize

You can open the GeoJSON files with [QuantumGIS](https://www.qgis.org/en/site/forusers/download.html) or any other GIS software. Same with the KML files which can be visualized using Google Earth.

If you want to create an animation of the GTFS data you will need to

- download / clone the [Transit Map](https://github.com/vasile/transit-map) web application
- download / clone the [Transit Map Route Icon](https://github.com/vasile/transit-map-route-icon) PHP script
- edit Rakefile and change the `PATH_TO_APP_TRANSIT_SIMULATOR`, PATH_TO_SCRIPT_ROUTE_ICON constants

## Setup Fusion Tables API

- create a project under [API Console](https://console.developers.google.com/)
- enable `Drive API` and `Fusion Tables API` under APIs - [screenshot](http://take.ms/eBNt6)
- add a new Credential as `Service Account` and select `P12` as key type - [screenshot](http://take.ms/MrlKz)
- save the key as `client.p12` under `inc/fusion_tables/client.p12`
- copy the email address which is `complicated_string@developer.gserviceaccount.com` and assign it to `API_CONSOLE_EMAIL_ADDRESS` inside `Rakefile` - [screenshot](http://take.ms/bHy2f)

## Update Transit-Map project

- Download / clone the [Transit Map](https://github.com/vasile/transit-map) web application

- Edit Rakefile and change the `PATH_TO_APP_TRANSIT_SIMULATOR`

- In a terminal window run the following Rake tasks:
	
		# Populate FusionTables with shapes.txt and stops.txt
		rake project:deploy_fusiontables
  	
		# Copy the files needed by the Transit Map web application
		rake project:deploy
  
Now, you should be able to see some action in your browser :)

![Swiss railways(SBB)](https://raw.github.com/vasile/transit-map/master/static/images/github_badge_800px.png "Swiss railways(SBB)")
Check SBB network - http://maps.vasile.ch/transit-sbb/
  
## License

**Copyright (c) 2014-2015 Vasile Coțovanu** - http://www.vasile.ch
 
Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the **following conditions:**
 
* **The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.**
 
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
