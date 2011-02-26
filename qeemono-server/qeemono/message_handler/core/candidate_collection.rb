module Qeemono
  module MessageHandler
    module Core
      #
      # All candidates message handlers.
      #
      class CandidateCollection < Qeemono::MessageHandler::Base

        def handled_methods
          [:foo, :bar]
        end

        def name
          '__candidate_collection_handler'
        end

        # ***

        def handle_bar(params)
          @qsif[:logger].info "HHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHHALLO!!!!!!!!!!! #{params}"
        end
      end
    end
  end
end
