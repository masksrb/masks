require "rdoc"

# RDoc 8 dropped GhostMethod and MetaMethod; sdoc's template still asks whether
# a method is one before deciding to offer its source. Nothing parsed here is
# either, so a class no method is an instance of answers it the same way RDoc 8
# would if it still had the constant.
module SDocCompat
  REMOVED = %i[GhostMethod MetaMethod].freeze

  def self.install!
    REMOVED.each do |name|
      next if RDoc.const_defined?(name)

      RDoc.const_set(name, Class.new(RDoc::AnyMethod))
    end
  end
end

SDocCompat.install!
