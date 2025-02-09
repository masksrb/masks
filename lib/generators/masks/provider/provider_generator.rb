# frozen_string_literal: true

require_relative "../model_generator"

class Masks::ProviderGenerator < Masks::ModelGenerator
  source_root File.expand_path("templates", __dir__)

  private

  def help_json
    types = Masks.conf.provider_map.map { |k, cls| [k, cls.settings] }

    super.merge(type: types.to_h)
  end

  def help_shell
    super

    puts
    log "", "Available types:"
    puts

    Masks.conf.provider_map.each do |key, cls|
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
    @model&.class&.settings_json || Masks::Provider.settings_json
  end

  def find_model
    @model ||= Masks.provider(key)
  end

  def build_model
    @model ||= Masks::Provider.seed(key:, **attrs)
  end
end
