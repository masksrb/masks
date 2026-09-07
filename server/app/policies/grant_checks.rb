module GrantChecks
  private

    def scopes_are_permitted
      refused = Scopes.refused(client.scope_list, requested_scopes)

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
