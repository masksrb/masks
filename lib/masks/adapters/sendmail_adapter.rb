module Masks
  module Adapters
    class SendmailAdapter
      include Masks::Adapter

      setting :location, :string
      setting :arguments, :string

      def setup?
        true
      end

      def to_mailer
        args = settings.symbolize_keys.compact

        args[:arguments] = args[:arguments].split(" ") if args[:arguments]

        Mail::Sendmail.new(args)
      end
    end
  end
end
