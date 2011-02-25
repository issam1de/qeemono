module Qeemono
  module MessageHandler
    module Core
      #
      # All system relevant message handlers.
      #
      class System < Qeemono::MessageHandler::Base

        def handled_methods
          ['1', :bar]
        end

        def name
          'dummy'
        end

      end
    end
  end
end
