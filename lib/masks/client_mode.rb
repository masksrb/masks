module Masks
  class ClientMode
    include Masks::Mode

    setting :token, :string, env: "MASKS_TOKEN"
    setting :actor_model, :string, default: "Masks::InMemory::Actor"
    setting :client_model, :string, default: "Masks::InMemory::Client"
    setting :device_model, :string, default: "Masks::InMemory::Device"
    setting :token_model, :string, default: "Masks::InMemory::Token"

    setting :use_secrets, :boolean, default: false
    setting :use_sessions, :boolean, default: false

    attr_accessor :settings

    def initialize(settings)
      self.settings = settings
    end

    def cli_commands
      []
    end
  end
end
