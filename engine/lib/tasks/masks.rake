namespace :masks do
  desc "Ensure every tenant named by MASKS_TENANTS exists, and print the setup token of any not yet set up"
  task tenants: :environment do
    Masks::Server::Tenant.declare!.each { |tenant| puts "#{tenant.subdomain}: #{tenant.signing_key.kid}" }

    Masks::Server::Tenant.active.reject(&:set_up?).each { |tenant| puts "masks: #{tenant.setup_announcement}" }
  end
end
