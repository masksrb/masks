module Masks
  module Server
    module Manage
      module Mutations
        class UpdateActor < BaseMutation
          requires :support

          argument :uuid, ID
          argument :nickname, String, required: false
          argument :email, String, required: false
          argument :phone, String, required: false
          argument :name, String, required: false
          argument :given_name, String, required: false
          argument :family_name, String, required: false
          argument :middle_name, String, required: false
          argument :profile_url, String, required: false
          argument :picture_url, String, required: false
          argument :website_url, String, required: false
          argument :gender, String, required: false
          argument :birthdate, String, required: false
          argument :zoneinfo, String, required: false
          argument :locale, String, required: false

          field :actor, Types::ActorType, null: false

          def resolve(uuid:, **attributes)
            actor = actor!(uuid)
            changing_email = attributes.key?(:email) && attributes[:email] != actor.email
            previous = actor.email if changing_email && actor.email_verified_at.present?

            actor.assign_attributes(attributes)
            actor.email_verified_at = nil if changing_email
            actor.phone_verified_at = nil if attributes.key?(:phone) && actor.phone_changed?

            save!(actor)

            audit!(Masks::Server::Event::ACTOR_UPDATED, actor: actor, changed: attributes.keys.map(&:to_s))
            audit!(Masks::Server::Event::EMAIL_CHANGED, actor: actor, previous: previous) if changing_email

            Verifications.open(actor: actor, journey: Masks::Server::Journey.manage(viewer)) if changing_email

            { actor: actor }
          end
        end
      end
    end
  end
end
