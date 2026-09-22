module Masks
  module Server
    VERSION = File.read(File.expand_path("../../../version.txt", __dir__)).strip.freeze
  end
end
