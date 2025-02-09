require_relative "../masks"
require_relative "./command"

require_relative "cli/model_command"

Dir[File.join(__dir__, "cli/*.rb")].each { |file| require file }

Masks
  .cli do
    name "masks"
    desc "Commands for interacting with masks"

    [
      Masks::LoginCommand.new,
      Masks::ConfCommand.new,
      Masks::Server::ClientCommand.new,
      Masks::Server::ActorCommand.new,
      Masks::Server::ProviderCommand.new,
    ].each { |command| cmd command }

    if Masks.mode.server?
      cmd do
        name "migrate"
        desc "Run migrations and seed data"

        run { system "bin/rails db:migrate db:seed" }
      end

      cmd do
        name "console"
        desc "Open a console with access to masks"

        run { system "bin/rails console" }
      end

      cmd do
        name "worker"
        desc "Start masks job workers"

        run do
          unless ENV["MASKS_SKIP_MIGRATIONS"]
            system "bin/rails db:migrate db:seed"
          end

          system "bin/jobs"
        end
      end

      cmd do
        name "server"
        desc "Start the masks web server (and job workers)"

        run do
          unless ENV["MASKS_SKIP_MIGRATIONS"]
            system "bin/rails db:migrate db:seed"
          end

          system "bin/rails server"
        end
      end
    end

    help do
      puts
      thor.say_status("Usage", "masks [command] [options]")
      thor.say opts
      puts
      thor.say_status("Commands", "")
      puts

      cmds = cmd.sort.map { |k, cmd| ["#{k}", cmd.desc] }

      print_table cmds, indent: 4

      puts
    end

    run { help }
  end
  .run!
