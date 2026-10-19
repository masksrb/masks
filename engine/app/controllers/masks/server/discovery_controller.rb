module Masks
  module Server
    class DiscoveryController < ApplicationController
      OPENID_ISSUER = "http://openid.net/specs/connect/1.0/issuer".freeze
      LONGEST_RESOURCE = 512

      def openid
        render json: issuer.discovery
      end

      def jwks
        expires_in 5.minutes, public: true
        render json: issuer.jwks
      end

      def resource
        render json: issuer.protected_resource
      end

      def webfinger
        resource = params[:resource].to_s
        host = resource_host(resource)

        return head(:bad_request) if host.nil?
        return head(:not_found) unless host.casecmp?(URI.parse(issuer.url).host)

        asked = Array(params[:rel]).map(&:to_s)
        links = [ { "rel" => OPENID_ISSUER, "href" => issuer.url } ]
        links = links.select { |link| asked.include?(link["rel"]) } if asked.any?

        response.headers["Access-Control-Allow-Origin"] = "*"
        render json: { "subject" => resource, "links" => links }, content_type: "application/jrd+json"
      end

      private

        def resource_host(resource)
          return nil if resource.blank? || resource.length > LONGEST_RESOURCE

          if resource.start_with?("acct:")
            account, separator, host = resource.delete_prefix("acct:").rpartition("@")

            return nil if separator.empty? || account.blank? || host.blank? || host.match?(%r{[/\\\s?#]})

            host.sub(/:\d+\z/, "")
          elsif resource.match?(%r{\Ahttps?://})
            URI.parse(resource).host
          end
        rescue URI::InvalidURIError
          nil
        end
    end
  end
end
