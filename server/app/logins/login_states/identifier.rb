module LoginStates
  class Identifier < LoginState
    accepts :identifier

    def reload!
      login.identifier ||= session&.actor&.identifier
    end

    handles "identify" do
      login.identifier = update(:identifier)

      warn! "missing-identifier" if login.identifier.blank?
    end

    handles "start-over" do
      login.start_over!
    end

    prompts "identify" do
      login.identifier.blank? && !login.first_factored?
    end

    def start_over!
      login.identifier = nil
    end
  end
end
