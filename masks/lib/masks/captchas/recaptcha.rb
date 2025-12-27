module Masks
  class RecaptchaAdapter
    include Masks::Adapter

    setting :sitekey, :string
    setting :secret, :string
    setting :variant, :string, default: 'enterprise' # enterprise, v3, v2_checkbox, v2_invisible
    setting :score_threshold, :float, default: 0.5 # for v3

    VARIANTS = %w[enterprise v3 v2_checkbox v2_invisible].freeze

    def passed?(device)
      result = device.captcha&.dig(type)
      return false unless result&.dig('success')

      # v3 returns a score, check threshold
      if variant == 'v3' && result['score']
        result['score'] >= score_threshold
      else
        true
      end
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
      uri = URI('https://www.google.com/recaptcha/api/siteverify')

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

    def enterprise?
      variant == 'enterprise'
    end

    def invisible?
      %w[enterprise v3 v2_invisible].include?(variant)
    end

    def checkbox?
      variant == 'v2_checkbox'
    end
  end
end
