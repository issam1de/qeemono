module Qeemono
  module MessageHandler
    module Core
      #
      # All candidates message handlers.
      #
      class CandidateCollection < Qeemono::MessageHandler::Base

        def handled_methods
          ['1', :bar]
        end

        def name
          'CandidateCollection'
        end

      end
    end
  end
end
