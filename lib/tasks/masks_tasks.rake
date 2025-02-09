namespace :masks do
  desc "Install masks—migrations, routes, and more..."
  task :install do
    Rails::Command.invoke :generate, ["masks:install"]
  end
end
