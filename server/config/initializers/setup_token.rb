Rails.application.configure do
  token = config.masks.setup_token

  if token && token.length < 24 && !Rails.env.local? && ENV["SECRET_KEY_BASE_DUMMY"].blank?
    raise "MASKS_SETUP_TOKEN is #{token.length} characters, and at least 24 are required outside " \
          "development. Whoever holds it creates the first account of every tenant that has none, " \
          "and that account manages the tenant."
  end
end
