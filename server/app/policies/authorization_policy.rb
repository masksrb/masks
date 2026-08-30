class AuthorizationPolicy < Policy
  uses ClientPolicy
  checks :response_type_is_supported,
         :client_may_use_the_code_grant,
         :pkce_is_present_when_required,
         :challenge_method_is_supported,
         :scopes_are_permitted,
         :resources_are_absolute

  delegate :client, :response_type, :requested_scopes, :granted_scopes,
           :code_challenge, :code_challenge_method, :audience, to: :subject

  private

    def response_type_is_supported
      unless Client::RESPONSE_TYPES.include?(response_type)
        deny!("unsupported_response_type",
              "only #{Client::RESPONSE_TYPES.join(', ')} is supported",
              redirectable: true)
      end
    end

    def client_may_use_the_code_grant
      unless client.grants?("authorization_code")
        deny!("unauthorized_client",
              "this client is not registered for the authorization_code grant",
              redirectable: true)
      end
    end

    def pkce_is_present_when_required
      if client.public? && code_challenge.blank?
        deny!("invalid_request",
              "a public client must send code_challenge",
              redirectable: true)
      end
    end

    def challenge_method_is_supported
      return if code_challenge.blank?

      unless Client::CHALLENGE_METHODS.include?(code_challenge_method)
        deny!("invalid_request",
              "code_challenge_method must be #{Client::CHALLENGE_METHODS.join(' or ')}",
              redirectable: true)
      end
    end

    def scopes_are_permitted
      refused = Scopes.list(requested_scopes) - client.scope_list

      if refused.any?
        deny!("invalid_scope",
              "this client may not request #{refused.join(', ')}",
              redirectable: true)
      end

      if granted_scopes.empty?
        deny!("invalid_scope", "no scope was requested", redirectable: true)
      end
    end

    def resources_are_absolute
      audience.each do |value|
        uri = URI.parse(value)

        if uri.scheme.blank? || uri.host.blank? || uri.fragment.present?
          deny!("invalid_target",
                "resource must be an absolute URI without a fragment: #{value}",
                redirectable: true)
        end
      rescue URI::InvalidURIError
        deny!("invalid_target", "resource is not a URI: #{value}", redirectable: true)
      end
    end
end
