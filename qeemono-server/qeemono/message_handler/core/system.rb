module Qeemono
  module MessageHandler
    module Core
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
