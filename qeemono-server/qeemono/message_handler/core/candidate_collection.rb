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

        # ***

        def handle_bar(sif, first)
          sif[:logger].info "HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHALLO!!!!!!!!!!! #{first}"
        end
      end
    end
  end
end
