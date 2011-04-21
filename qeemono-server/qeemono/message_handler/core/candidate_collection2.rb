module Qeemono
  module MessageHandler
    module Core
      #
      # This is another message handler defining candidate and test methods.
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
                  {:method => :echo2, :params => params}
          )
        end
      end
    end
  end
end
