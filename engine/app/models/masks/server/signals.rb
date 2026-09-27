module Masks
  module Server
    module Signals
      CAEP = "https://schemas.openid.net/secevent/caep/event-type/".freeze
      RISC = "https://schemas.openid.net/secevent/risc/event-type/".freeze

      SESSION_REVOKED = "#{CAEP}session-revoked".freeze
      CREDENTIAL_CHANGE = "#{CAEP}credential-change".freeze
      ACCOUNT_DISABLED = "#{RISC}account-disabled".freeze
      ACCOUNT_ENABLED = "#{RISC}account-enabled".freeze
      VERIFICATION = "https://schemas.openid.net/secevent/ssf/event-type/verification".freeze

      TYPES = [ SESSION_REVOKED, CREDENTIAL_CHANGE, ACCOUNT_DISABLED, ACCOUNT_ENABLED ].freeze

      Signal = Data.define(:type, :details) do
        def payload(event)
          caep = type.start_with?(CAEP)

          details.merge(
            "event_timestamp" => (event.created_at.to_i if caep),
            "initiating_entity" => (Signals.initiator(event) if caep)
          ).compact
        end
      end

      MAPPED = {
        Event::SESSION_REVOKED => Signal.new(SESSION_REVOKED, {}),
        Event::ACTOR_SIGNED_OUT => Signal.new(SESSION_REVOKED, {}),
        Event::PASSWORD_CHANGED => Signal.new(CREDENTIAL_CHANGE, { "credential_type" => "password", "change_type" => "update" }),
        Event::PASSWORD_RESET_COMPLETED => Signal.new(CREDENTIAL_CHANGE, { "credential_type" => "password", "change_type" => "update" }),
        Event::PASSKEY_ADDED => Signal.new(CREDENTIAL_CHANGE, { "credential_type" => "fido2-platform", "change_type" => "create" }),
        Event::PASSKEY_REMOVED => Signal.new(CREDENTIAL_CHANGE, { "credential_type" => "fido2-platform", "change_type" => "delete" }),
        Event::AUTHENTICATOR_ENABLED => Signal.new(CREDENTIAL_CHANGE, { "credential_type" => "app", "change_type" => "create" }),
        Event::AUTHENTICATOR_DISABLED => Signal.new(CREDENTIAL_CHANGE, { "credential_type" => "app", "change_type" => "delete" }),
        Event::ACTOR_SUSPENDED => Signal.new(ACCOUNT_DISABLED, {}),
        Event::ACTOR_RESTORED => Signal.new(ACCOUNT_ENABLED, {})
      }.freeze

      class << self
        def for(event)
          MAPPED[event.action]
        end

        def initiator(event)
          if event.by_id.nil? then "system"
          elsif event.by_id == event.actor_id then "user"
          else "admin"
          end
        end
      end
    end
  end
end
