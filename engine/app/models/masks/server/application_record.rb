module Masks
  module Server
    class ApplicationRecord < ActiveRecord::Base
      self.abstract_class = true

      connects_to database: { writing: Server.config.database, reading: Server.config.database } if Server.config.database

      def self.model_name
        @_model_name ||= ActiveModel::Name.new(self, nil, name.delete_prefix("Masks::Server::"))
      end

      def self.encrypts(*names, **options)
        super(*names, **options.reverse_merge(key_provider: Server.key_provider))
      end
    end
  end
end
