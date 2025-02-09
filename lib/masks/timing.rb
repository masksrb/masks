module Masks
  NEVER_EXPIRE = "never"

  class Timing
    def duration(value)
      case value
      when String
        ChronicDuration.parse(value) if value.present?
      else
        nil
      end
    end

    def expires_at(value, after: nil)
      duration = self.duration(value)
      (after || Time.current) + duration if duration
    end

    def expired?(value)
      time =
        case value
        when NEVER_EXPIRE
          return false
        when String
          Time.parse(value)
        else
          value
        end

      time < Time.now.utc
    rescue RangeError, TypeError, NoMethodError, ArgumentError
      true
    end

    def min_time(delay)
      return yield unless delay && delay > 0

      starting = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = yield
      ending = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      taken = (ending - starting).to_f * 1000
      min_ms = ([delay - taken, 0].max)
      sleep min_ms / 1000 if min_ms.nonzero?
      result
    end
  end
end
