module Masks
  class Scope < ApplicationRecord
    self.table_name = "masks_scopes"

    validates :key, :owner_id, :owner_type, presence: true
    validates :key, uniqueness: { scope: %i[owner_id owner_type] }

    def client=(client)
      raise if owner_type

      self.owner_type = "client"
      self.owner_id = client.key
    end

    def actor=(actor)
      raise if owner_type

      self.owner_type = "actor"
      self.owner_id = actor.key
    end

    def owner
      @owner ||=
        case owner_type
        when "client"
          Masks.client(owner_id)
        when "actor"
          Masks.actor(owner_id)
        when nil
          nil
        else
          raise KeyError
        end
    end
  end
end
