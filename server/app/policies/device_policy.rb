class DevicePolicy < Policy
  include GrantChecks

  checks :client_is_known,
         :client_may_use_the_device_grant,
         :scopes_are_permitted,
         :resources_are_absolute

  delegate :client, :requested_scopes, :granted_scopes, :audience, to: :subject

  private

    def client_is_known
      deny!("invalid_client", "no client is registered with that client_id") if client.nil?
    end

    def client_may_use_the_device_grant
      unless client.grants?(DeviceGrant::GRANT_TYPE)
        deny!("unauthorized_client", "this client is not registered for the device grant")
      end
    end
end
