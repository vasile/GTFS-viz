require 'csv'
require 'json'
require 'google/api_client'

class FT_Export
  @debug = false
  @debug_client = false
  
  @client_issuer = API_CONSOLE_EMAIL_ADDRESS

  @client = nil
  @api_drive = nil
  @api_ft = nil

  def self.init
    if @client
      return
    end

    @client = Google::APIClient.new(:application_name => "Simcity", :application_version => "1.0")
    if @debug_client
      @client.logger.level = Logger::DEBUG
    end

    if @client_issuer.nil?
      print "ERROR: Fusion Tables setup is not done, missing @client_issuer"
      exit      
    end

    client_key_path = "#{APP_INC_PATH}/fusion_tables/client.p12"
    if !(File.exists? client_key_path)
      print "ERROR: Fusion Tables setup is not done, missing client.p12 file"
      exit
    end
    
    key = Google::APIClient::KeyUtils.load_from_pkcs12(client_key_path, 'notasecret')
    @client.authorization = Signet::OAuth2::Client.new(
      :token_credential_uri => 'https://accounts.google.com/o/oauth2/token',
      :audience => 'https://accounts.google.com/o/oauth2/token',
      :scope => ['https://www.googleapis.com/auth/drive', 'https://www.googleapis.com/auth/fusiontables'],
      :issuer => @client_issuer,
      :signing_key => key,
    )
    @client.authorization.fetch_access_token!

    @api_drive = @client.discovered_api('drive', 'v2')
    @api_ft = @client.discovered_api('fusiontables', 'v2')
  end

  def self.topology_export
    self.init
    
    ['shapes', 'stops'].each do |feature_name|
      self.table_export(feature_name)
    end
  end

  def self.table_export(feature_name)
    google_drive_filename = self.drive_filename(feature_name)

    ft_table = nil

    if @debug
      print "Listing DRIVE documents for of #{@client_issuer}\n"
    end

    drive_api_result = @client.execute(
      :api_method => @api_drive.files.list
    )
    drive_api_result.data.items.each do |f|
      if @debug
        print "   #{f['title']} (#{f['id']})\n"
      end
      if f['title'] == google_drive_filename
        ft_table = f
      end
    end

    ft_table = nil

    if ft_table
      tableId = ft_table['id']
    else
      json = JSON.parse(File.open("#{APP_INC_PATH}/fusion_tables/table_def_#{feature_name}.json", "r").read)
      json['name'] = google_drive_filename

      api_result = @client.execute(
        :api_method => @api_ft.table.insert,
        :body_object => json
      )

      ft_table = JSON.parse(api_result.body)
      tableId = ft_table['tableId']

      print "CREATED #{google_drive_filename}\n"
    end

    if feature_name == 'shapes'
      api_result = @client.execute(
        :api_method => @api_ft.style.list,
        :parameters => { 
          'tableId' => tableId,
        },
      )
      if api_result.data.items.count == 0
        json = JSON.parse(File.open("#{APP_INC_PATH}/fusion_tables/ft_styler.json", "r").read)
        api_result = @client.execute(
          :api_method => @api_ft.style.insert,
          :parameters => { 
            'tableId' => tableId,
          },
          :body_object => json
        )
      end
    end

    table_url = "https://www.google.com/fusiontables/DataSource?docid=#{tableId}"
    print "#{feature_name} URL: #{table_url}\n"

    api_result = @client.execute(
      :api_method => @api_drive.permissions.list,
      :parameters => {
        'fileId' => tableId
      }
    )

    if @debug
      print "Listing DRIVE permissions for #{table_url}\n"
    end

    anyone_has_access = false
    api_result.data.items.each do |item|
      name = item['id'] == 'anyone' ? 'ANYONE' : item['name']
      if @debug
        print " - user: #{name}, role #{item['role']}\n"
      end
      
      if item['role'] == 'reader' && item['type'] == 'anyone'
        anyone_has_access = true
      end
    end

    if !anyone_has_access
      self.insert_permission(tableId, 'anyone', 'anyone', 'reader')
    end

    csv_data = self.geojson2csv(feature_name)

    api_result = @client.execute(
      :api_method => @api_ft.table.replace_rows,
      :parameters => { 
        'tableId' => tableId,
        'uploadType' => 'media',
      },
      :body => csv_data
    )

    # Clean up mess - the previous operation creates 'Copy of' tables, lets delete them
    drive_api_result = @client.execute(
      :api_method => @api_drive.files.list
    )
    drive_api_result.data.items.each do |f|
      if f['title'] == "Copy of #{google_drive_filename}"
        api_result = @client.execute(
          :api_method => @api_drive.files.delete,
          :parameters => {
            'fileId' => f['id']
          }
        )
      end
    end
  end

  def self.geojson2csv(feature_name)
    geojson_path = "#{TMP_PATH}/gtfs_#{feature_name}.geojson"
    json = JSON.parse(File.open(geojson_path, 'r').read)
    csv_path = self.csv_file_path(feature_name)

    Profiler.save("Feature #{feature_name} - #{json['features'].length} rows")

    if feature_name == 'shapes'
      shapes_color = GTFS::getShapesConfig()
      kml_linestring_template = IO.read("#{APP_INC_PATH}/templates/kml_linestring.xml")
    end

    CSV.open(csv_path, 'w') do |csv|
      json['features'].each do |f|
        csv_values = []
        
        if feature_name == 'stops'
          f_coords = f['geometry']['coordinates']
          csv_values = [
            f['properties']['stop_id'], 
            f['properties']['stop_name'], 
            "#{f_coords[1]},#{f_coords[0]}"
          ]
        end
        
        if feature_name == 'shapes'
          kml_line_coords = []
          f['geometry']['coordinates'].each do |p|
            kml_line_coords.push(p.join(','))
          end
          kml_linestring = kml_linestring_template.sub('[coordinates]', kml_line_coords.join(" "))

          shape_id = f['properties']['shape_id']
          shape_config = shapes_color[shape_id]
          bg_color = shape_config['route_color'].to_s == '' ? 'FF0000' : shape_config['route_color']

          csv_values = [
            shape_id,
            kml_linestring,
            "##{bg_color}"
          ]
        end

        if csv_values.count > 0
          csv << csv_values
        end
      end
    end

    return File.open(csv_path, "rb").read
  end

  def self.csv_file_path(feature_name)
    return "#{TMP_PATH}/ft_#{feature_name}.csv"
  end

  def self.drive_filename(feature_name)
    return "gtfs_#{PROJECT_NAME}_#{feature_name}"
  end

  def self.insert_permission(file_id, value, type, role)
    if @debug
      print "ADDING #{value} of type:#{type} and role:#{role}\n"
    end

    new_permission = @api_drive.permissions.insert.request_schema.new({
      'value' => value,
      'type' => type,
      'role' => role,
    })
    result = @client.execute(
      :api_method => @api_drive.permissions.insert,
      :body_object => new_permission,
      :parameters => { 
        'fileId' => file_id 
      }
    )
  end

  def self.table_id(feature_name)
    google_drive_filename = self.drive_filename(feature_name)
    
    self.init
    drive_api_result = @client.execute(
      :api_method => @api_drive.files.list
    )
    drive_api_result.data.items.each do |f|
      if f['title'] == google_drive_filename
        return f['id']
      end
    end

    return nil
  end
end