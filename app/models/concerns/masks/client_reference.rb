module Masks
  module ClientReference
    extend ActiveSupport::Concern

    included do
      belongs_to :client, primary_key: "key", class_name: "Masks::Client"
    end

    def client
      @client ||= Masks.client(client_id)
    end
  end
end
