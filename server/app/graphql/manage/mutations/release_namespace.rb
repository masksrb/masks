module Manage
  module Mutations
    class ReleaseNamespace < BaseMutation
      argument :name, String

      field :released, String, null: false

      def resolve(name:)
        held = Namespace.find_by(name: name) || refuse!("no namespace by that name is claimed")

        unless held.releasable?
          refuse!("#{held.name} is in use by #{held.client.name}; archive it first")
        end

        held.release!

        { released: held.name }
      end
    end
  end
end
