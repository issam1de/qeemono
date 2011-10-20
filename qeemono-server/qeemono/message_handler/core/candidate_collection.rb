#
# (c) 2011, Mark von Zeschau
#


module Qeemono
  module MessageHandler
    module Core
      #
      # This message handler defines candidate and test methods.
      #
      class CandidateCollection < Qeemono::MessageHandler::Base

        def name
          :'qeemono::cand'
        end

        def description
          'This message handler defines candidate and test methods.'
        end

        def handled_methods
          [:echo, :foo]
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

        #
        # Just for testing...
        #
        def handle_foo(origin_client_id, params)
          notify :type => :info, :code => 0, :params => {:msg => 'FOO!!!'}
        end

      end # end - class
    end
  end
end
