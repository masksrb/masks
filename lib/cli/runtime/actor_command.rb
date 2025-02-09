module Masks
  class ActorCommand < ModelCommand
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

    def preferred_keys
      %w[id key uuid name]
    end

    def settings_json
      Masks::Actor.settings_json
    end
  end
end
