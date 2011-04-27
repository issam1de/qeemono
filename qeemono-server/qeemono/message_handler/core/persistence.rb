module Qeemono
  module MessageHandler
    module Core
      #
      # This message handler defines relevant methods for persistence.
      #
      class Persistence < Qeemono::MessageHandler::Base

        require 'mongoid'
        require_relative '../../client_data'


        def initialize(attrs = {})
          super(attrs)
          connect_to_mongodb
        end

        def name
          :'qeemono::persist'
        end

        def description
          'persistence' # TODO: better description
        end

        def handled_methods
          [:store_data, :load_data]
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
        #   - :vcontext => TODO: vcontext is not implemented yet!
        #                  The visibility context. An Array of client ids
        #                  and/or channel symbols. The data is readable by
        #                  all clients which are either listed directly in
        #                  the vcontext or are subscribed to at least one
        #                  channel which is in turn listed in the vcontext.
        #                  The vcontext is by default empty meaning that no
        #                  one except the client owning the data can read
        #                  the data.
        #
        def handle_store_data(origin_client_id, params)
          data = params[:data]
          public = params[:public] || false

          ClientData.create(owner_client_id: origin_client_id.to_sym, data: data, public: public)
        end

        def handle_load_data(origin_client_id, params)
        end

        private

        def connect_to_mongodb
          mongoid_conf = YAML::load_file('qeemono/config/mongoid.yml')
          Mongoid.configure do |config|
            config.master = Mongo::Connection.new(mongoid_conf['host'], mongoid_conf['port']).db(mongoid_conf['database'])
          end
        end

      end # end - class
    end
  end
end
