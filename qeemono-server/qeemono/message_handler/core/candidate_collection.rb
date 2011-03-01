module Qeemono
  module MessageHandler
    module Core
      #
      # All candidates message handlers.
      #
      class CandidateCollection < Qeemono::MessageHandler::Base

        def handled_methods
          [:echo, :foo]
        end

        def name
          '__candidate_collection_handler'
        end

        # **************************************************************
        # **************************************************************
        # **************************************************************

        #
        # Just for testing...
        #
        def handle_echo(origin_client_id, params)
          @qsif[:notificator].notify :type => :info, :code => 0, :receivers => @qsif[:web_sockets][origin_client_id], :params => {:msg => "Echo back to client '#{origin_client_id}': #{params}"}
        end

        #
        # Just for testing...
        #
        def handle_foo(origin_client_id, params)
          @qsif[:notificator].notify :type => :info, :code => 0, :params => {:msg => 'FOO!!!'}
        end
      end
    end
  end
end
