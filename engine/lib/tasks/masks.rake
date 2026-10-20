namespace :masks do
  desc "Ensure every tenant named by MASKS_TENANTS exists, and print the setup token of any not yet set up"
  task tenants: :environment do
    Masks::Server::MasterKey.check!

    config = Rails.configuration.masks
    announce = lambda do |outcome, lines|
      if outcome.done?
        lines.call(outcome.value).each { |line| puts "masks: #{line}" }
        puts "masks: #{outcome.name} done on #{outcome.host}"
      else
        puts "masks: #{outcome.name} already done on #{outcome.host}, skipped"
      end
    end

    declared = Masks::Server::BootTask.once("tenants", fingerprint: config.tenants.join(",")) { Masks::Server::Tenant.declare! }
    announce.call(declared, ->(tenants) { tenants.map { |tenant| "#{tenant.subdomain}: #{tenant.signing_key.kid}" } })

    Masks::Server::Tenant.active.reject(&:set_up?).each { |tenant| puts "masks: #{tenant.setup_announcement}" }

    if config.config_path.present?
      digest = File.exist?(config.config_path) ? Digest::SHA256.file(config.config_path).hexdigest : config.config_path
      applied = Masks::Server::BootTask.once("config", fingerprint: digest) { Masks::Server::Declared.apply! }
      announce.call(applied, ->(said) { said })
    end

    if config.recover.present?
      recovered = Masks::Server::BootTask.once("recover", fingerprint: config.recover) { Masks::Server::LockedOut.recover! }
      announce.call(recovered, ->(lines) { lines })
    end

    if ENV["ENCRYPTION_PREVIOUS_PRIMARY_KEY"].present?
      reencrypted = Masks::Server::BootTask.once("reencrypt", fingerprint: ENV["ENCRYPTION_PREVIOUS_PRIMARY_KEY"]) do
        Masks::Server::MasterKey.reencrypt!
        [ "every encrypted column now uses the current master key. Remove MASKS_PREVIOUS_MASTER_KEY." ]
      end
      announce.call(reencrypted, ->(lines) { lines })
    elsif Masks::Server::MasterKey.underived.exists?
      derived = Masks::Server::BootTask.once("derive", fingerprint: Masks::Server::MasterKey.underived.pluck(:id).sort.join(",")) do
        Masks::Server::MasterKey.reencrypt!(Masks::Server::MasterKey.underived)
        [ "every tenant's encrypted columns now use a key of that tenant's own." ]
      end
      announce.call(derived, ->(lines) { lines })
    end
  end
end
