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
              [:say_hello, :'just_fail!', :this_method_does_not_exist, :i_need_long_time]
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
                      {:method => :hello, :params => {:greeting => "Hello Markimo! Your input is: \"#{input}\""}}
              )
            end

            #
            # Just for testing...
            # This method will always fail with an exception!
            #
            def handle_just_fail!(origin_client_id, params)
              raise "I am failing..... I am failing..... I am failing to the see..."
            end

            #
            # Just for testing...
            #
            def handle_i_need_long_time(origin_client_id, params)
              # Just sleep for 10 seconds.
              # The execution will be aborted by the qeemono dispatcher...
              sleep(10)
            end

          end # end - class
        end
      end
    end
  end
end
