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

        # **************************************************************
        # **************************************************************
        # **************************************************************

        def handle_bar3(params)
          @qsif[:logger].info "BAR!!! #{params}"
        end

        def handle_foo(params)
          @qsif[:logger].info "FOO!!! #{params}"
        end
      end
    end
  end
end
