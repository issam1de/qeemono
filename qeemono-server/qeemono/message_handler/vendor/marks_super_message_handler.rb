module Qeemono
  module MessageHandler
    module Vendor
      #
      # This is an example third-party message handler.
      # Just for fun and testing...
      #
      class MarksSuperMessageHandler < Qeemono::MessageHandler::Base

        def name
          :'mark::super_mh'
        end

        def description
          "Mark's super message handler"
        end

        def handled_methods
          [:say_hello]
        end

        def modules
          [:__marks_module]
        end

        # **************************************************************
        # **************************************************************
        # **************************************************************

        #
        # Just for testing...
        #
        def handle_say_hello(origin_client_id, params)
          relay(
                  origin_client_id,
                  @qsif[:client_manager].web_socket(:client_id => origin_client_id),
                  {:method => :hello, :params => {:greeting => 'Hello Mark!'}}
          )
        end
      end
    end
  end
end
