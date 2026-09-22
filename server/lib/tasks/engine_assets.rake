namespace :masks do
  desc "Build the assets the masks-server gem ships into engine/public/masks-assets"
  task :engine_assets do
    public_dir = File.expand_path("../../../engine/public", __dir__)

    system(
      { "VITE_RUBY_PUBLIC_DIR" => public_dir, "VITE_RUBY_PUBLIC_OUTPUT_DIR" => "masks-assets" },
      "bin/vite", "build", "--mode", "production",
      exception: true
    )
  end
end
