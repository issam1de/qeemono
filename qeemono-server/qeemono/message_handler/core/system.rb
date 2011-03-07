module Qeemono
  module MessageHandler
    module Core
      #
      # All system relevant message handlers.
      #
      class System < Qeemono::MessageHandler::Base

        def handled_methods
        end

        def name
          '__system_handler'
        end

        def modules
          :core
        end

        # **************************************************************
        # **************************************************************
        # **************************************************************

      end
    end
  end
end
