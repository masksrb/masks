class Avatar < ApplicationRecord
  include TenantScoped

  STORED = 512
  LIMIT = 8.megabytes

  belongs_to :actor

  validates :actor_id, uniqueness: { scope: :tenant_id }

  def self.store!(actor:, upload:)
    refuse_size!(upload.size) if upload.respond_to?(:size)

    bytes = bytes_in(upload)

    raise Pictures::Unreadable, "an avatar has to be an image" if Pictures.sniff(bytes).nil?

    refuse_size!(bytes.bytesize)

    square = Pictures.square(bytes, STORED)
    held = find_or_initialize_by(actor_id: actor.id)

    held.update!(
      content_type: Pictures::CONTENT_TYPE,
      digest: Pictures.digest(square),
      byte_size: square.bytesize,
      data: square
    )

    held
  end

  def self.refuse_size!(size)
    return if size.nil? || size <= LIMIT

    raise Pictures::Unreadable, "an avatar has to be smaller than #{LIMIT / 1.megabyte}MB"
  end

  def self.bytes_in(upload)
    return upload.read(LIMIT + 1).to_s.b if upload.respond_to?(:read)

    upload.to_s.b
  end

  def resized(size)
    Pictures.resized(data, digest, size, stored: STORED, kind: "avatar")
  end
end
