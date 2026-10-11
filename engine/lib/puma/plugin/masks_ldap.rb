require "puma/plugin"

Puma::Plugin.create do
  def start(launcher)
    @log_writer = launcher.log_writer

    launcher.events.after_booted { listen }
    launcher.events.after_stopped { stop }
    launcher.events.before_restart { stop }
  end

  private

    def listen
      @listener = Masks::Server::Ldap::Listener.from_configuration.start
    rescue NameError
      @log_writer.log("masks ldap: the app is not loaded in this process, so LDAP is not served")
    rescue SystemCallError, OpenSSL::OpenSSLError => e
      @log_writer.log("masks ldap: not listening: #{e.message}")
    end

    def stop
      Thread.new { @listener&.stop }.join
    end
end
