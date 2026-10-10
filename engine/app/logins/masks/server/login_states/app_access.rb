module Masks
  module Server
    module LoginStates
      class AppAccess < LoginState
        def enabled?
          actor.present? && client.present? && login.first_factored?
        end

        def factor!
          return unless enabled? && !client.admits?(actor)

          refused!("not_admitted")
          refuse!("access_denied", "#{actor.identifier} is not in a group that may use #{client.name}")
        end
      end
    end
  end
end
