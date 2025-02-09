module Masks
  class Installation < ApplicationRecord
    self.table_name = "masks_installations"

    include Masks::Settings

    serialize :settings, coder: JSON

    has_one_attached :light_logo
    has_one_attached :dark_logo
    has_one_attached :favicon
    has_one_attached :styles

    scope :active, -> { where(expired_at: nil) }

    after_create :upload_assets

    def upload_assets
      upload_file(:light_logo, "light-logo.png")
      upload_file(:dark_logo, "dark-logo.png")
      upload_file(:favicon, "favicon.png")
      upload_file(:styles, "styles.css")
    end

    def upload_file(key, path)
      case path
      when String
        io = Masks::Loader.file(path)
        filename = path
      when Pathname
        io = File.open(path)
        filename = path.basename.to_s
      else
        raise "unsupported"
      end

      send(key).attach(io:, filename:)
    end
  end
end
