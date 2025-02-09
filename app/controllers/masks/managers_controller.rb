module Masks
  class ManagersController < ApplicationController
    include Masks::ProtectedController
    include Masks::FrontendController

    mask managers_only: true
  end
end
