module Masks
  class ManagersController < ApplicationController
    include InternalController
    include FrontendController

    managers_only

    rescue_from MissingClientError do
      render_404
    end
  end
end
