module Paged
  extend ActiveSupport::Concern

  included do
    scope :newest_first, -> { order(created_at: :desc, id: :desc) }
    scope :after, ->(id) {
      held = klass.where(id: id).pick(:created_at, :id)

      next none if held.nil?

      where("(#{klass.quoted_table_name}.created_at, #{klass.quoted_table_name}.id) < (?, ?)", *held)
    }
  end
end
