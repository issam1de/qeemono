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

        def handle_echo(sender_client_id, params, version)
          @qsif[:notificator].notify :type => :info, :code => 0, :receivers => @qsif[:web_sockets][sender_client_id], :params => {:msg => "Echo back to client '#{sender_client_id}': #{params}"}
        end

        def handle_foo(sender_client_id, params, version)
          @qsif[:notificator].notify :type => :info, :code => 0, :params => {:msg => 'FOO!!!'}
        end
      end
    end
  end
end
