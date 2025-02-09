Rails.application.config.after_initialize do
  if Masks.installation&.persisted?
    Masks.installation&.reconfigured_at = nil
    Masks.installation&.save!
  end
rescue => e
  nil
end
