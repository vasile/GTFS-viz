## About

This Ruby script is used to convert a set of [GTFS](https://developers.google.com/transit/gtfs/reference) files into a SQLite database + GeoJSONs needed by the [Transit Map](https://github.com/vasile/transit-map) web application that animates vehicles on a map based on timetables and network.

The script was tested on OSX machines with Ruby 1.9.x

## Install

- clone / download the copy of the repo on your machine
- install required Ruby Gems

    	(sudo) gem install json sqlite3 fusion_tables rake

## Setup

- create a folder inside **./gtfs-data** and name it with your project information (i.e. **usa-san-francisco-muni**)
  - the name of the folder should contain letters, digits, +, - characters only
- in this folder unzip the GTFS dataset
  - not sure where to get GTFS data ? Check http://www.gtfs-data-exchange.com/
- edit the Rakefile and change the PROJECT_NAME constant with the folder name

For instance this is how [SFMTA GTFS](http://www.gtfs-data-exchange.com/agency/san-francisco-municipal-transportation-agency/) dataset looks like http://screencast.com/t/5V2q2QZP9W7

## Import

The following Rake Tasks sequence need to be executed. 

	cd /path/to/GTFS-viz

	rake setup:init

	rake parse:gtfs_2_sqlite

	rake parse:shapes_2_geojson
	rake parse:stops_2_geojson
	rake parse:gtfs_2_kml
  
	rake parse:stops_interpolate
  
	rake parse:stops_trips_update

**TODO - add a detailed description about each task and execution times for SFMTA project.**

Check the contents of ./PROJECT_NAME/ , you should have
- gtfs.db, SQLite DB tables of calendar.txt, routes.txt, stop_times.txt, stops.txt, trips.txt
- gtfs_shapes.geojson, gtfs_stops.geojson - GeoJSON files of shapes.txt, stops.txt
- gtfs_shapes.kml, gtfs_stops.kml - KML (Google Earth) files of shapes.txt, stops.txt

## Visualize

You can open the GeoJSON files with [QuantumGIS](https://www.qgis.org/en/site/forusers/download.html) or any other GIS software. Same with the KML files which can be visualized with Google Earth.

If you want to create an animation of the GTFS data you will need to

- download / clone the [Transit Map](https://github.com/vasile/transit-map) web application
- download / clone the [Transit Map Route Icon](https://github.com/vasile/transit-map-route-icon) PHP script
- edit Rakefile and change the PATH_TO_APP_TRANSIT_SIMULATOR, PATH_TO_SCRIPT_ROUTE_ICON constants
- run the tasks below:
	
		cd /path/to/GTFS-viz

		rake project:deploy_fusiontables
  
		rake project:deploy
  
Now you can access the [Transit Map](https://github.com/vasile/transit-map) app in browser and enjoy the animation :)
  
## License

**Copyright (c) 2014 Vasile Coțovanu** - http://www.vasile.ch
 
Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the **following conditions:**
 
* **The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.**
 
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
