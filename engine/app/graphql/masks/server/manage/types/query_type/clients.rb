module Masks
  module Server
    module Manage
      module Types
        class QueryType
          module Clients
            extend ActiveSupport::Concern
            include GraphQL::Schema::Member::GraphQLTypeNames

            included do
              field :clients, [ ClientType ], null: false do
                argument :search, String, required: false
                argument :archived, Boolean, required: false
                argument :after_id, ID, required: false
                argument :limit, Integer, required: false
              end

              field :client_count, Integer, null: false do
                argument :search, String, required: false
                argument :archived, Boolean, required: false
              end

              field :client, ClientType do
                argument :client_id, ID
              end

              field :tokens, [ TokenType ], null: false do
                argument :actor, ID, required: false
                argument :client, ID, required: false
                argument :kind, String, required: false
                argument :live, Boolean, required: false
                argument :limit, Integer, required: false
              end

              field :consents, [ ConsentType ], null: false do
                argument :actor, ID, required: false
                argument :client, ID, required: false
                argument :revoked, Boolean, required: false
                argument :limit, Integer, required: false
              end

              field :namespaces, [ NamespaceType ], null: false
              field :scopes_supported, [ String ], null: false
              field :app_presets, [ AppPresetType ], null: false

              field :sign_in_policies, [ SignInPolicyType ], null: false do
                argument :archived, Boolean, required: false
              end

              field :sign_in_policy, SignInPolicyType do
                argument :key, ID
              end

              field :default_sign_in_policy, SignInPolicyType, null: false
              field :saml_metadata_url, String, null: false
            end

            def clients(after_id: nil, limit: nil, **filters)
              scope = client_scope(**filters).includes(:approved_by, :namespaces, :sign_in_policy).newest_first
              scope = scope.after(Client.find_by(client_id: after_id)&.id) if after_id.present?

              scope.limit(bounded(limit))
            end

            def client_count(**filters)
              client_scope(**filters).count
            end

            def client(client_id:)
              Client.find_by(client_id: client_id)
            end

            def tokens(actor: nil, client: nil, kind: nil, live: true, limit: nil)
              subject = actor.present? ? Actor.find_by(uuid: actor) : nil
              held = client.present? ? Client.find_by(client_id: client) : nil

              return Masks::Server::Token.none if actor.present? && subject.nil?
              return Masks::Server::Token.none if client.present? && held.nil?

              scope = granted.includes(:actor, :client, :device).order(created_at: :desc)
              scope = scope.live if live
              scope = scope.where(actor: subject) if subject
              scope = scope.where(client: held) if held
              scope = scope.where(kind: typed(kind)) if kind.present?

              scope.limit(bounded(limit))
            end

            def consents(actor: nil, client: nil, revoked: false, limit: nil)
              subject = actor.present? ? Actor.find_by(uuid: actor) : nil
              held = client.present? ? Client.find_by(client_id: client) : nil

              return Masks::Server::Consent.none if actor.present? && subject.nil?
              return Masks::Server::Consent.none if client.present? && held.nil?

              scope = Masks::Server::Consent.includes(:client, :actor).order(updated_at: :desc)
              scope = revoked ? scope.where.not(revoked_at: nil) : scope.live unless revoked.nil?
              scope = scope.where(actor: subject) if subject
              scope = scope.where(client: held) if held

              scope.limit(bounded(limit))
            end

            def namespaces
              Namespace.includes(:client).order(:name)
            end

            def scopes_supported
              Scopes::DESCRIBED.keys + Namespace.order(:name).pluck(:name)
            end

            def app_presets
              Masks::Server::AppPreset.all
            end

            def sign_in_policies(archived: false)
              scope = Masks::Server::SignInPolicy.listed(archived).includes(:clients)

              scope.order(:name)
            end

            def sign_in_policy(key:)
              Masks::Server::SignInPolicy.find_by(key: key)
            end

            def default_sign_in_policy
              Masks::Server::SignInPolicy.for(tenant: Current.tenant)
            end

            def saml_metadata_url
              SamlIdentity.metadata_url(Issuer.new(Current.tenant, Current.origin))
            end

            private

              def client_scope(search: nil, archived: false)
                scope = Client.listed(archived)

                return scope if search.blank?

                term = "%#{Client.sanitize_sql_like(search.strip)}%"
                scope.where("name ILIKE :term OR client_id = :exact", term: term, exact: search.strip)
              end

              def granted
                Masks::Server::Token.where(kind: Types::TokenType::GRANTS)
              end

              def typed(kind)
                raise GraphQL::ExecutionError, "no token kind called #{kind}" unless Types::TokenType::GRANTS.include?(kind.to_s)

                kind.to_s
              end
          end
        end
      end
    end
  end
end
