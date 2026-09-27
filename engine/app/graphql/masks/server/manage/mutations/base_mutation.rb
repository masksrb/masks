module Masks
  module Server
    module Manage
      module Mutations
        class BaseMutation < GraphQL::Schema::Mutation
          class_attribute :level, instance_accessor: false, default: :owner
          class_attribute :level_declared, instance_accessor: false, default: false

          def self.requires(level)
            raise ArgumentError, "no manage level called #{level}" unless ManageRoles::LEVELS.key?(level)

            self.level = level
            self.level_declared = true
          end

          def authorized?(**arguments)
            return super if ManageRoles.permits?(roles, self.class.level)

            refuse!("#{field.name} needs #{ManageRoles::LEVELS.fetch(self.class.level).join(' or ')}")
          end

          private

            def roles
              context[:roles] || []
            end

            def owner?
              ManageRoles.owner?(roles)
            end

            def managed!(actor)
              return actor if owner? || actor.id == viewer.id || !actor.manages?

              refuse!("only an owner can change another manager")
            end

            def granting!(scopes)
              return if owner?

              refuse!("only an owner can hand out #{Scopes.join(ManageRoles.held(scopes))}") if ManageRoles.any?(scopes)
            end

            def viewer
              context[:actor]
            end

            def refuse!(message)
              raise GraphQL::ExecutionError, message
            end

            def audit!(action, actor: nil, client: nil, **details)
              Masks::Server::Event.record!(action, actor: actor, by: viewer, client: client, **details)
            end

            def actor!(uuid)
              managed!(Actor.find_by(uuid: uuid) || refuse!("no actor with that uuid"))
            end

            def client!(client_id)
              client = Client.find_by(client_id: client_id) || refuse!("no client with that client_id")

              if !owner? && ManageRoles.any?(Scopes.union(client.allowed_scopes, client.required_scopes))
                refuse!("only an owner can change a client that can carry a manage scope")
              end

              client
            end

            def device!(id)
              device = Masks::Server::Device.find_by(id: id) || refuse!("no device with that id")

              return device if owner?

              others = Masks::Server::Session.live.where(device: device).where.not(actor_id: viewer.id).includes(:actor)
              refuse!("only an owner can act on a device another manager is signed in on") if others.any? { |held| held.actor.manages? }

              device
            end

            def provider!(key)
              Masks::Server::Provider.find_by(key: key) || refuse!("no provider keyed #{key}")
            end

            def sign_in_policy!(key)
              Masks::Server::SignInPolicy.find_by(key: key) || refuse!("no sign-in policy keyed #{key}")
            end

            def adapter!(key)
              Masks::Server::Adapter.find_by(key: key) || refuse!("no adapter keyed #{key}")
            end

            def event_stream!(key)
              Masks::Server::EventStream.find_by(key: key) || refuse!("no event stream keyed #{key}")
            end

            def organization_named(key)
              return nil if key.blank?

              Masks::Server::Organization.find_by(key: key) || refuse!("no organization keyed #{key}")
            end

            def signing_key!(kid)
              Masks::Server::SigningKey.find_by(kid: kid) || refuse!("no signing key with that kid")
            end

            def save!(record)
              refuse!(record.errors.full_messages.join("; ")) unless record.save

              record
            end
        end
      end
    end
  end
end
