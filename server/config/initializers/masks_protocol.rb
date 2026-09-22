module Masks
  PROTOCOL_VERSION = 1

  def self.to_bool(val, default: false)
    return default if val.nil?

    ActiveModel::Type::Boolean.new.cast(val)
  end
end
