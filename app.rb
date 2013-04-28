require 'rubygems'
require 'bundler'
require 'sinatra/base'
require 'multi_json'
require 'zip/zip'
require 'ffi-ogr'
require 'ffi-geos'
require 'securerandom'
require 'rack/cors'

module GeoMetro
  class App < Sinatra::Base
    configure do
      UPLOAD_PATH = File.expand_path(File.join(File.dirname(__FILE__), 'uploads'))

      use Rack::Cors do
        allow do
          origins '*'
          resource '*', headers: :any, methods: [:get, :post, :options]
        end
      end
    end

    def unzip_shp(zipfile, dest=nil)
      file_name = "gm_#{SecureRandom.urlsafe_base64(24)}"

      Zip::ZipFile.open(zipfile) do |zip|
        zip.each do |file|
          ext = file.name.split('.').last
          path = File.join(UPLOAD_PATH, file_name + '.' + ext)

          zip.extract(file, path) unless File.exist?(path)
        end
      end

      "#{file_name}.shp"
    end

    def shp_to_geojson(shp, epsg_out=4326)
      read_shp = OGR::ShpReader.new.read File.join(UPLOAD_PATH, shp)
      read_shp_sr = read_shp.layers.first.spatial_ref

      file_name = shp.split('.').first

      new_sr = OGR::SpatialReference.from_epsg(epsg_out)

      read_shp.to_geojson "#{UPLOAD_PATH}/#{file_name}.geojson", {spatial_ref: new_sr}
      read_shp.free

      "#{UPLOAD_PATH}/#{file_name}.geojson"
    end

    get '/files/:file.?:format?' do
      send_file("#{UPLOAD_PATH}/#{params[:file]}.#{params[:format]}")
    end

    post '/shp_to_geojson' do
      path = unzip_shp(params['shp'][:tempfile], params['epsg_code'])
      geojson_path = shp_to_geojson(path)

      content_type :json
      geojson = MultiJson.load(IO.read(geojson_path))
      MultiJson.dump({'geojson' => geojson, 'file' => geojson_path.split('/').last.split('.geojson').first})
    end
  end
end
