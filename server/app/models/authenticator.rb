class Authenticator < ApplicationRecord
  MDS = "mds".freeze
  BUNDLED = "bundled".freeze

  COMPROMISED = %w[
    ATTESTATION_KEY_COMPROMISE
    USER_VERIFICATION_BYPASS
    USER_KEY_REMOTE_COMPROMISE
    USER_KEY_PHYSICAL_COMPROMISE
    REVOKED
  ].freeze

  CERTIFIED = %w[
    FIDO_CERTIFIED FIDO_CERTIFIED_L1 FIDO_CERTIFIED_L1plus
    FIDO_CERTIFIED_L2 FIDO_CERTIFIED_L2plus
    FIDO_CERTIFIED_L3 FIDO_CERTIFIED_L3plus
  ].freeze

  validates :aaguid, :name, :source, presence: true
  validates :aaguid, uniqueness: true

  scope :compromised, -> { where.not(compromised_at: nil) }

  def self.describing(aaguid)
    return nil if aaguid.blank?

    find_by(aaguid: aaguid)
  end

  def self.compromise_in(statuses)
    Array(statuses).find { |status| COMPROMISED.include?(status.to_s) }
  end

  def self.certification_in(statuses)
    Array(statuses).reverse.find { |status| CERTIFIED.include?(status.to_s) }
  end

  def compromised?
    compromised_at.present?
  end

  def certified?
    certification.present?
  end

  def compromise
    self.class.compromise_in(statuses)
  end

  def authoritative?
    source == MDS
  end
end
