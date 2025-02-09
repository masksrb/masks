module Masks
  module Prompts
    class Identifier
      include Masks::Prompt

      UPDATE_EVENT = "identify"

      match { true }

      reset { session[:identifier] = nil }

      preauth do
        next if actor && identifier

        id =
          if event?(UPDATE_EVENT)
            updates["identifier"]
          elsif session.identifier.tracked
            session.identifier.tracked
          else
            params["login_hint"]
          end

        identify!(id)

        if actor&.new_record? && !actor&.valid?
          warn!("invalid-identifier", prompt: "identify")
        end

        extras(actors:)
      end

      prompt "identify" do
        !identifier
      end

      def identify!(id, actor = nil)
        actor ||= Masks.identify(id) if id

        session[:actor] = actor
        session[:identifier] = id if id
      end

      private

      def actors
        @actors ||=
          session.identifier.map do |bag|
            Masks.identify(bag.current).slice(:identifier, :identicon_id)
          end
      end
    end
  end
end
