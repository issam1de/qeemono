module Qeemono
  module MessageHandler
    module Core
      #
      # All message handlers dealing with core communication.
      #
      class Communication < Qeemono::MessageHandler::Base

        def handled_methods
        end

        def name
          '__communication_handler'
        end

      end
    end
  end
end
