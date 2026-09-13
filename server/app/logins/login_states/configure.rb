module LoginStates
  class Configure < LoginState
    HELD = "configuring".freeze

    accepts :called

    handles "setup-configure" do
      configure
    end

    prompts "setup-configure" do
      true
    end

    def enabled?
      login.store[HELD].present? && actor.present? && login.first_factored? &&
        actor.second_factor? && login.store[Enrolment::HELD].blank?
    end

    def as_json
      { "configure" => { "called" => tenant&.name, "steps" => Signup.steps(true) } }
    end

    def start_over!
      login.store.delete(HELD)
    end

    private

      def configure
        called = update(:called).to_s.strip

        tenant.name = called if called.present?

        return warn!("invalid-configuration") unless tenant.save

        login.store.delete(HELD)
      end
  end
end
