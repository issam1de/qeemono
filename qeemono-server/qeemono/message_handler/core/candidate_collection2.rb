module Qeemono
  module MessageHandler
    module Core
      #
      # All candidates message handlers.
      #
      class CandidateCollection2 < Qeemono::MessageHandler::Base

        def name
          :'qeemono::cand2'
        end

        def description
          'candidate collection 2' # TODO: better description
        end

        def handled_methods
          [:echo]
        end

        def modules
          [:__candidate_collection, :test]
        end

        # **************************************************************
        # **************************************************************
        # **************************************************************

        #
        # Just for testing...
        #
        def handle_echo(origin_client_id, params)
          relay(
                  origin_client_id,
                  @qsif[:client_manager].web_socket(:client_id => origin_client_id),
                  {:method => :echo, :params => params}
          )
        end
      end
    end
  end
end
