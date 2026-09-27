module Masks
  module Server
    module Manage
      module Types
        class OrganizationType < BaseObject
          field :uuid, ID, null: false
          field :key, ID, null: false
          field :name, String, null: false
          field :roles, [ String ], null: false, description: "Every role a member can hold here, owner and member included."
          field :members, [ "Masks::Server::Manage::Types::MembershipType" ], null: false
          field :member_count, Integer, null: false, description: "Members who have accepted."
          field :owner_count, Integer, null: false, description: "Members who have accepted and hold owner."
          field :pending_count, Integer, null: false, description: "Invitations still open, neither accepted nor expired."
          field :live_token_count, Integer, null: false,
                                       description: "Live tokens issued for this organization. Archiving revokes them."
          field :domains, [ DomainClaimType ], null: false,
                          description: "Domains claimed for this organization's providers, proven or not."
          field :provisioning_tokens, [ ProvisioningTokenType ], null: false,
                                      description: "Live provisioning tokens that reach only this organization."
          field :sign_in_policy, SignInPolicyType, description: "The policy for signing in as a member, ahead of the app's and the tenant's."
          field :providers, [ ProviderType ], null: false
          field :events, [ EventType ], null: false, description: "The organization's most recent events."
          field :archived_at, GraphQL::Types::ISO8601DateTime
          field :created_at, GraphQL::Types::ISO8601DateTime, null: false

          def roles
            object.role_list
          end

          def members
            object.memberships.includes(:actor, :invited_by).joins(:actor).order("actors.nickname", "actors.email")
          end

          def providers
            object.providers.active.order(:name)
          end

          def events
            Masks::Server::Event.where(organization: object).newest_first.includes(:actor, :by, :client, :device)
                                .limit(Masks::Server::Event::LIMIT)
          end

          def member_count
            dataloader.with(Sources::MembershipCounts, :members).load(object.id)
          end

          def owner_count
            dataloader.with(Sources::MembershipCounts, :owners).load(object.id)
          end

          def pending_count
            dataloader.with(Sources::MembershipCounts, :pending).load(object.id)
          end

          def live_token_count
            object.tokens.live.count
          end

          def domains
            Masks::Server::DomainClaim.where(provider: object.providers.active).includes(:provider).order(:domain)
          end

          def provisioning_tokens
            Masks::Server::ProvisioningToken.live.where(organization: object).order(created_at: :desc)
          end
        end
      end
    end
  end
end
