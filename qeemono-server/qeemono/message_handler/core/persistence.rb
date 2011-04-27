module Qeemono
  module MessageHandler
    module Core
      #
      # This message handler defines relevant methods for persistence.
      #
      class Persistence < Qeemono::MessageHandler::Base

        def name
          :'qeemono::persist'
        end

        def description
          'persistence' # TODO: better description
        end

        def handled_methods
          [:store_data]
        end

        def modules
          [:core]
        end

        # **************************************************************
        # **************************************************************
        # **************************************************************

        #
        # Stores data for the given client id.
        #
        # * origin_client_id - The originator (sender) of the message for
        #                      whom the data is to be stored.
        # * params:
        #   - :data => Hash of data which is to be stored for the client.
        #   - :public => If true the data can be read by anyone; if false
        #                only the client (origin_client_id) can read the
        #                data. Defaults to false.
        #
        def handle_store_data(origin_client_id, params)
          data = params[:data]
          public = params[:public] || false
        end

      end
    end
  end
end
