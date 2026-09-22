module Masks
  module Server
    class ApplicationRecord < ActiveRecord::Base
      primary_abstract_class

      def self.model_name
        @_model_name ||= ActiveModel::Name.new(self, nil, name.delete_prefix("Masks::Server::"))
      end
    end
  end
end
