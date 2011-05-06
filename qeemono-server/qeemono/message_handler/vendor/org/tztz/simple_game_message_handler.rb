module Qeemono
  module MessageHandler
    module Vendor
      module Org
        module Tztz
          class SimpleGameMessageHandler < Qeemono::MessageHandler::Base

            def name
              :'mark::simple_game'
            end

            def description
              "This is the message handler for the really simple game called 'simple game' enabling each player to store her position and show it to all other players."
            end

            def handled_methods
              [:store_location]
            end

            def modules
              [:__marks_module]
            end

            # **************************************************************
            # **************************************************************
            # **************************************************************

            def handle_store_location(origin_client_id, params)

            end

          end # end - class
        end
      end
    end
  end
end
