module Manage
  module Types
    class MutationType < BaseObject
      field :update_actor, mutation: Mutations::UpdateActor
      field :set_actor_scopes, mutation: Mutations::SetActorScopes
      field :generate_backup_codes, mutation: Mutations::GenerateBackupCodes
      field :disable_authenticator, mutation: Mutations::DisableAuthenticator
      field :update_client, mutation: Mutations::UpdateClient
      field :rotate_client_secret, mutation: Mutations::RotateClientSecret
      field :archive_client, mutation: Mutations::ArchiveClient
      field :revoke_session, mutation: Mutations::RevokeSession
      field :update_tenant, mutation: Mutations::UpdateTenant
    end
  end
end
