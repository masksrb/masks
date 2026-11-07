module Masks
  module Server
    class Client
      module Redirects
        extend ActiveSupport::Concern

        included do
          validate :redirect_uris_are_usable
          validate :post_logout_redirect_uris_are_usable
          validate :backchannel_logout_uri_is_usable
          validate :metadata_uris_are_usable

          normalizes(*METADATA_URIS, with: ->(value) { value.to_s.strip.presence })
        end

        class_methods do
          def loopback?(uri)
            host = uri.host.to_s

            LOOPBACK.include?(host) || host.end_with?(".localhost")
          end
        end

        def redirect_uri?(candidate)
          redirect_uris.include?(candidate.to_s) || redirect_uris.any? { |registered| same_loopback?(registered, candidate.to_s) }
        end

        def redirects?
          saml? || (grant_types & REDIRECTED_GRANT_TYPES).any?
        end

        def redirect_hosts
          redirect_uris.filter_map { |value| SectorIdentifier.host(value) }.uniq
        end

        def link(field)
          value = public_send(field)

          value if LINKS.include?(field) && value.present? && web_uri_refusal(value).nil?
        end

        def notified_on_logout?
          backchannel_logout_uri.present?
        end

        private

          def redirect_uris_are_usable
            if redirect_uris.blank?
              errors.add(:redirect_uris, "must include at least one URI") if redirects?
              return
            end

            redirect_uris.each { |value| redirect_refusal(:redirect_uris, value) }
          end

          def post_logout_redirect_uris_are_usable
            Array(post_logout_redirect_uris).each { |value| redirect_refusal(:post_logout_redirect_uris, value) }
          end

          def backchannel_logout_uri_is_usable
            return if backchannel_logout_uri.blank?

            refusal = web_uri_refusal(backchannel_logout_uri.to_s, fetched: true)
            errors.add(:backchannel_logout_uri, refusal) if refusal
          end

          def metadata_uris_are_usable
            METADATA_URIS.each do |field|
              value = public_send(field)

              next if value.blank? || !will_save_change_to_attribute?(field)

              refusal = web_uri_refusal(value, fetched: field == :logo_uri)
              errors.add(field, refusal) if refusal
            end
          end

          def redirect_refusal(attribute, value)
            uri = URI.parse(value.to_s)

            if uri.fragment.present?
              errors.add(attribute, "must not contain a fragment: #{value}")
            elsif uri.scheme.blank?
              errors.add(attribute, "must be absolute: #{value}")
            elsif SCRIPTED_SCHEMES.include?(uri.scheme.downcase)
              errors.add(attribute, "must not use the #{uri.scheme.downcase} scheme: #{value}")
            elsif uri.scheme.casecmp?("http") && !self.class.loopback?(uri) && !::Rails.env.local?
              errors.add(attribute, "must use https unless it is loopback: #{value}")
            end
          rescue URI::InvalidURIError
            errors.add(attribute, "is not a URI: #{value}")
          end

          def same_loopback?(registered, candidate)
            held = URI.parse(registered)
            asked = URI.parse(candidate)

            [ held, asked ].all? { |uri| uri.instance_of?(URI::HTTP) && LOOPBACK.include?(uri.hostname) && uri.userinfo.nil? && uri.fragment.nil? } &&
              held.hostname == asked.hostname && held.path == asked.path && held.query == asked.query
          rescue URI::InvalidURIError
            false
          end

          def web_uri_refusal(value, fetched: false)
            return "must be at most #{URI_LIMIT} characters" if value.length > URI_LIMIT

            uri = URI.parse(value)

            if !uri.is_a?(URI::HTTP)
              "must be an http or https URL"
            elsif uri.host.blank?
              "must be absolute"
            elsif uri.userinfo.present?
              "must not carry a username or password"
            elsif fetched && uri.fragment.present?
              "must not contain a fragment"
            elsif fetched && dynamic? && !::Rails.env.local?
              dynamic_fetch_refusal(uri)
            elsif uri.scheme == "http" && !self.class.loopback?(uri) && !::Rails.env.local?
              "must use https unless it is loopback"
            end
          rescue URI::InvalidURIError
            "is not a URI"
          end

          def dynamic_fetch_refusal(uri)
            return "must not point at a loopback address" if self.class.loopback?(uri)

            "must use https" unless uri.scheme == "https"
          end
      end
    end
  end
end
