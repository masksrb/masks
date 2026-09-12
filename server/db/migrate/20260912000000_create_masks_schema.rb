class CreateMasksSchema < ActiveRecord::Migration[8.1]
  include TenantIsolation

  ISOLATED = %w[
    signing_keys
    actors
    clients
    tokens
    sessions
    consents
    providers
    connections
    passkeys
    devices
    device_factors
    avatars
    namespaces
    events
    subjects
  ].freeze

  def up
    enable_extension "pgcrypto" unless extension_enabled?("pgcrypto")

    create_table :tenants do |t|
      t.uuid :uuid, null: false, default: -> { "gen_random_uuid()" }
      t.string :subdomain, null: false
      t.string :name, null: false
      t.jsonb :settings, null: false, default: {}
      t.datetime :archived_at

      t.timestamps

      t.text :dynamic_client_scopes
      t.text :pairwise_salt
      t.string :named_by
      t.string :dynamic_registration

      t.index :uuid, unique: true
      t.index :subdomain, unique: true
    end

    create_table :actors do |t|
      t.references :tenant, null: false, foreign_key: true
      t.uuid :uuid, null: false, default: -> { "gen_random_uuid()" }
      t.string :nickname
      t.string :name
      t.string :email
      t.string :password_digest
      t.text :scopes, null: false, default: ""
      t.text :otp_secret
      t.datetime :otp_enabled_at
      t.datetime :email_verified_at
      t.datetime :last_login_at

      t.timestamps

      t.string :given_name
      t.string :family_name
      t.string :middle_name
      t.string :profile_url
      t.string :picture_url
      t.string :website_url
      t.string :gender
      t.string :birthdate
      t.string :zoneinfo
      t.string :locale
      t.jsonb :backup_code_digests, null: false, default: []
      t.datetime :backup_codes_generated_at
      t.datetime :activated_at
      t.string :webauthn_id
      t.bigint :otp_last_step
      t.jsonb :muted_notifications, null: false, default: []

      t.check_constraint "nickname IS NOT NULL OR email IS NOT NULL",
                         name: "actors_are_named"

      t.index :uuid, unique: true
      t.index [ :tenant_id, :nickname ], unique: true
      t.index [ :tenant_id, :email ], unique: true
    end

    create_table :signing_keys do |t|
      t.references :tenant, null: false, foreign_key: true
      t.string :kid, null: false
      t.string :algorithm, null: false, default: "RS256"
      t.text :private_pem, null: false
      t.jsonb :public_jwk, null: false
      t.datetime :activated_at
      t.datetime :retired_at

      t.timestamps

      t.index [ :tenant_id, :kid ], unique: true
      t.index [ :tenant_id, :activated_at ]
    end

    create_table :clients do |t|
      t.references :tenant, null: false, foreign_key: true
      t.string :client_id, null: false
      t.string :secret_digest
      t.string :name, null: false
      t.jsonb :redirect_uris, null: false, default: []
      t.jsonb :grant_types, null: false, default: [ "authorization_code" ]
      t.jsonb :response_types, null: false, default: [ "code" ]
      t.jsonb :resources, null: false, default: []
      t.text :allowed_scopes, null: false, default: ""
      t.string :token_endpoint_auth_method, null: false, default: "client_secret_basic"
      t.string :application_type, null: false, default: "web"
      t.string :client_uri
      t.string :logo_uri
      t.string :tos_uri
      t.string :policy_uri
      t.boolean :dynamic, null: false, default: false
      t.string :registration_token_digest
      t.datetime :secret_expires_at
      t.datetime :archived_at

      t.timestamps

      t.datetime :approved_at
      t.references :approved_by, foreign_key: { to_table: :actors }
      t.text :required_scopes, null: false, default: ""
      t.jsonb :post_logout_redirect_uris, null: false, default: []
      t.string :backchannel_logout_uri
      t.boolean :backchannel_logout_session_required, null: false, default: false
      t.boolean :require_pushed_authorization_requests, null: false, default: false
      t.string :subject_type, null: false, default: "public"
      t.string :sector_identifier_uri
      t.boolean :dpop_bound_access_tokens, null: false, default: false

      t.index [ :tenant_id, :client_id ], unique: true
      t.index :registration_token_digest
    end

    create_table :devices do |t|
      t.references :tenant, null: false, foreign_key: true

      t.string :public_id, null: false
      t.string :version, null: false
      t.string :name
      t.string :user_agent
      t.string :ip_address
      t.datetime :last_seen_at, null: false
      t.datetime :blocked_at

      t.timestamps

      t.index [ :tenant_id, :public_id ], unique: true
      t.index [ :tenant_id, :last_seen_at ]
    end

    create_table :device_factors do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :device, null: false, foreign_key: true
      t.references :actor, null: false, foreign_key: true

      t.string :factor, null: false
      t.datetime :satisfied_at, null: false
      t.datetime :expires_at, null: false

      t.timestamps

      t.index [ :device_id, :actor_id, :factor ],
              unique: true, name: "index_device_factors_on_device_and_actor_and_factor"
    end

    create_table :sessions do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :actor, null: false, foreign_key: true
      t.string :digest, null: false
      t.string :user_agent
      t.string :ip_address
      t.datetime :authenticated_at, null: false
      t.datetime :expires_at, null: false
      t.datetime :revoked_at

      t.timestamps

      t.jsonb :amr, null: false, default: []
      t.references :device, foreign_key: true
      t.string :device_version
      t.uuid :uuid, null: false, default: -> { "gen_random_uuid()" }
      t.string :origin

      t.index :digest, unique: true
      t.index [ :tenant_id, :uuid ], unique: true
    end

    create_table :tokens do |t|
      t.references :tenant, null: false, foreign_key: true
      t.string :type, null: false
      t.references :actor, foreign_key: true
      t.references :client, foreign_key: true
      t.references :parent, foreign_key: { to_table: :tokens }
      t.string :digest, null: false
      t.text :scopes, null: false, default: ""
      t.jsonb :audience, null: false, default: []
      t.string :redirect_uri
      t.string :nonce
      t.string :code_challenge
      t.string :code_challenge_method
      t.datetime :expires_at, null: false
      t.datetime :consumed_at

      t.timestamps

      t.datetime :authenticated_at
      t.jsonb :requested_claims
      t.jsonb :payload
      t.references :device, foreign_key: true
      t.references :session, foreign_key: { on_delete: :nullify }
      t.string :user_code_digest
      t.string :jkt

      t.index :digest, unique: true
      t.index [ :tenant_id, :type, :expires_at ]
      t.index [ :tenant_id, :user_code_digest ],
              unique: true, where: "user_code_digest IS NOT NULL"
    end

    create_table :consents do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :actor, null: false, foreign_key: true
      t.references :client, null: false, foreign_key: true
      t.text :scopes, null: false, default: ""
      t.jsonb :audience, null: false, default: []
      t.datetime :revoked_at

      t.timestamps

      t.index [ :actor_id, :client_id ], unique: true
    end

    create_table :providers do |t|
      t.references :tenant, null: false, foreign_key: true
      t.string :key, null: false
      t.string :name, null: false
      t.string :authorization_url, null: false
      t.string :token_url, null: false
      t.string :revocation_url
      t.string :userinfo_url
      t.string :client_id, null: false
      t.text :client_secret
      t.text :scopes, null: false, default: ""
      t.jsonb :authorize_params, null: false, default: {}
      t.string :subject_claim, null: false, default: "sub"
      t.string :label_claim, null: false, default: "email"
      t.datetime :archived_at

      t.timestamps

      t.string :issuer
      t.string :jwks_uri
      t.jsonb :jwks, null: false, default: {}
      t.datetime :jwks_fetched_at
      t.boolean :signs_in, null: false, default: false
      t.boolean :provisions, null: false, default: false
      t.text :email_domains, null: false, default: ""
      t.text :signup_scopes, null: false, default: ""

      t.index [ :tenant_id, :key ], unique: true
      t.index [ :tenant_id, :signs_in ]
    end

    create_table :connections do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :provider, null: false, foreign_key: true
      t.references :actor, null: false, foreign_key: true
      t.uuid :uuid, null: false, default: -> { "gen_random_uuid()" }
      t.string :subject, null: false
      t.string :label
      t.text :scopes, null: false, default: ""
      t.text :refresh_token
      t.text :access_token
      t.datetime :access_token_expires_at
      t.datetime :connected_at
      t.datetime :revoked_at
      t.string :revoked_reason

      t.timestamps

      t.string :email
      t.boolean :email_verified, null: false, default: false
      t.datetime :signed_in_at

      t.index [ :tenant_id, :provider_id, :subject ], unique: true
      t.index :uuid, unique: true
    end

    create_table :passkeys do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :actor, null: false, foreign_key: true

      t.string :name
      t.string :external_id, null: false
      t.text :public_key, null: false
      t.bigint :sign_count, null: false, default: 0
      t.string :aaguid
      t.boolean :discoverable, null: false, default: false
      t.boolean :user_verified, null: false, default: false
      t.datetime :last_used_at

      t.timestamps

      t.index [ :tenant_id, :external_id ], unique: true
    end

    create_table :authenticators do |t|
      t.string :aaguid, null: false
      t.string :name, null: false
      t.string :source, null: false
      t.text :icon
      t.string :certification
      t.jsonb :statuses, null: false, default: []
      t.datetime :compromised_at

      t.timestamps

      t.index :aaguid, unique: true
    end

    create_table :avatars do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :actor, null: false, foreign_key: true

      t.string :content_type, null: false
      t.string :digest, null: false
      t.integer :byte_size, null: false
      t.binary :data, null: false

      t.timestamps

      t.index [ :tenant_id, :actor_id ], unique: true
    end

    create_table :namespaces do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :client, foreign_key: { on_delete: :nullify }

      t.string :name, null: false
      t.string :resource, null: false
      t.datetime :claimed_at, null: false

      t.timestamps

      t.index [ :tenant_id, :name ], unique: true
      t.index [ :tenant_id, :resource ]
    end

    create_table :events do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :actor, foreign_key: { on_delete: :nullify }
      t.references :by, foreign_key: { to_table: :actors, on_delete: :nullify }
      t.references :client, foreign_key: { on_delete: :nullify }
      t.references :device, foreign_key: { on_delete: :nullify }

      t.string :action, null: false
      t.string :ip_address
      t.string :user_agent
      t.jsonb :details, null: false, default: {}

      t.datetime :created_at, null: false

      t.index [ :tenant_id, :created_at ]
      t.index [ :tenant_id, :actor_id, :created_at ]
      t.index [ :tenant_id, :action, :created_at ]
    end

    create_table :subjects do |t|
      t.references :tenant, null: false, foreign_key: true
      t.references :actor, null: false, foreign_key: { on_delete: :cascade }

      t.string :sector, null: false
      t.string :sub, null: false

      t.timestamps

      t.index [ :tenant_id, :actor_id, :sector ], unique: true
      t.index [ :tenant_id, :sub ], unique: true
    end

    ISOLATED.each { |table| enable_row_level_security(table) }
  end

  def down
    ISOLATED.each { |table| disable_row_level_security(table) }

    %i[
      subjects
      events
      namespaces
      avatars
      authenticators
      passkeys
      connections
      providers
      consents
      tokens
      sessions
      device_factors
      devices
      clients
      signing_keys
      actors
      tenants
    ].each { |table| drop_table(table) }
  end
end
