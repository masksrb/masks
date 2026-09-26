module Masks
  module Server
    module Manage
      module Mutations
        class DisableCodeFactor < BaseMutation
          argument :uuid, ID
          argument :factor, String

          field :actor, Types::ActorType, null: false

          def resolve(uuid:, factor:)
            actor = actor!(uuid)

            refuse!("factor must be email or sms") unless CodeFactors.known?(factor)
            refuse!("that factor is not on") unless CodeFactors.disable!(actor, factor, by: viewer)

            DeviceFactor.forget!(actor: actor)

            { actor: actor }
          end
        end
      end
    end
  end
end
