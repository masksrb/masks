module Masks
  module Rails
    class AvatarsController < BaseController
      SIZES = [ 32, 64, 128, 256, 512 ].freeze

      def show
        return head :not_found unless masks_signed_in?

        url = photo_url

        return head :not_found if url.nil?

        deliver(
          Masks::Client::HTTP.fetch(
            url, "Authorization" => masks_tokens.authorization, "Accept" => "image/*"
          )
        )
      rescue Masks::Client::Error
        head :bad_gateway
      end

      private

        def photo_url
          held = masks_claims.avatars.photo

          return nil if held.nil?
          return nil unless held.start_with?("#{masks_config.issuer_for(request)}/")

          asked = params[:size].presence

          return held if asked.nil?

          "#{held}?size=#{SIZES.find { |allowed| allowed >= asked.to_i } || SIZES.last}"
        end

        def deliver(answer)
          case answer
          when Net::HTTPRedirection
            redirect_to answer["Location"], allow_other_host: true
          when Net::HTTPSuccess
            expires_in 5.minutes, public: false

            send_data answer.body, type: answer["Content-Type"], disposition: "inline"
          else
            head :not_found
          end
        end
    end
  end
end
