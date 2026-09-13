module ProviderDomains
  def self.join(held)
    Array(held).map { |one| one.to_s.strip.downcase.delete_prefix("@") }.reject(&:empty?).uniq.join(" ")
  end
end
