Rails.autoloaders.each do |autoloader|
  autoloader.inflector.inflect("rack_oauth2_endpoint" => "RackOAuth2Endpoint", "oauth2" => "OAuth2")
end
