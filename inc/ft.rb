class FusionTables
  def self.init
    if @ft.nil?
      @ft = GData::Client::FusionTables.new
      if FT_USERNAME == 'Google_Drive_Username'
        print "Invalid FT_USERNAME, check inc/ft_login.rb\n"
        print "ABORT\n"
        exit
      end
      @ft.clientlogin(FT_USERNAME, FT_PASSWORD)
      @ft.set_api_key(FT_KEY)
    end
  end

  def self.find_table(ft_table_name)
    ft_table = nil
    @ft.show_tables.each do |table|
      if table.name == ft_table_name
        ft_table = table
        break
      end
    end
    
    return ft_table
  end
  
  def self.update(feature_name)
    ft_table = self.getTable(feature_name)

    geojson_file = "#{TMP_PATH}/gtfs_#{feature_name}.geojson"
    geojson = JSON.parse(File.open(geojson_file, "r").read)

    Profiler.save("Feature #{feature_name} - #{geojson['features'].length} rows")

    if feature_name == 'shapes'
      shapes_color = GTFS::getShapesConfig()
    end

    ft_rows = []
    geojson['features'].each do |f|
      if feature_name == 'shapes'
        kml_coordinates = []
        f['geometry']['coordinates'].each do |f_coords|
          kml_coordinates.push("#{f_coords[0]},#{f_coords[1]},0")
        end

        shape_id = f['properties']['shape_id']
        shape_config = shapes_color.find{ |s| s['shape_id'] == shape_id}

        if shape_config.nil?
          next
        end

        bg_color = shape_config['route_color'].to_s == '' ? '#FF0000' : shape_config['route_color']

        ft_row = {
          'shape_id' => shape_id,
          'bg_color' => bg_color,
          'geometry' => '<LineString><coordinates>' + kml_coordinates.join(' ') + '</coordinates></LineString>',
        }
        ft_rows.push(ft_row)
      end

      if feature_name == 'stops'
        ft_row = {
          'stop_id' => f['properties']['stop_id'],
          'stop_name' => f['properties']['stop_name'],
          'geometry' => "#{f['geometry']['coordinates'][1]},#{f['geometry']['coordinates'][0]}"
        }
        ft_rows.push(ft_row)
      end
    end

    rows_k = 0

    ft_table.truncate!
    ft_rows.each_slice(100).each do |ft_rows_bunch|
      ft_table.insert(ft_rows_bunch)
      rows_k += ft_rows_bunch.length
      Profiler.save("#{rows_k} rows")
      
      sleep(1)
    end

  end

  def self.getTable(feature_name)
    ft_table_name = "gtfs_#{PROJECT_NAME}_#{feature_name}"
    ft_table_name.gsub!('-', '_')

    if ft_table_name.match(/^[a-z0-9_]+?$/i).nil?
      print "FT Client can handle only letters, numbers and underscores for table name.\n"
      exit
    end

    self.init
    
    ft_table = self.find_table(ft_table_name)
    if ft_table.nil?
      column_definitions = {
        'shapes' => [
          {:name => 'shape_id',   :type => 'string'},  
          {:name => 'geometry',   :type => 'location'},
          {:name => 'bg_color',   :type => 'string'},
        ],
        'stops' => [
          {:name => 'stop_id',    :type => 'string'},  
          {:name => 'stop_name',  :type => 'string'},
          {:name => 'geometry',   :type => 'location'},
        ],
      }

      begin
        ft_table = @ft.create_table(ft_table_name, column_definitions[feature_name])
      rescue
        # https://github.com/tokumine/fusion_tables/issues/19
        ft_table = self.find_table(ft_table_name)
      end

      if feature_name == 'shapes'
        self.updateTableStyles(ft_table.id)
      end
    end
    
    # TODO - make the table public - http://screencast.com/t/Wq275qo2
    print "Make sure #{ft_table_name} it's shared to public . Open the link below > Share\n"
    print "https://www.google.com/fusiontables/DataSource?docid=#{ft_table.id}\n"

    return ft_table
  end

  def self.updateTableStyles(tableId)
    def self.getFTClient(headers = {})
      client = GData::Client::Base.new(
        :clientlogin_service => 'fusiontables',
        :headers => headers
      )
      client.clientlogin(FT_USERNAME, FT_PASSWORD)

      return client
    end

    api_base_url = "https://www.googleapis.com/fusiontables/v1/tables"
    api_table_styles_url = "#{api_base_url}/#{tableId}/styles?key=#{FT_KEY}"

    client = self.getFTClient()
    json_resp = JSON.parse(client.get(api_table_styles_url).body)

    # Delete current styles
    if json_resp['totalItems'] > 0
      json_resp['items'].each do |json_style|
        begin
          api_style_url = "#{api_base_url}/#{tableId}/styles/#{json_style['styleId']}?key=#{FT_KEY}"
          client.delete(api_style_url)
        rescue Exception => e
          # In case of success, the HTTP status code returned is 204 - which confuses the client
          # Catch other status codes
          if e.response.status_code != 204
            p e
            exit
          end
        end
      end
    end

    # Insert style
    style_res = File.read("#{Dir.pwd}/inc/ft_styler.json")

    client = self.getFTClient({
        'Content-Type' => 'application/json'
    })
    json_resp = client.post(api_table_styles_url, style_res)
  end
end