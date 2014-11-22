Encoding.default_external = "UTF-8"

require 'json'
require 'csv'
require 'yaml'
require 'sqlite3'

import 'inc/helpers.rb'
import 'inc/gtfs.rb'
import 'inc/ft.rb'

# Allowed characters: letters, digits, -, _
PROJECT_NAME = 'sfmta'
# Path of the repo cloned/downloaded from https://github.com/vasile/transit-map
PATH_TO_APP_TRANSIT_MAP = nil
# Path of the repo cloned/downloaded from https://github.com/vasile/transit-map-route-icon
PATH_TO_SCRIPT_ROUTE_ICON = nil

if Rake.application.options.show_tasks
  print "=======================\n"
  print "Project: #{PROJECT_NAME}\n"
  print "=======================\n"
end

if PROJECT_NAME.match(/^[0-9a-z_-]*$/i).nil?
  print "Invalid project name \"#{PROJECT_NAME}\" !\n"
  print "Allowed characters: letters, digits, -, _\n"
  exit
end

GTFS_FOLDER = "#{Dir.pwd}/gtfs-data/#{PROJECT_NAME}"

if !(File.exists? GTFS_FOLDER)
  print "GTFS project folder not found \"#{GTFS_FOLDER}\" !\n"
  exit
end

ft_login_path = "#{Dir.pwd}/inc/ft_login.rb"
if (File.exists? ft_login_path) == false
  sh "cp #{Dir.pwd}/inc/templates/ft_login.template.rb #{ft_login_path}"
end
import ft_login_path

TMP_PATH = "#{Dir.pwd}/tmp/#{PROJECT_NAME}"
GTFS_DB_PATH = "#{TMP_PATH}/gtfs.db"
GTFS_SQL_PATH = "#{Dir.pwd}/inc/sql"
KML_TEMPLATES = "#{Dir.pwd}/inc/templates"

namespace :setup do
  desc "SETUP: init"
  task :init do
    sh "rm -rf #{TMP_PATH}"
    sh "mkdir -p #{TMP_PATH}"
  end
end

namespace :parse do
  desc "PARSE: GTFS files to SQLite"
  task :gtfs_2_sqlite do
    Profiler.init('START SQL inserts from GTFS files')

    sh "rm -f #{GTFS_DB_PATH}"
    GTFS.db_init

    config = YAML.load(File.open("#{Dir.pwd}/inc/gtfs_mapping.yml"))
    config['tables'].each do |table_name, table_config|
      gtfs_file = "#{GTFS_FOLDER}/#{table_name}.txt"
      if (File.exist? gtfs_file) == false
        print "ERROR: required GTFS table #{table_name} not found !\n"
        print "Expected file: #{gtfs_file}\n"
        exit
      end

      Profiler.save("SQL INSERT #{table_name}, #{GTFS.gtfs_file_count_lines(gtfs_file)} records")
      GTFS.parse_file(gtfs_file, 'gtfs_to_sqlite', {"table_name" => table_name, "table_config" => table_config})
    end

    Profiler.save("DONE SQL INSERTs")
  end

  desc "PARSE: Override GTFS files, see ./inc/gtfs_override.yml file"
  task :gtfs_override do
    GTFS::override_tables()
  end

  desc "PARSE: GTFS shapes.txt file to GeoJSON"
  task :shapes_2_geojson do
    gtfs_file = "#{GTFS_FOLDER}/shapes.txt"
    Profiler.init("START GTFS shapes.txt conversion to GeoJSON, #{GTFS.gtfs_file_count_lines(gtfs_file)} lines")
    
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

      Profiler.save('DONE custom shapes.txt')
    end

    features = GTFS.parse_file(gtfs_file, 'shapes_to_geojson')

    geojson = {
      "type" => "FeatureCollection",
      "features" => features.values
    }

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
    features = {}
    shapes_json['features'].each do |feature|
      features[feature['properties']['shape_id']] = feature
    end

    debug_shape_id = nil
    # debug_shape_id = '110255'

    trips = {}

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
      if trips[trip_signature].nil?
        trips[trip_signature] = {
          'signature' => trip_signature,
          'shape_id' => trip_row['shape_id'],
          'stations' => [],
        }
      else
        next
      end

      if trip_row['shape_id'].nil?
        print "ERROR: Empty shape_id for#{trip_row} !\n"
        trips[trip_signature]['ok'] = false
        next
      end

      shape_coords = features[trip_row['shape_id']]

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
        # END LOOP: Shape coordinates

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

        trips[trip_signature]['stations'].push({
          'stop_id' => row['stop_id'],
          'shape_percent' => shape_percent,
        })

        if debug_shape_id
          print "#{coords_k},#{row['stop_id']},#{p_data['x']},#{p_data['y']},#{shape_percent}\n"
        end
      end
      # END LOOP: Trip Stations
      
      trips[trip_signature]['ok'] = trip_ok
    end
    # END LOOP: Trips

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
        if k % 10000 == 0
          Profiler.save("Trip #{k}/#{trip_rows.length}")
        end

        sql = 'SELECT stops.stop_id, stop_name, stop_lon, stop_lat, arrival_time, departure_time FROM stop_times, stops WHERE trip_id = ? AND stop_times.stop_id = stops.stop_id ORDER BY stop_sequence'
        stop_ids = []

        db_stops = db.execute(sql, trip_row['trip_id'])
        db_stops.each do |row|
          stop_ids.push(row['stop_id'])
        end

        trip_signature = stop_ids.join('_')

        json_trip = json_trips[trip_signature]
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

namespace :project do
  desc "PROJECT: copy the project files in the API folder"
  task :deploy do
    if PATH_TO_APP_TRANSIT_MAP.nil?
      print "WARNING - invalid PATH_TO_APP_TRANSIT_MAP: #{PATH_TO_APP_TRANSIT_MAP} !\n"
      print "ABORT\n"
      exit
    end

    API_FOLDER = "#{PATH_TO_APP_TRANSIT_MAP}/api"

    API_GTFS_FOLDER = "#{API_FOLDER}/gtfs-data"
    sh "rm -rf #{API_GTFS_FOLDER} && mkdir #{API_GTFS_FOLDER}"
    ["gtfs.db", "gtfs_shapes.geojson", "gtfs_stops.geojson"].each do |project_file|
      sh "cp #{TMP_PATH}/#{project_file} #{API_GTFS_FOLDER}/#{project_file}"
    end
    
    API_TMP_FOLDER = "#{API_FOLDER}/tmp"
    sh "rm -rf #{API_TMP_FOLDER} && mkdir #{API_TMP_FOLDER} && chmod 0777 #{API_TMP_FOLDER}"
    sh "mkdir -p #{API_TMP_FOLDER}/cache/db && chmod 0777 #{API_TMP_FOLDER}/cache/db"

    Rake::Task["project:update_settings_ft"].invoke
    Rake::Task["project:update_settings_map"].invoke
    Rake::Task["project:update_settings_routes"].invoke
  end

  desc "PROJECT: push to Fusion Tables (require Google account)"
  task :deploy_fusiontables do
    require 'fusion_tables'
    Profiler.init('START Fusion Tables INSERTs')
    
    ["shapes", "stops"].each do |feature_name|
      FusionTables.update(feature_name)
    end

    Profiler.save('DONE Fusion Tables INSERTs')
  end

  desc "PROJECT: update ALL project settings"
  task :update_settings_all do
    Rake::Task["project:update_settings_ft"].invoke
    Rake::Task["project:update_settings_map"].invoke
    Rake::Task["project:update_settings_routes"].invoke
  end

  desc "PROJECT: update project settings for Fusion Tables"
  task :update_settings_ft do
    if PATH_TO_APP_TRANSIT_MAP.nil?
      print "WARNING - invalid PATH_TO_APP_TRANSIT_MAP: #{PATH_TO_APP_TRANSIT_MAP} !\n"
      print "ABORT\n"
      exit
    end
    
    map_js_config_file = "#{PATH_TO_APP_TRANSIT_MAP}/static/js/config.js"
    map_js_config = JSON.parse(File.open(map_js_config_file, "r").read)

    map_js_config['ft_layer_ids.mask'] = nil
    map_js_config['ft_layer_ids.topology_edges'] = nil
    map_js_config['ft_layer_ids.topology_stations'] = nil
    
    if FT_USERNAME == 'Google_Drive_Username'
      print "NOTICE - rake project:update_settings_ft task need a valid FT_USERNAME\n"
    else
      require 'fusion_tables'
      ["shapes", "stops"].each do |feature_name|
        ft_table = FusionTables.getTable(feature_name)
        map_js_config["ft_layer_ids.gtfs_#{feature_name}"] = ft_table.id
      end
    end

    File.open(map_js_config_file, "w") {|f| f.write(JSON.pretty_generate(map_js_config)) }
  end

  desc "PROJECT: update project settings for map"
  task :update_settings_map do
    if PATH_TO_APP_TRANSIT_MAP.nil?
      print "WARNING - invalid PATH_TO_APP_TRANSIT_MAP: #{PATH_TO_APP_TRANSIT_MAP} !\n"
      print "ABORT\n"
      exit
    end

    map_js_config_file = "#{PATH_TO_APP_TRANSIT_MAP}/static/js/config.js"
    map_js_config = JSON.parse(File.open(map_js_config_file, "r").read)

    map_js_config['api_paths.trips'] = 'api/getTrips/[hhmm]'
    map_js_config['geojson.gtfs_shapes'] = 'api/geojson/gtfs_shapes.geojson'
    map_js_config['geojson.gtfs_stops'] = 'api/geojson/gtfs_stops.geojson'
    map_js_config['geojson.topology_edges'] = nil
    map_js_config['geojson.topology_stations'] = nil
    
    sum_x = sum_y = 0
    geojson = JSON.parse(File.open("#{TMP_PATH}/gtfs_stops.geojson", "r").read)
    geojson['features'].each do |f|
      sum_x += f['geometry']['coordinates'][0]
      sum_y += f['geometry']['coordinates'][1]
    end
    center_x = sum_x / geojson['features'].length
    center_y = sum_y / geojson['features'].length

    map_js_config["center.x"] = center_x.round(6)
    map_js_config["center.y"] = center_y.round(6)

    File.open(map_js_config_file, "w") {|f| f.write(JSON.pretty_generate(map_js_config)) }
  end

  desc "PROJECT: update project settings for routes (color, icons)"
  task :update_settings_routes do
    if PATH_TO_APP_TRANSIT_MAP.nil?
      print "WARNING - invalid PATH_TO_APP_TRANSIT_MAP: #{PATH_TO_APP_TRANSIT_MAP} !\n"
      print "ABORT\n"
      exit
    end

    if PATH_TO_SCRIPT_ROUTE_ICON.nil?
      print "NOTICE - PATH_TO_SCRIPT_ROUTE_ICON is needed for generating the vehicle route icons\n"
    end

    map_js_config_file = "#{PATH_TO_APP_TRANSIT_MAP}/static/js/config.js"
    map_js_config = JSON.parse(File.open(map_js_config_file, "r").read)

    map_js_config["routes"] = {}

    if PATH_TO_SCRIPT_ROUTE_ICON
      sh_line = "rm -f #{PATH_TO_APP_TRANSIT_MAP}/static/images/route_icons/*.png"
      sh sh_line
    end

    routes = GTFS.getRoutesConfig()
    routes.each do |route|
      route_key = route['route_short_name']
      if route_key.nil? || route_key.empty?
        print "Skipping empty route #{route}\n"
        next
      end

      project_icon_rel_path = "static/images/route_icons/#{route_key}.png"
      project_icon_abs_path = "#{PATH_TO_APP_TRANSIT_MAP}/#{project_icon_rel_path}"
      config_icon = false
      if File.exists? project_icon_abs_path
        config_icon = project_icon_rel_path
      else
        if PATH_TO_SCRIPT_ROUTE_ICON
          sh_line = "php #{PATH_TO_SCRIPT_ROUTE_ICON}/route_icon.php bg=#{route['route_color']} fg=#{route['route_text_color']} t=#{route_key}"
          sh(sh_line)

          tmp_file = "#{PATH_TO_SCRIPT_ROUTE_ICON}/tmp/route_icon_#{route_key}.png"
          if File.exists? tmp_file
            sh("mv #{tmp_file} #{project_icon_abs_path}")
            config_icon = project_icon_rel_path
          end
        end
      end

      route_color = route['route_color'].to_s == '' ? '#0178BC' : '#' + route['route_color']
      route_text_color = route['route_text_color'].to_s == '' ? '#FFFFFF' : '#' + route['route_text_color']

      map_js_config["routes"][route_key] = {
        'icon'              => config_icon,
        'route_short_name'  => route['route_short_name'],
        'route_color'       => route_color,
        'route_text_color'  => route_text_color,
      } 
    end

    File.open(map_js_config_file, "w") {|f| f.write(JSON.pretty_generate(map_js_config)) }
  end
end
