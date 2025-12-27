module Masks
  class TurnstileAdapter
    include Masks::Adapter

    setting :sitekey, :string
    setting :secret, :string

    def passed?(device)
      device.captcha&.dig(type, 'success')
    end

    def verify(request)
      device = Masks.sessions.current(request)&.device

      return unless device

      if request.params[:token]
        device.verify_captcha(
          request.params[:captcha],
          siteverify(request.params[:token])
        )

        device.save
      end
    end

    def siteverify(response)
      uri = URI('https://challenges.cloudflare.com/turnstile/v0/siteverify')

      params = {
        secret:,
        response:
      }

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      request = Net::HTTP::Post.new(uri.path)
      request.set_form_data(params)
      response = http.request(request)

      if response.is_a?(Net::HTTPSuccess)
        JSON.parse(response.body)
      end
    end
  end
end
