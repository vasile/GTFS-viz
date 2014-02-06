## About

This Ruby script is used to convert a set of [GTFS](https://developers.google.com/transit/gtfs/reference) files into a SQLite database + GeoJSONs needed by the [Transit Simulator](https://github.com/vasile/transit-simulator) web application that animates vehicles on a map based on timetables and network.

The script was tested on OSX machines with Ruby 1.9.x

## Install

- clone / download the copy of the repo on your machine
- install required Ruby Gems

		# (sudo) gem install json sqlite3 fusion_tables rake

## Setup

- create a folder inside **./gtfs-data** and name it with your project information (i.e. **usa-san-francisco-muni**)
	- the newly created folder inside gtfs-data should contain letters, digits, +, - characters only
- get a GTFS dataset and unzip-it inside the folder that you just created (i.e. )
	- not sure where to get one ? Check http://www.gtfs-data-exchange.com/
- edit the Rakefile and change the PROJECT_NAME variable with the folder name

For example this is how the [SFMTA GTFS](http://www.gtfs-data-exchange.com/agency/san-francisco-municipal-transportation-agency/) data looks on the local folder - http://screencast.com/t/5V2q2QZP9W7

## Import

The following Rake Tasks sequence need to be executed. 

	rake setup:init
	
	rake parse:shapes_2_geojson
	rake parse:stops_2_geojson
	rake parse:gtfs_2_kml
	
	rake parse:gtfs_2_sqlite
	
	rake parse:stops_interpolate
	
	rake parse:stops_trips_update
	
	rake project:deploy
	rake project:update_fusiontables
	
	rake project:update_settings_ft
	rake project:update_settings_map
	rake project:update_settings_routes
	rake project:update_name

Now you can access the transit simulator in browser and anjoy the animation :)
	
**TODO - add a detailed description about each task and execution times for SFMTA project.**

## License

**Copyright (c) 2014 Vasile Coțovanu** - http://www.vasile.ch
 
Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the **following conditions:**
 
* **The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.**
 
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
