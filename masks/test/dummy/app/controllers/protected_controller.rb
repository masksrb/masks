class ProtectedController < ApplicationController
  def show
    render json: { foo: 'bar' }
  end
end
