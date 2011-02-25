module Qeemono
  module MessageHandler
    module Core
      #
      # All message handlers dealing with core communication.
      #
      class Communication < Qeemono::MessageHandler::Base

        def handled_methods
          'bauer'
        end

        def name
          'dummy2'
        end

      end
    end
  end
end
