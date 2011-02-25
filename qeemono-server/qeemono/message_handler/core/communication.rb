module Qeemono
  module MessageHandler
    module Core
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
