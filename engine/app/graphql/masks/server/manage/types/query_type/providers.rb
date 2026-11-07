module Masks
  module Server
    module Manage
      module Types
        class QueryType
          module Providers
            extend ActiveSupport::Concern
            include GraphQL::Schema::Member::GraphQLTypeNames

            included do
              field :providers, [ ProviderType ], null: false do
                argument :archived, Boolean, required: false
              end

              field :provider, ProviderType do
                argument :key, ID
              end

              field :provider_presets, [ ProviderPresetType ], null: false

              field :connections, [ ConnectionType ], null: false do
                argument :actor, ID, required: false
                argument :provider, ID, required: false
                argument :revoked, Boolean, required: false
                argument :limit, Integer, required: false
              end

              field :domain_claims, [ DomainClaimType ], null: false
            end

            def providers(archived: false)
              scope = Masks::Server::Provider.listed(archived)

              scope.order(:name)
            end

            def provider(key:)
              Masks::Server::Provider.find_by(key: key)
            end

            def provider_presets
              Masks::Server::ProviderPreset.all
            end

            def connections(actor: nil, provider: nil, revoked: false, limit: nil)
              subject = actor.present? ? Actor.find_by(uuid: actor) : nil
              held = provider.present? ? Masks::Server::Provider.find_by(key: provider) : nil

              return Masks::Server::Connection.none if actor.present? && subject.nil?
              return Masks::Server::Connection.none if provider.present? && held.nil?

              scope = Masks::Server::Connection.includes(:provider, :actor).order(created_at: :desc)
              scope = revoked ? scope.where.not(revoked_at: nil) : scope.live unless revoked.nil?
              scope = scope.where(actor: subject) if subject
              scope = scope.where(provider: held) if held

              scope.limit(bounded(limit))
            end

            def domain_claims
              Masks::Server::DomainClaim.includes(:provider).order(:domain)
            end
          end
        end
      end
    end
  end
end
