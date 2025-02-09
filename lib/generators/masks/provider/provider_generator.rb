# frozen_string_literal: true

require_relative "../model_generator"

class Masks::ProviderGenerator < Masks::ModelGenerator
  source_root File.expand_path("templates", __dir__)

  private

  def help_notes
    puts
    log "", "Available types:"
    puts

    Masks.installation.provider_types.each do |key, cls|
      log key, ""
      settings_table(cls.settings)
      puts
    end

    nil
  end

  def preferred_keys
    %w[id key name]
  end

  def settings
    @model&.public_settings || Masks::Provider.settings
  end

  def find_model
    @model ||= Masks.provider(key)
  end

  def build_model
    @model ||= Masks::Provider.seed(key:, **attrs)
  end
end
