require "bundler/setup"

APP_RAKEFILE = File.expand_path("server/Rakefile", __dir__)

load "rails/tasks/engine.rake"
load "rails/tasks/statistics.rake"
load "lib/masks/tasks/masks_tasks.rake"

Bundler::GemHelper.install_tasks(name: "masks")
