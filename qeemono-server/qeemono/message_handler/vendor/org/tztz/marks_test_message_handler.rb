module Qeemono
  module MessageHandler
    module Vendor
      module Org
        module Tztz
          #
          # This is an example third-party message handler.
          # Just for fun and testing...
          #
          class MarksTestMessageHandler < Qeemono::MessageHandler::Base

            def name
              :'mark::test_mh'
            end

            def description
              "Mark's test message handler"
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
              input = params[:input] || ''
              relay(
                      origin_client_id,
                      @qsif[:client_manager].web_socket(:client_id => origin_client_id),
                      {:method => :hello, :params => {:greeting => "Hello Mark! Your input is: \"#{input}\""}}
              )
            end
          end
        end
      end
    end
  end
end
