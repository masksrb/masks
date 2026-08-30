# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_08_29_100008) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

  create_table "actors", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email"
    t.datetime "email_verified_at"
    t.datetime "last_login_at"
    t.string "name"
    t.string "nickname", null: false
    t.datetime "otp_enabled_at"
    t.text "otp_secret"
    t.string "password_digest"
    t.text "scopes", default: "", null: false
    t.bigint "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.uuid "uuid", default: -> { "gen_random_uuid()" }, null: false
    t.index ["tenant_id", "email"], name: "index_actors_on_tenant_id_and_email"
    t.index ["tenant_id", "nickname"], name: "index_actors_on_tenant_id_and_nickname", unique: true
    t.index ["tenant_id"], name: "index_actors_on_tenant_id"
    t.index ["uuid"], name: "index_actors_on_uuid", unique: true
  end

  create_table "clients", force: :cascade do |t|
    t.string "application_type", default: "web", null: false
    t.datetime "archived_at"
    t.string "client_id", null: false
    t.string "client_uri"
    t.datetime "created_at", null: false
    t.boolean "dynamic", default: false, null: false
    t.jsonb "grant_types", default: ["authorization_code"], null: false
    t.string "logo_uri"
    t.string "name", null: false
    t.string "policy_uri"
    t.jsonb "redirect_uris", default: [], null: false
    t.string "registration_token_digest"
    t.jsonb "resources", default: [], null: false
    t.jsonb "response_types", default: ["code"], null: false
    t.text "scopes", default: "", null: false
    t.string "secret_digest"
    t.datetime "secret_expires_at"
    t.bigint "tenant_id", null: false
    t.string "token_endpoint_auth_method", default: "client_secret_basic", null: false
    t.string "tos_uri"
    t.datetime "updated_at", null: false
    t.index ["registration_token_digest"], name: "index_clients_on_registration_token_digest"
    t.index ["tenant_id", "client_id"], name: "index_clients_on_tenant_id_and_client_id", unique: true
    t.index ["tenant_id"], name: "index_clients_on_tenant_id"
  end

  create_table "consents", force: :cascade do |t|
    t.bigint "actor_id", null: false
    t.jsonb "audience", default: [], null: false
    t.bigint "client_id", null: false
    t.datetime "created_at", null: false
    t.datetime "revoked_at"
    t.text "scopes", default: "", null: false
    t.bigint "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_id", "client_id"], name: "index_consents_on_actor_id_and_client_id", unique: true
    t.index ["actor_id"], name: "index_consents_on_actor_id"
    t.index ["client_id"], name: "index_consents_on_client_id"
    t.index ["tenant_id"], name: "index_consents_on_tenant_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.bigint "actor_id", null: false
    t.datetime "authenticated_at", null: false
    t.datetime "created_at", null: false
    t.string "digest", null: false
    t.datetime "expires_at", null: false
    t.string "ip_address"
    t.datetime "revoked_at"
    t.bigint "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.index ["actor_id"], name: "index_sessions_on_actor_id"
    t.index ["digest"], name: "index_sessions_on_digest", unique: true
    t.index ["tenant_id"], name: "index_sessions_on_tenant_id"
  end

  create_table "signing_keys", force: :cascade do |t|
    t.datetime "activated_at"
    t.string "algorithm", default: "RS256", null: false
    t.datetime "created_at", null: false
    t.string "kid", null: false
    t.text "private_pem", null: false
    t.jsonb "public_jwk", null: false
    t.datetime "retired_at"
    t.bigint "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["tenant_id", "activated_at"], name: "index_signing_keys_on_tenant_id_and_activated_at"
    t.index ["tenant_id", "kid"], name: "index_signing_keys_on_tenant_id_and_kid", unique: true
    t.index ["tenant_id"], name: "index_signing_keys_on_tenant_id"
  end

  create_table "tenants", force: :cascade do |t|
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.jsonb "settings", default: {}, null: false
    t.string "subdomain", null: false
    t.datetime "updated_at", null: false
    t.uuid "uuid", default: -> { "gen_random_uuid()" }, null: false
    t.index ["subdomain"], name: "index_tenants_on_subdomain", unique: true
    t.index ["uuid"], name: "index_tenants_on_uuid", unique: true
  end

  create_table "tokens", force: :cascade do |t|
    t.bigint "actor_id"
    t.jsonb "audience", default: [], null: false
    t.bigint "client_id"
    t.string "code_challenge"
    t.string "code_challenge_method"
    t.datetime "consumed_at"
    t.datetime "created_at", null: false
    t.string "digest", null: false
    t.datetime "expires_at", null: false
    t.string "nonce"
    t.bigint "parent_id"
    t.string "redirect_uri"
    t.text "scopes", default: "", null: false
    t.bigint "tenant_id", null: false
    t.string "type", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_id"], name: "index_tokens_on_actor_id"
    t.index ["client_id"], name: "index_tokens_on_client_id"
    t.index ["digest"], name: "index_tokens_on_digest", unique: true
    t.index ["parent_id"], name: "index_tokens_on_parent_id"
    t.index ["tenant_id", "type", "expires_at"], name: "index_tokens_on_tenant_id_and_type_and_expires_at"
    t.index ["tenant_id"], name: "index_tokens_on_tenant_id"
  end

  add_foreign_key "actors", "tenants"
  add_foreign_key "clients", "tenants"
  add_foreign_key "consents", "actors"
  add_foreign_key "consents", "clients"
  add_foreign_key "consents", "tenants"
  add_foreign_key "sessions", "actors"
  add_foreign_key "sessions", "tenants"
  add_foreign_key "signing_keys", "tenants"
  add_foreign_key "tokens", "actors"
  add_foreign_key "tokens", "clients"
  add_foreign_key "tokens", "tenants"
  add_foreign_key "tokens", "tokens", column: "parent_id"
end
