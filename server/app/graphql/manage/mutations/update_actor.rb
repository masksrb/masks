module Manage
  module Mutations
    class UpdateActor < BaseMutation
      argument :uuid, ID
      argument :nickname, String, required: false
      argument :email, String, required: false
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

        actor.assign_attributes(attributes)
        actor.email_verified_at = nil if changing_email

        save!(actor)

        audit!(::Event::ACTOR_UPDATED, actor: actor, changed: attributes.keys.map(&:to_s))

        Verifications.open(actor: actor, by: viewer) if changing_email

        { actor: actor }
      end
    end
  end
end
