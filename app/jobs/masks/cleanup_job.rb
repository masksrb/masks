module Masks
  class CleanupJob < ApplicationJob
    def perform(name)
      cls = name.constantize
      cls.cleanable.find_each { |record| record.cleanup if record.cleanable? }
    end
  end
end
