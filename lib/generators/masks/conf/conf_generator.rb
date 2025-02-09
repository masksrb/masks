# frozen_string_literal: true
require_relative "../model_generator"

class Masks::ConfGenerator < Masks::ModelGenerator
  source_root File.expand_path("templates", __dir__)

  private

  def help_header
    <<-HELP
Shows configuration for this masks installation.

If the installation is writable, you will be
able to customize settings:

$ masks conf setting=...
HELP
  end

  def key
    Masks.conf.name
  end

  def find_model
    Masks.conf
  end

  def attrs
    if Masks.conf.writable?
      super
    else
      {}
    end
  end

  def settings
    Masks.conf.class.settings_json
  end

  def preferred_keys
    %w[name url]
  end
end
