Rails.application.config.to_prepare do
  FidoMetadata.configure do |config|
    config.cache_backend = Rails.cache
  end
end
