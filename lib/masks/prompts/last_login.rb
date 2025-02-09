module Masks
  module Prompts
    class LastLogin
      include Masks::Prompt

      match { true }

      login do
        next unless trusted?

        if !current_actor.last_login_at ||
             current_actor.last_login_at < last_login_at
          current_actor.update_attribute(:last_login_at, last_login_at)
        end
      end

      private

      def last_login_at
        Date.parse(session.endpoint[:trusted_at] ||= Time.now.utc.iso8601)
      end
    end
  end
end
