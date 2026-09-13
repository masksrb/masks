module Manage
  module Mutations
    class CreateAdapter < BaseMutation
      argument :key, ID
      argument :service, String
      argument :name, String
      argument :config, GraphQL::Types::JSON, required: false
      argument :primary, Boolean, required: false

      field :adapter, Types::AdapterType, null: false

      def resolve(key:, service:, name:, config: nil, primary: nil)
        klass = ::Adapter.service_for(service) || refuse!("there is no adapter for #{service}")

        refuse!("an adapter is already keyed #{key}") if ::Adapter.exists?(key: key)

        adapter = klass.new(key: key, name: name)
        adapter.configure(config)
        adapter.primary = primary.nil? ? !::Adapter.active.exists?(kind: klass.kind, primary: true) : primary

        ::Adapter.transaction do
          demote_others(adapter) if adapter.primary
          save!(adapter)
        end

        audit!(::Event::ADAPTER_CREATED, adapter: adapter.key, service: adapter.service)

        { adapter: adapter }
      end

      private

        def demote_others(adapter)
          ::Adapter.active.where(kind: adapter.kind, primary: true).where.not(key: adapter.key)
                   .update_all(primary: false)
        end
    end
  end
end
