class GTFS
  def self.init
    db = SQLite3::Database.new(GTFS_DB_PATH)
    sql = File.open("#{GTFS_SQL_PATH}/gtfs_init.sql", "r").read
    db.execute_batch(sql)
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
    lines_max = 10000
    IO.foreach(gtfs_file) do |line|
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
    db = main_args["db"]
    table_name = main_args['table_name']
    table_columns = main_args['table_config']['table_columns']

    p lines
    exit

    # More SQLite improvements here
    # http://stackoverflow.com/questions/1711631/how-do-i-improve-the-performance-of-sqlite
    db.transaction
      CSV.parse(lines.join).each do |line|
        row = self.csv_line_to_row(headers, line)

        row_values = []
        table_columns.each do |column|
          row_values.push(row[column])
        end

        sql = "INSERT INTO #{table_name} (#{table_columns.join(', ')}) VALUES (#{(["?"] * table_columns.length).join(', ')})"
        db.execute(sql, row_values)
      end
    db.commit
  end

  def self.shapes_to_geojson(headers, lines, json, main_args)
    if json.nil?
      json = {
        "type" => "FeatureCollection",
        "features" => []
      }
    end

    CSV.parse(lines.join).each do |line|
      row = self.csv_line_to_row(headers, line)

      f_found = json['features'].find{|f| f['properties']['shape_id'] == row['shape_id']}
      if f_found.nil?
        f_found = {
          'type' => 'Feature',
          'properties' => {
            'shape_id' => row['shape_id']
          },
          'geometry' => {
            'type' => 'LineString',
            'coordinates' => []
          }
        }

        json['features'].push(f_found)
      end

      f_found['geometry']['coordinates'].push([row['shape_pt_lon'].to_f, row['shape_pt_lat'].to_f])    
    end

    return json
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
          'coordinates' => [row['stop_lon'].to_f, row['stop_lat'].to_f]
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
      kml_placemark = File.open("#{KML_TEMPLATES}/kml_placemark_#{feature_name}.xml", "r").read
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
    
    kml_content = File.open("#{KML_TEMPLATES}/kml_document.xml", "r").read
    kml_content.gsub!('{feature_name}', feature_name)
    kml_content.sub!('{placemarks}', kml_placemarks.join("\n"))
    
    File.open("#{TMP_PATH}/gtfs_#{feature_name}.kml", "w") {|f| f.write(kml_content) }
  end

end