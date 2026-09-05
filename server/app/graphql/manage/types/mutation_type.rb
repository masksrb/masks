module Manage
  module Types
    class MutationType < BaseObject
      field :invite_actor, mutation: Mutations::InviteActor
      field :resend_invitation, mutation: Mutations::ResendInvitation
      field :reset_password, mutation: Mutations::ResetPassword
      field :verify_email, mutation: Mutations::VerifyEmail
      field :update_actor, mutation: Mutations::UpdateActor
      field :set_actor_scopes, mutation: Mutations::SetActorScopes
      field :sign_out_actor, mutation: Mutations::SignOutActor
      field :delete_actor, mutation: Mutations::DeleteActor
      field :generate_backup_codes, mutation: Mutations::GenerateBackupCodes
      field :disable_authenticator, mutation: Mutations::DisableAuthenticator
      field :revoke_passkey, mutation: Mutations::RevokePasskey
      field :remove_avatar, mutation: Mutations::RemoveAvatar
      field :update_client, mutation: Mutations::UpdateClient
      field :rotate_client_secret, mutation: Mutations::RotateClientSecret
      field :archive_client, mutation: Mutations::ArchiveClient
      field :revoke_session, mutation: Mutations::RevokeSession
      field :block_device, mutation: Mutations::BlockDevice
      field :unblock_device, mutation: Mutations::UnblockDevice
      field :sign_out_device, mutation: Mutations::SignOutDevice
      field :update_tenant, mutation: Mutations::UpdateTenant
      field :stage_signing_key, mutation: Mutations::StageSigningKey
      field :activate_signing_key, mutation: Mutations::ActivateSigningKey
      field :discard_signing_key, mutation: Mutations::DiscardSigningKey
      field :rotate_signing_key, mutation: Mutations::RotateSigningKey
    end
  end
end
