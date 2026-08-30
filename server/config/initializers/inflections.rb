Rails.autoloaders.each do |autoloader|
  autoloader.inflector.inflect("rack_oauth2_endpoint" => "RackOAuth2Endpoint")
end
