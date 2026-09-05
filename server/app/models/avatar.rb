class Avatar < ApplicationRecord
  include TenantScoped

  class Unreadable < StandardError; end

  CONTENT_TYPE = "image/webp".freeze
  STORED = 512
  QUALITY = 82
  LIMIT = 8.megabytes
  PIXELS = 100_000_000

  MAGIC = {
    "\x89PNG\r\n\x1a\n".b => "image/png",
    "\xFF\xD8\xFF".b => "image/jpeg",
    "GIF87a".b => "image/gif",
    "GIF89a".b => "image/gif"
  }.freeze

  RIFF = "RIFF".b
  WEBP = "WEBP".b

  belongs_to :actor

  validates :actor_id, uniqueness: { scope: :tenant_id }

  def self.store!(actor:, upload:)
    refuse_size!(upload.size) if upload.respond_to?(:size)

    bytes = bytes_in(upload)

    raise Unreadable, "an avatar has to be an image" if sniff(bytes).nil?

    refuse_size!(bytes.bytesize)

    square = square(bytes)
    held = find_or_initialize_by(actor_id: actor.id)

    held.update!(
      content_type: CONTENT_TYPE,
      digest: self.digest(square),
      byte_size: square.bytesize,
      data: square
    )

    held
  end

  def self.digest(bytes)
    Digest::SHA256.hexdigest(bytes)[0, 16]
  end

  def self.sniff(bytes)
    head = bytes.to_s.b

    return "image/webp" if head.start_with?(RIFF) && head[8, 4] == WEBP

    MAGIC.find { |magic, _| head.start_with?(magic) }&.last
  end

  def self.refuse_size!(size)
    return if size.nil? || size <= LIMIT

    raise Unreadable, "an avatar has to be smaller than #{LIMIT / 1.megabyte}MB"
  end

  def self.bytes_in(upload)
    return upload.read(LIMIT + 1).to_s.b if upload.respond_to?(:read)

    upload.to_s.b
  end

  def self.images
    require "vips"

    Vips::Image
  end

  def self.square(bytes)
    refuse_a_bomb(bytes)

    images.thumbnail_buffer(
      bytes, STORED, height: STORED, size: :both, crop: :attention
    ).webpsave_buffer(Q: QUALITY, strip: true)
  rescue Vips::Error => e
    raise Unreadable, e.message
  end

  def self.refuse_a_bomb(bytes)
    header = images.new_from_buffer(bytes, "", access: :sequential)

    return if header.width.to_i * header.height.to_i <= PIXELS

    raise Unreadable, "that image has too many pixels to resize"
  rescue Vips::Error => e
    raise Unreadable, e.message
  end

  def resized(size)
    return data if size.nil? || size >= STORED

    Rails.cache.fetch([ "avatar", digest, size ], expires_in: 1.day) do
      self.class.images.thumbnail_buffer(
        data, size, height: size, size: :both, crop: :attention
      ).webpsave_buffer(Q: QUALITY, strip: true)
    end
  end
end
