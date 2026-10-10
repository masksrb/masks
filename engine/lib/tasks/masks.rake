namespace :masks do
  desc "Ensure every tenant named by MASKS_TENANTS exists, and print the setup token of any not yet set up"
  task tenants: :environment do
    Masks::Server::MasterKey.check!

    Masks::Server::Tenant.declare!.each { |tenant| puts "#{tenant.subdomain}: #{tenant.signing_key.kid}" }

    Masks::Server::Tenant.active.reject(&:set_up?).each { |tenant| puts "masks: #{tenant.setup_announcement}" }

    Masks::Server::LockedOut.recover!.each { |recovered| puts "masks: #{recovered}" }

    if ENV["ENCRYPTION_PREVIOUS_PRIMARY_KEY"].present?
      Masks::Server::MasterKey.reencrypt!
      puts "masks: every encrypted column now uses the current master key. Remove MASKS_PREVIOUS_MASTER_KEY."
    end
  end
end
