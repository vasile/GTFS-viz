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

    ft_rows = []
    geojson['features'].each do |f|
      if feature_name == 'shapes'
        kml_coordinates = []
        f['geometry']['coordinates'].each do |f_coords|
          kml_coordinates.push("#{f_coords[0]},#{f_coords[1]},0")
        end

        ft_row = {
          'shape_id' => f['properties']['shape_id'],
          'geometry' => '<LineString><coordinates>' + kml_coordinates.join(' ') + '</coordinates></LineString>'
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
    end
    
    # TODO - make the table public - http://screencast.com/t/Wq275qo2
    print "Make sure #{ft_table_name} it's shared to public . Open the link below > Share\n"
    print "https://www.google.com/fusiontables/DataSource?docid=#{ft_table.id}\n"

    return ft_table
  end
end