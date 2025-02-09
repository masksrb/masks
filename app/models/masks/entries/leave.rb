module Masks
  module Entries
    class Leave < Authentication
      def event
        nil
      end

      def enter
        session.entry[:settlement] = nil

        dispatch(Prompt::RESET)
        dispatch(Prompt::LOGOUT) if raw_params[:logout]

        oauth_entry { prompt! }
      end
    end
  end
end
