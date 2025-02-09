# frozen_string_literal: true

require_relative "../model_generator"

class Masks::ClientGenerator < Masks::ModelGenerator
  source_root File.expand_path("templates", __dir__)

  private

  def help_notes
    <<-HELP
You can adjust scopes with the following:

require_scopes=foo,bar  # Requires actors with foo & bar scopes
allow_scopes=baz,foo    # Allows the baz scope, makes foo optional
remove_scopes=foo,baz   # Removes foo and baz scopes. Bar is still required
HELP
  end

  def filter_value(key, value)
    return value if key.end_with?("_expires_in")

    super
  end

  def preferred_keys
    %w[id key name]
  end

  def settings
    Masks::Client.settings
  end

  def find_model
    Masks.client(key)
  end

  def build_model
    Masks::Client.seed(key:, **updates)
  end
end
