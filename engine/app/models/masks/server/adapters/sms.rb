module Masks
  module Server
    module Adapters
      class Sms < Adapter
        NUMBER = /\A\+[1-9]\d{6,14}\z/

        self.kind = SMS

        def self.number(value)
          held = Actor.normalize_value_for(:phone, value)

          held&.match?(NUMBER) ? held : nil
        end

        def deliver(to:, body:)
          raise NotImplementedError
        end

        def deliver_test(to)
          number = self.class.number(to)

          raise Failed, "that is not a phone number in international form, like +15551234567" if number.nil?

          deliver(to: number, body: I18n.t("adapters.test.sms", tenant: tenant.name))
        end

        private

          def sender
            self[:from]
          end

          def post_json(url, payload, headers = {})
            request(url, payload.to_json, headers.merge("Content-Type" => "application/json"))
          end

          def post_form(url, form, headers = {})
            post_encoded(url, URI.encode_www_form(form), headers)
          end

          def post_encoded(url, body, headers = {})
            request(url, body, headers.merge("Content-Type" => "application/x-www-form-urlencoded"))
          end

          def basic(user, password)
            "Basic #{Base64.strict_encode64("#{user}:#{password}")}"
          end

          def request(url, body, headers)
            uri = URI(url)
            held = Net::HTTP::Post.new(uri, headers.merge("Accept" => "application/json"))
            held.body = body

            response = Outbound.call(uri, held, open: Outbound::OPEN_TIMEOUT, read: Outbound::READ_TIMEOUT)

            refuse!(response) unless response.is_a?(Net::HTTPSuccess)

            response
          rescue IOError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError, SocketError => error
            raise Failed, "#{self.class.label} could not be reached: #{error.message}"
          end

          def refuse!(response)
            raise Failed, "#{self.class.label} refused the message (#{response.code}): " \
                          "#{Outbound.body(response).byteslice(0, 300)}"
          end

          def parsed(response)
            JSON.parse(Outbound.body(response))
          rescue JSON::ParserError
            {}
          end
      end
    end
  end
end
