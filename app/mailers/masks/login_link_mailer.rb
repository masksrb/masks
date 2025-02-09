module Masks
  class LoginLinkMailer < ApplicationMailer
    include Masks::LoginLinkHelper

    helper_method :code

    def authenticate
      @link = params[:login_link]
      @client = @link.client
      @email = @link.email
      @actor = @link.actor

      mail(to: @email.address, subject: "Your login code to #{@client.name}...")
    end

    def verify
      @link = params[:login_link]
      @client = @link.client
      @email = @link.email
      @actor = @link.actor

      mail(
        to: @email.address,
        subject: "Verify your email to #{@client.name}...",
      )
    end
  end
end
