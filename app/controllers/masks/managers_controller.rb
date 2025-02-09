module Masks
  class ManagersController < ApplicationController
    include Masks::Controller

    managers_only
  end
end
