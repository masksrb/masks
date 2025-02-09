module Masks
  module Prompts
    class LastLogin
      include Masks::Prompt

      match { true }

      login do
        next unless trusted?

        if !actor.last_login_at || actor.last_login_at < last_login_at
          actor.update_attribute(:last_login_at, last_login_at)
        end
      end

      private

      def last_login_at
        Date.parse(session.entry[:trusted_at] ||= Time.now.utc.iso8601)
      end
    end
  end
end
