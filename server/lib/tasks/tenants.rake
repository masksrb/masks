namespace :masks do
  desc "Ensure every tenant named by MASKS_TENANTS exists"
  task tenants: :environment do
    Tenant.declare!.each { |tenant| puts "#{tenant.subdomain}: #{tenant.signing_key.kid}" }
  end
end
