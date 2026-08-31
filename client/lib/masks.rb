require_relative "masks/version"
require_relative "masks/client"

require_relative "masks/rails" if defined?(::Rails::Engine)
