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

ActiveRecord::Schema[8.0].define(version: 2025_02_28_135522) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index %w[record_type record_id name blob_id],
            name: "index_active_storage_attachments_uniqueness",
            unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index %w[blob_id variation_digest],
            name: "index_active_storage_variant_records_uniqueness",
            unique: true
  end

  create_table "masks_actors", force: :cascade do |t|
    t.string "key"
    t.string "uuid"
    t.string "name"
    t.string "nickname"
    t.string "password_digest"
    t.string "webauthn_id"
    t.string "tz"
    t.text "backup_codes"
    t.text "scopes"
    t.text "settings"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "last_login_at"
    t.datetime "password_changed_at"
    t.datetime "enabled_second_factor_at"
    t.datetime "saved_backup_codes_at"
    t.datetime "notified_inactive_at"
    t.datetime "onboarded_at"
    t.index ["key"], name: "index_masks_actors_on_key", unique: true
    t.index ["nickname"], name: "index_masks_actors_on_nickname", unique: true
    t.index ["uuid"], name: "index_masks_actors_on_uuid", unique: true
  end

  create_table "masks_client_providers", force: :cascade do |t|
    t.integer "client_id"
    t.integer "provider_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["client_id"], name: "index_masks_client_providers_on_client_id"
    t.index %w[provider_id client_id],
            name: "index_masks_client_providers_on_provider_id_and_client_id",
            unique: true
    t.index ["provider_id"], name: "index_masks_client_providers_on_provider_id"
  end

  create_table "masks_clients", force: :cascade do |t|
    t.string "name"
    t.string "key"
    t.string "secret"
    t.string "public_url"
    t.boolean "internal"
    t.boolean "pkce"
    t.text "response_types"
    t.text "grant_types"
    t.text "redirect_uris"
    t.text "scopes"
    t.text "settings"
    t.text "rsa_private_key"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_masks_clients_on_key", unique: true
  end

  create_table "masks_devices", force: :cascade do |t|
    t.string "public_id", null: false
    t.string "user_agent"
    t.string "ip_address"
    t.string "session_id"
    t.bigint "version"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "blocked_at"
    t.index ["public_id"],
            name: "index_masks_devices_on_public_id",
            unique: true
  end

  create_table "masks_emails", force: :cascade do |t|
    t.string "address", null: false
    t.string "group"
    t.datetime "verified_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "actor_id"
    t.index ["actor_id"], name: "index_masks_emails_on_actor_id"
    t.index %w[address group],
            name: "index_masks_emails_on_address_and_group",
            unique: true
  end

  create_table "masks_hardware_keys", force: :cascade do |t|
    t.string "name", null: false
    t.string "aaguid"
    t.string "external_id", null: false
    t.string "public_key", null: false
    t.bigint "sign_count", default: 0, null: false
    t.integer "actor_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "verified_at"
    t.index ["actor_id"], name: "index_masks_hardware_keys_on_actor_id"
    t.index %w[external_id aaguid],
            name: "index_masks_hardware_keys_on_external_id_and_aaguid",
            unique: true
  end

  create_table "masks_installations", force: :cascade do |t|
    t.text "settings"
    t.datetime "expired_at"
    t.datetime "reconfigured_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "masks_login_links", force: :cascade do |t|
    t.string "token"
    t.string "code"
    t.boolean "log_in", default: false, null: false
    t.text "settings"
    t.integer "client_id"
    t.integer "actor_id"
    t.integer "email_id"
    t.integer "device_id"
    t.datetime "revoked_at"
    t.datetime "expires_at"
    t.datetime "authenticated_at"
    t.datetime "reset_password_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_id"], name: "index_masks_login_links_on_actor_id"
    t.index ["client_id"], name: "index_masks_login_links_on_client_id"
    t.index %w[code email_id device_id client_id],
            name: "idx_on_code_email_id_device_id_client_id_2f61fce223",
            unique: true
    t.index ["device_id"], name: "index_masks_login_links_on_device_id"
    t.index ["email_id"], name: "index_masks_login_links_on_email_id"
  end

  create_table "masks_otp_secrets", force: :cascade do |t|
    t.string "public_id", null: false
    t.string "name"
    t.string "secret", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "verified_at"
    t.integer "actor_id"
    t.index ["actor_id"], name: "index_masks_otp_secrets_on_actor_id"
    t.index ["public_id"],
            name: "index_masks_otp_secrets_on_public_id",
            unique: true
    t.index ["secret"], name: "index_masks_otp_secrets_on_secret", unique: true
  end

  create_table "masks_phones", force: :cascade do |t|
    t.string "number", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "verified_at"
    t.integer "actor_id"
    t.index ["actor_id"], name: "index_masks_phones_on_actor_id"
    t.index ["number"], name: "index_masks_phones_on_number", unique: true
  end

  create_table "masks_providers", force: :cascade do |t|
    t.string "key"
    t.string "name"
    t.string "type"
    t.boolean "common"
    t.text "settings"
    t.datetime "disabled_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_masks_providers_on_key", unique: true
  end

  create_table "masks_single_sign_ons", force: :cascade do |t|
    t.string "key"
    t.text "settings"
    t.integer "provider_id"
    t.integer "actor_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_id"], name: "index_masks_single_sign_ons_on_actor_id"
    t.index %w[key provider_id],
            name: "index_masks_single_sign_ons_on_key_and_provider_id",
            unique: true
    t.index ["provider_id"], name: "index_masks_single_sign_ons_on_provider_id"
  end

  create_table "masks_tokens", force: :cascade do |t|
    t.string "key"
    t.string "name"
    t.string "type"
    t.string "secret"
    t.string "nonce"
    t.string "redirect_uri"
    t.text "scopes"
    t.text "settings"
    t.integer "client_id"
    t.integer "actor_id"
    t.integer "device_id"
    t.integer "token_id"
    t.datetime "expires_at"
    t.datetime "revoked_at"
    t.datetime "refreshed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["actor_id"], name: "index_masks_tokens_on_actor_id"
    t.index ["client_id"], name: "index_masks_tokens_on_client_id"
    t.index ["device_id"], name: "index_masks_tokens_on_device_id"
    t.index ["key"], name: "index_masks_tokens_on_key", unique: true
    t.index ["secret"], name: "index_masks_tokens_on_secret", unique: true
    t.index ["token_id"], name: "index_masks_tokens_on_token_id"
  end

  add_foreign_key "active_storage_attachments",
                  "active_storage_blobs",
                  column: "blob_id"
  add_foreign_key "active_storage_variant_records",
                  "active_storage_blobs",
                  column: "blob_id"
end
