# frozen_string_literal: true
require_relative "../model_generator"

class Masks::ActorGenerator < Masks::ModelGenerator
  source_root File.expand_path("templates", __dir__)

  private

  def help_notes
    <<-HELP
  You can adjust scopes with the following:

  assign_scopes=foo,bar  # Assigns the foo & bar scopes
  remove_scopes=foo      # Removes the foo scope
  HELP
  end

  def find_model
    Masks.actor(key, required: true)
  end

  def build_model
    Masks.actor(key)
  end

  def settings
    Masks::Actor.settings
  end

  def preferred_keys
    %w[id key uuid name]
  end
end
