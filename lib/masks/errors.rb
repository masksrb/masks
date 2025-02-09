module Masks
  class AuthError < RuntimeError
    def code
      self
        .class
        .name
        .delete_suffix("Error")
        .split("::")
        .last
        .underscore
        .dasherize
    end
  end

  class InvalidModeError < RuntimeError
    def initialize(mode)
      if mode
        super "Invalid mode: #{mode}"
      else
        super "Specify a mode for masks: server | client"
      end
    end
  end

  class InvalidStateError < AuthError
  end

  class InvalidPromptError < AuthError
  end

  class SingleSignOnError < AuthError
  end

  class MissingStateError < AuthError
  end

  class ExpiredStateError < AuthError
  end

  class MissingClientError < AuthError
  end

  class ExpiredDeviceError < AuthError
  end

  class MismatchedClientError < AuthError
  end

  class MisconfiguredClientError < AuthError
  end

  class SettledStateError < AuthError
  end

  class LoggedOut < RuntimeError
    def initialize(entry)
      @entry = entry
    end

    def redirect_uri
      @entry.redirect_uri
    end
  end
end
