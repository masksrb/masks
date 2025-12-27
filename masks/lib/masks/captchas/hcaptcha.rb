module Masks
  class HcaptchaAdapter
    include Masks::Adapter

    setting :sitekey, :string
    setting :secret, :string
    setting :variant, :string, default: 'checkbox' # checkbox, invisible

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
      uri = URI('https://hcaptcha.com/siteverify')

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

    def invisible?
      variant == 'invisible'
    end

    def checkbox?
      variant == 'checkbox'
    end
  end
end
