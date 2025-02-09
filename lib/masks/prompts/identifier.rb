module Masks
  module Prompts
    class Identifier
      include Masks::Prompt

      setting :identifier, :string

      UPDATE_EVENT = "identify"

      match { true }

      setup do
        session.structure do
          current :identifier,
                  parent: :endpoint,
                  track: true,
                  expiry: Masks::NEVER_EXPIRE,
                  null: true
        end
      end

      reset { session[:identifier] = nil }

      preauth do
        next if current_actor && current_identifier

        id =
          if event?(UPDATE_EVENT)
            identifier
          elsif session.identifier.tracked
            session.identifier.tracked
          else
            login.login_hint
          end

        identify!(id)

        if current_actor&.new_record? && !current_actor&.valid?
          warn!("invalid-identifier")
        end

        extras(actors:)
      end

      prompt "identify" do
        !current_identifier
      end

      def identify!(id, actor = nil)
        actor ||= Masks.actors.identify(id) if id

        session[:actor] = actor
        session[:identifier] = id if id
      end

      private

      def actors
        @actors ||=
          session.identifier.map do |bag|
            Masks.actors.identify(bag.current).slice(:identifier, :identicon_id)
          end
      end
    end
  end
end
