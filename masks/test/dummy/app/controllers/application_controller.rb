class ApplicationController < ActionController::Base
  include Masks::Sessions::Controller

  before_action do
    # masks_session.throttle.increment(:captcha) unless request.options?
  end
end
