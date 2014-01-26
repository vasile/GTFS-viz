require 'json'
require 'csv'
require 'yaml'
require 'sqlite3'

import 'inc/helpers.rb'
import 'inc/gtfs.rb'

PROJECT_NAME = 'spain-madrid'
# PROJECT_NAME = 'france-paris-ratp-BUS_38'
# PROJECT_NAME = 'france-paris-ratp'
# PROJECT_NAME = "usa-sf-muni"
# PROJECT_NAME = "canada-vancouver-translink"


GTFS_FOLDER = "#{Dir.pwd}/gtfs-data/#{PROJECT_NAME}"
TMP_PATH = "#{Dir.pwd}/tmp/#{PROJECT_NAME}"
GTFS_DB_PATH = "#{TMP_PATH}/gtfs.db"
GTFS_SQL_PATH = "#{Dir.pwd}/inc/sql"
KML_TEMPLATES = "#{Dir.pwd}/inc/templates"

namespace :setup do
  desc "SETUP: init"
  task :init do
    sh "rm -rf #{TMP_PATH}"
    sh "mkdir #{TMP_PATH}"

    GTFS.init
  end
end

namespace :parse do
  desc "PARSE: GTFS files to SQLite"
  task :gtfs_2_sqlite do
    Profiler.init('START SQL inserts from GTFS files')

    sh "rm -f #{GTFS_DB_PATH}"
    GTFS.init

    db = SQLite3::Database.open(GTFS_DB_PATH)

    config = YAML.load(File.open("#{Dir.pwd}/inc/gtfs_mapping.yml"))
    config['tables'].each do |table_name, table_config|
      gtfs_file = "#{GTFS_FOLDER}/#{table_name}.txt"
      if (File.exist? gtfs_file) == false
        print "ERROR: required GTFS table #{table_name} not found !\n"
        print "Expected file: #{gtfs_file}\n"
        exit
      end

      Profiler.save("SQL INSERT #{table_name}, #{GTFS.gtfs_file_count_lines(gtfs_file)} records")
      GTFS.parse_file(gtfs_file, 'gtfs_to_sqlite', {"db" => db, "table_name" => table_name, "table_config" => table_config})
    end

    Profiler.save("DONE SQL INSERTs")
  end

  desc "PARSE: GTFS shapes.txt file to GeoJSON"
  task :shapes_2_geojson do
    gtfs_file = "#{GTFS_FOLDER}/shapes.txt"
    if (File.exists? gtfs_file) == false
      print "Missing shapes.txt file, create one from stops.txt\n"
      trips = GTFS.create_shapes_from_stops
      
      CSV.open(gtfs_file, "w") do |csv|
        csv << ['shape_id', 'shape_pt_lat', 'shape_pt_lon', 'shape_pt_sequence', 'shape_dist_traveled']
        trips.each do |trip|
          trip['shape_points'].each_with_index do |shape_point, k|
            csv << [trip['shape_id'], shape_point['y'], shape_point['x'], k, nil]
          end
        end
      end
    end
    
    Profiler.init("START GTFS shapes.txt conversion to GeoJSON, #{GTFS.gtfs_file_count_lines(gtfs_file)} lines")
    geojson = GTFS.parse_file(gtfs_file, 'shapes_to_geojson')
    File.open("#{TMP_PATH}/gtfs_shapes.geojson", "w") {|f| f.write(JSON.pretty_generate(geojson)) }
    Profiler.save('DONE shapes_2_geojson')
  end

  desc "PARSE: GTFS stops.txt file to GeoJSON"
  task :stops_2_geojson do
    gtfs_file = "#{GTFS_FOLDER}/stops.txt"
    Profiler.init("START GTFS stops.txt conversion to GeoJSON, #{GTFS.gtfs_file_count_lines(gtfs_file)} lines")
    geojson = GTFS.parse_file(gtfs_file, 'stops_to_geojson')
    File.open("#{TMP_PATH}/gtfs_stops.geojson", "w") {|f| f.write(JSON.pretty_generate(geojson)) }
    Profiler.save('DONE stops_2_geojson')
  end

  desc "PARSE: GeoJSON shapes and stops to KML(Fusion Tables)"
  task :gtfs_2_kml do
    ["shapes", "stops"].each do |feature_name|
      GTFS.geojson_to_kml(feature_name)
    end
  end

  desc "PARSE: Interpolate stops along shapes"
  task :stops_interpolate do
    Profiler.init('START stops_interpolate')

    db = SQLite3::Database.open(GTFS_DB_PATH)
    db.results_as_hash = true

    shapes_json = JSON.parse(File.open("#{TMP_PATH}/gtfs_shapes.geojson", "r").read)

    debug_shape_id = nil
    # debug_shape_id = '110255'

    trips = []

    sql = 'SELECT trip_id, shape_id FROM trips'
    if debug_shape_id
      sql += " WHERE shape_id = '#{debug_shape_id}'"
    end

    db.execute(sql).each do |trip_row|
      sql = 'SELECT stops.stop_id, stop_name, stop_lon, stop_lat, arrival_time, departure_time FROM stop_times, stops WHERE trip_id = ? AND stop_times.stop_id = stops.stop_id ORDER BY stop_sequence'
      stop_ids = []

      db_stops = db.execute(sql, trip_row['trip_id'])
      db_stops.each do |row|
        stop_ids.push(row['stop_id'])
      end

      trip_signature = stop_ids.join('_')
      trip_found = trips.find{|t| t['signature'] == trip_signature}
      if trip_found.nil?
        trip_found = {
          'signature' => trip_signature,
          'shape_id' => trip_row['shape_id'],
          'stations' => [],
        }
        trips.push(trip_found)
      else
        next
      end

      shape_coords = shapes_json['features'].find{ |f| f['properties']['shape_id'] == trip_row['shape_id'] }

      if debug_shape_id
        print "DEBUG\n"
        p trip_found
        print "shape_id: #{trip_row['shape_id']}\n" 
        print "Shape coordinates\n"
        print "k,x,y,d_total\n"
      end

      d_total = 0
      shape_coords['properties']['d_total'] = []
      shape_coords['geometry']['coordinates'].each_with_index do |p2, k|
        if k == 0
          d12 = 0
        else
          p1 = shape_coords['geometry']['coordinates'][k-1]
          p1_x = p1[0]
          p1_y = p1[1]
          p2_x = p2[0]
          p2_y = p2[1]
          
          d12 = compute_distance(p1_x, p1_y, p2_x, p2_y)
        end

        d_total += d12
        shape_coords['properties']['d_total'].push(d_total)

        if debug_shape_id
          print "#{k},#{p2[0]},#{p2[1]},#{d_total}\n"
        end
      end

      if debug_shape_id
        print "\n"
        print "Stations lookup\n\n"
        print "k,stop_id,x,y,perc\n"
      end

      coords_k = 0
      
      trip_ok = true
      
      db_stops.each_with_index do |row, k|
        point_found = nil
        shape_percent = nil
        
        if k == 0
          point_found = shape_coords['geometry']['coordinates'][0]
          shape_percent = 0
        end

        if k == (db_stops.length - 1)
          point_found = shape_coords['geometry']['coordinates'][-1]
          shape_percent = 100
        end

        if point_found.nil?
          d_min = 1000
          p_data = nil
          shape_coords['geometry']['coordinates'].each_with_index do |p2, k1|
            if (k1 == 0) || (k1 < coords_k)
              next
            end

            # From http://paulbourke.net/geometry/pointlineplane/
            p1 = shape_coords['geometry']['coordinates'][k1 - 1]

            p1_x = p1[0]
            p1_y = p1[1]
            p2_x = p2[0]
            p2_y = p2[1]
            
            p3_x = row['stop_lon']
            p3_y = row['stop_lat']

            line_u = ((p3_x - p1_x) * (p2_x - p1_x) + (p3_y - p1_y) * (p2_y - p1_y)) / ( (p2_x - p1_x) ** 2 + (p2_y - p1_y) ** 2 )

            if line_u < 0 || line_u.nan?
              p_x = p1_x
              p_y = p1_y
            elsif line_u > 1
              p_x = p2_x
              p_y = p2_y
            else
              p_x = p1_x + line_u * (p2_x - p1_x)
              p_y = p1_y + line_u * (p2_y - p1_y)
            end

            dP3P = compute_distance(p3_x, p3_y, p_x, p_y)

            if dP3P < d_min
              p_data = {
                'coords_k' => k1 - 1,
                'x' => p_x.round(6),
                'y' => p_y.round(6),
              }
              d_min = dP3P
              if debug_shape_id
                p "Station: #{row['stop_id']} found: #{k1},#{d_min}"
              end

              # Maximum distance that a station can be placed from the polyline
              # - useful for shapes like these - http://screencast.com/t/3AXWNfCI7
              if d_min < 20
                break
              end
            end
          end

          if p_data.nil?
            # Incomplete shape_id ? http://screencast.com/t/apW714Tp6u9O
            print "ERROR finding stop_id #{row['stop_id']} along shape_id #{trip_row['shape_id']}\n"
            trip_ok = false
            break
          end

          coords_k = p_data['coords_k']
          
          p1 = shape_coords['geometry']['coordinates'][coords_k]
          d1P = compute_distance(p1[0], p1[1], p_data['x'], p_data['y'])
          p_d_total = shape_coords['properties']['d_total'][coords_k] + d1P
          d_shape = shape_coords['properties']['d_total'][-1]

          shape_percent = ((p_d_total.to_f / d_shape.to_f) * 100).round(2)

          point_found = [p_data['x'], p_data['y']]
        end

        if trip_ok == false
          break
        end
        
        trip_found['stations'].push({
          'stop_id' => row['stop_id'],
          'shape_percent' => shape_percent,
        })

        if debug_shape_id
          print "#{coords_k},#{row['stop_id']},#{point_found[0]},#{point_found[1]},#{shape_percent}\n"
        end
      end
      
      trip_found['ok'] = trip_ok
    end
    
    File.open("#{TMP_PATH}/trips_shapes.json", "w") {|f| f.write(JSON.pretty_generate(trips)) }
    Profiler.save('DONE stops_interpolate')
  end

  desc "PARSE: Update stop_times and trips"
  task :stops_trips_update do
    def hms2day_seconds (hms)
      return hms[0,2].to_i * 3600 + hms[3,2].to_i * 60 + hms[6,2].to_i
    end

    Profiler.init('START stops_trips_update')

    json_trips = JSON.parse(File.open("#{TMP_PATH}/trips_shapes.json", "r").read)

    db = SQLite3::Database.open(GTFS_DB_PATH)
    db.results_as_hash = true

    k_updates = 0

    db.transaction
      sql = 'SELECT trip_id, shape_id FROM trips'
      trip_rows = db.execute(sql)
      trip_rows.each_with_index do |trip_row, k|
        if k % 1000 == 0
          Profiler.save("Trip #{k}/#{trip_rows.length}")
        end

        sql = 'SELECT stops.stop_id, stop_name, stop_lon, stop_lat, arrival_time, departure_time FROM stop_times, stops WHERE trip_id = ? AND stop_times.stop_id = stops.stop_id ORDER BY stop_sequence'
        stop_ids = []

        db_stops = db.execute(sql, trip_row['trip_id'])
        db_stops.each do |row|
          stop_ids.push(row['stop_id'])
        end

        trip_signature = stop_ids.join('_')

        json_trip = json_trips.find{|t| t['signature'] == trip_signature}
        if json_trip['ok'] == false
          sql = 'UPDATE trips SET trip_ok = 0 WHERE trip_id = ?'
          db.execute(sql, trip_row['trip_id'])
          next
        end

        trip_span_midnight = db_stops[0]['departure_time'] > db_stops[-1]['arrival_time']
        trip_start_seconds = hms2day_seconds(db_stops[0]['departure_time'])
        trip_end_seconds = hms2day_seconds(db_stops[-1]['arrival_time'])
        if trip_span_midnight
          trip_end_seconds += 24 * 3600
        end

        sql = 'UPDATE trips SET trip_ok = 1, trip_span_midnight = ?, trip_start_seconds = ?, trip_end_seconds = ? WHERE trip_id = ?'
        db.execute(sql, trip_span_midnight ? 1 : 0, trip_start_seconds, trip_end_seconds, trip_row['trip_id'])

        json_trip['stations'].each do |stop|
          sql = 'UPDATE stop_times SET stop_shape_percent = ? WHERE trip_id = ? AND stop_id = ?'
          db.execute(sql, stop['shape_percent'], trip_row['trip_id'], stop['stop_id'])

          k_updates += 1

          if k_updates > 10000
            db.commit
            db.transaction
            k_updates = 0
          end
        end
      end
    db.commit

    Profiler.save('DONE stops_trips_update')
  end
end

# START EXPERIMENTAL STUFF BELOW

namespace :topology do
  desc "EXPERIMENTAL-TOPOLOGY: parse the routes"
  task :parse_lines do
    json = JSON.parse(File.open("#{Dir.pwd}/export/network_edges.json", "r").read)

    features_new = []
    json['features'].each do |f|
      coordinates_signature = 

      p f['geometry']['coordinates']
      exit
    end

    exit
  end
end