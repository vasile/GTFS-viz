class GTFS
  @db = nil
  
  def self.db_init
    if @db
      return
    end

    if File.file? GTFS_DB_PATH
      @db = SQLite3::Database.open(GTFS_DB_PATH)
    else
      @db = SQLite3::Database.new(GTFS_DB_PATH)
      sql = File.open("#{APP_INC_PATH}/sql/gtfs_init.sql", "r").read
      @db.execute_batch(sql)
    end

    @db.results_as_hash = true
  end

  def self.gtfs_file_count_lines(gtfs_file)
    return %x{wc -l #{gtfs_file}}.split.first.to_i - 1
  end

  def self.csv_line_to_row(headers, line)
    row = {}
    headers.each_with_index do |key, column_key|
      row[key] = line[column_key]
    end
    return row
  end

  def self.parse_file(gtfs_file, method, method_args = nil)
    method_response = nil

    headers = nil
    lines = []
    lines_total = 0
    lines_max = 100000
    IO.foreach(gtfs_file, :encoding => 'bom|utf-8') do |line|
      if headers.nil?
        headers = line.parse_csv
        next
      end

      lines.push(line)
      if lines.size >= lines_max
        lines_total += lines_max
        method_response = self.send(method, headers, lines, method_response, method_args)
        Profiler.save("DONE #{lines_total} lines")
        lines = []
      end
    end
    method_response = self.send(method, headers, lines, method_response, method_args)
    
    return method_response
  end
  
  def self.gtfs_to_sqlite(headers, lines, json, main_args)
    table_name = main_args['table_name']
    table_columns = main_args['table_config']['table_columns']

    # More SQLite improvements here
    # http://stackoverflow.com/questions/1711631/how-do-i-improve-the-performance-of-sqlite
    @db.transaction
      CSV.parse(lines.join).each do |line|
        row = self.csv_line_to_row(headers, line)

        row_values = []
        if table_name == 'stop_times'
          row['arrival_time'] = validate_time(row['arrival_time'])
          row['departure_time'] = validate_time(row['departure_time'])

          if row['departure_time'] == row['arrival_time']
            row['arrival_time'] = hms_shift(row['arrival_time'], -5)
          end
        end

        if table_name == 'stops'
          if row['stop_lat'].to_i == 0 && row['stop_lon'].to_i == 0
            next
          end
        end
        
        table_columns.each do |column|
          value = row[column]
          if value.is_a? String
            value.strip!
          end
          row_values.push(value)
        end
        
        sql = "INSERT INTO #{table_name} (#{table_columns.join(', ')}) VALUES (#{(["?"] * table_columns.length).join(', ')})"
        @db.execute(sql, row_values)
      end
    @db.commit
  end

  def self.shapes_to_geojson(headers, lines, features, main_args)
    if features.nil?
      features = {}
    end

    shapes_color = self::getShapesConfig()

    shapes_not_found = []

    CSV.parse(lines.join).each do |line|
      row = self.csv_line_to_row(headers, line)

      shape_id = row['shape_id']

      if shapes_not_found.include? shape_id
        next
      end

      if shapes_color[shape_id].nil?
        shapes_not_found.push(shape_id)
        print "Shape_id #{shape_id} not used in trips.txt !\n"
        next
      end

      if features[shape_id].nil?
        features[shape_id] = {
          'type' => 'Feature',
          'properties' => {
            'shape_id' => shape_id,
          },
          'geometry' => {
            'type' => 'LineString',
            'coordinates' => []
          }
        }
      end

      features[shape_id]['geometry']['coordinates'].push([row['shape_pt_lon'].to_f, row['shape_pt_lat'].to_f])    
    end

    return features
  end

  def self.stops_to_geojson(headers, lines, json, main_args)
    if json.nil?
      json = {
        "type" => "FeatureCollection",
        "features" => []
      }
    end

    CSV.parse(lines.join).each do |line|
      row = self.csv_line_to_row(headers, line)

      feature = {
        'type' => 'Feature',
        'properties' => {
          'stop_id' => row['stop_id'],
          'stop_code' => row['stop_code'],
          'stop_name' => row['stop_name'],
        },
        'geometry' => {
          'type' => 'Point',
          'coordinates' => [row['stop_lon'].to_f.round(6), row['stop_lat'].to_f.round(6)]
        }
      }

      json['features'].push(feature)
    end

    return json
  end

  def self.geojson_to_kml(feature_name)
    geojson_file = "#{TMP_PATH}/gtfs_#{feature_name}.geojson"
    geojson = JSON.parse(File.open(geojson_file, "r").read)
    
    kml_placemarks = []
    geojson['features'].each do |f|
      kml_placemark = File.open("#{APP_INC_PATH}/inc/templates/kml_placemark_#{feature_name}.xml", "r").read
      f['properties'].each do |key, value|
        kml_placemark.gsub!("{#{key}}", value.nil? ? '' : value)
      end
      
      kml_coordinates = []

      if f['geometry']['type'] == 'LineString'
        f['geometry']['coordinates'].each do |f_coords|
          kml_coordinates.push("#{f_coords[0]},#{f_coords[1]},0")
        end
      end

      if f['geometry']['type'] == 'Point'
        kml_coordinates.push("#{f['geometry']['coordinates'][0]},#{f['geometry']['coordinates'][1]},0")
      end

      kml_placemark.sub!('{coordinates}', kml_coordinates.join(' '))
      kml_placemarks.push(kml_placemark)
    end
    
    kml_content = File.open("#{APP_INC_PATH}/inc/templates/kml_document.xml", "r").read
    kml_content.gsub!('{feature_name}', feature_name)
    kml_content.sub!('{placemarks}', kml_placemarks.join("\n"))
    
    File.open("#{TMP_PATH}/gtfs_#{feature_name}.kml", "w") {|f| f.write(kml_content) }
  end
  
  def self.create_shapes_from_stops
    self.db_init
    
    trips = {}
    shape_id = 1
    
    sql = 'SELECT trip_id FROM trips'
    @db.execute(sql).each do |trip_row|
      sql = 'SELECT stops.stop_id, stop_name, stop_lon, stop_lat, arrival_time, departure_time FROM stop_times, stops WHERE trip_id = ? AND stop_times.stop_id = stops.stop_id ORDER BY stop_sequence'
      
      stop_ids = []

      db_stops = @db.execute(sql, trip_row['trip_id'])
      db_stops.each do |row|
        stop_ids.push(row['stop_id'])
      end

      trip_signature = stop_ids.join('_')
      
      if trips[trip_signature].nil?
        shape_points = []
        db_stops.each do |row|
          shape_points.push({
            'x' => row['stop_lon'].to_f.round(6),
            'y' => row['stop_lat'].to_f.round(6),
          })
        end

        trips[trip_signature] = {
          'signature' => trip_signature,
          'shape_id' => shape_id.to_s,
          'shape_points' => shape_points
        }
        
        shape_id += 1
      end
      
      sql = 'UPDATE trips SET shape_id = ? WHERE trip_id = ?'
      @db.execute(sql, trips[trip_signature]['shape_id'], trip_row['trip_id'])
    end

    return trips.values
  end

  def self.getRoutesConfig
    self.db_init
    sql = 'SELECT DISTINCT route_short_name, route_color,route_text_color FROM routes'
    routes = @db.execute(sql)
    return routes
  end


  def self.getShapesConfig
    if @shapes_config
      return @shapes_config
    end

    @shapes_config = {}

    self.db_init
    sql = 'SELECT DISTINCT shape_id, trips.route_id, route_color, route_text_color FROM trips, routes WHERE trips.route_id = routes.route_id'
    
    rows = @db.execute(sql)
    rows.each do |row|
      @shapes_config[row['shape_id']] = row
    end

    return @shapes_config
  end

  def self.override_tables
    config = YAML.load(File.open("#{Dir.pwd}/inc/gtfs_override.yml"))
    if config[PROJECT_NAME].nil?
      print "Missing #{PROJECT_NAME} definition in ./inc/gtfs_override.yml\n"
      exit
    end

    self.db_init

    config[PROJECT_NAME].each do |config_group|
      config_group.keys.each do |table_name|
        table_field = config_group[table_name]['field_filter']
        rows = config_group[table_name]['values']

        rows.keys.each do |field_value|
          set_items = []

          fields_to_update = rows[field_value]
          fields_to_update.keys.each do |column_name|
            column_value = fields_to_update[column_name]
            if column_value.nil?
              next
            end

            set_items.push("#{column_name} = '#{column_value}'")
          end

          if set_items.length == 0
            next
          end

          sql = "UPDATE #{table_name} SET #{set_items.join(', ')} WHERE #{table_field} = '#{field_value}'"
          @db.execute(sql)
        end
      end
    end
  end
end

# Adapted from https://gist.github.com/j05h/673425
#   loc1 and loc2 are arrays of [latitude, longitude]
def compute_distance (lon1, lat1, lon2, lat2)
  def deg2rad(deg)
    return deg * Math::PI / 180
  end

  dLat = deg2rad(lat2-lat1)
  dLon = deg2rad(lon2-lon1)
  a = Math.sin(dLat/2) * Math.sin(dLat/2) +
      Math.cos(deg2rad(lat1)) * Math.cos(deg2rad(lat2)) *
      Math.sin(dLon/2) * Math.sin(dLon/2)
  c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1-a))
  d = (6371 * c * 1000).to_i
end

def hms_shift(hms, shift_seconds)
  hms_parts = hms.split(':')
  time_s = hms_parts[0].to_i * 3600 + hms_parts[1].to_i * 60 + hms_parts[2].to_i
  
  time_s = time_s + shift_seconds
  hms_shifted = seconds_2_hms(time_s)
  
  return hms_shifted
end

def seconds_2_hms(time_s)
  hh = (time_s / 3600).floor
  mm = ((time_s - hh * 3600) / 60).floor
  ss = time_s - hh * 3600 - mm * 60
  
  return "#{'%02d' % hh}:#{'%02d' % mm}:#{'%02d' % ss}"
end

def validate_time(hms)
  if hms.length === 8
    return hms
  end
  
  if hms.match(/^[0-9]:[0-9]{2}:[0-9]{2}$/)
    return "#{0}hms"
  end
  
  print "GTFS field, unknown time format: #{hms}\n"
  return hms
end