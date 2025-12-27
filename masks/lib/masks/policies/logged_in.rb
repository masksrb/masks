module Masks
  class LoggedInPolicy
    include Policy
    include RequestMatchers

    # TODO: Implement logged_in policy using the new `on :request` pattern
    #
    # Example:
    #   checks :request do |policy|
    #     # self is the controller (via context: parameter)
    #     # Check if user is logged in, redirect to login if not
    #     unless masks_session.actor
    #       redirect_to masks_login_path
    #     end
    #   end
  end
end
