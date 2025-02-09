module Masks
  class ApplicationMailer < ActionMailer::Base
    default from: -> { Masks.conf.email_from },
            reply_to: -> { Masks.conf.email_reply_to }

    layout "masks/mailer"
  end
end
