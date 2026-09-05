class Passkey < ApplicationRecord
  include TenantScoped

  MAX_PER_ACTOR = 20
  SIGN_COUNT_CEILING = (2**32) - 1

  belongs_to :actor
  belongs_to :authenticator, primary_key: :aaguid, foreign_key: :aaguid, optional: true

  validates :external_id, :public_key, presence: true
  validates :external_id, uniqueness: { scope: :tenant_id }
  validates :sign_count, numericality: {
    only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: SIGN_COUNT_CEILING
  }

  scope :newest_first, -> { order(created_at: :desc) }
  scope :discoverable, -> { where(discoverable: true) }

  def self.enrol!(actor:, credential:, name:)
    create!(
      actor: actor,
      name: name.presence,
      external_id: credential.id,
      public_key: credential.public_key,
      sign_count: credential.sign_count,
      aaguid: aaguid_of(credential),
      discoverable: !!credential.response&.authenticator_data&.user_verified?,
      user_verified: !!credential.response&.authenticator_data&.user_verified?
    )
  end

  def self.aaguid_of(credential)
    credential.response&.attestation_object&.authenticator_data&.attested_credential_data&.aaguid
  rescue StandardError
    nil
  end

  def used!(sign_count, user_verified:)
    update!(
      sign_count: [ sign_count.to_i, self.sign_count ].max,
      user_verified: user_verified,
      last_used_at: Time.current
    )
  end

  def label
    name.presence || authenticator&.name.presence || "Passkey"
  end

  def icon
    authenticator&.icon
  end

  def compromised?
    authenticator&.compromised? || false
  end

  def compromise
    authenticator&.compromise
  end

  def cloned?(reported)
    reported.to_i.positive? && sign_count.positive? && reported.to_i <= sign_count
  end
end
