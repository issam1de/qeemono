module Qeemono
  module MessageHandler
    module Core
      #
      # All message handlers dealing with core communication.
      #
      class Communication < Qeemono::MessageHandler::Base

        def handled_methods
          [:send]
        end

        def name
          '__communication_handler'
        end

        # **************************************************************
        # **************************************************************
        # **************************************************************

        def send_to_channels(sender_client_id, channels, payload)
          return false if channels.nil?
          channels = [channels] unless channels.is_a? Array
          channels.each do |channel|
            if @qsif[:channels][channel.to_sym].nil?
              @qsif[:notificator].notify(:type => :error, :code => 10000, :receivers => @qsif[:web_sockets][sender_client_id], :params => {:channel => channel, :payload => payload})
            else
              @qsif[:channels][channel.to_sym].push(payload) # TODO: send/relay message according to protocol
            end
          end
        end

        def send_to_receivers(sender_client_id, receiver_client_ids, payload)
          return false if receiver_client_ids.nil?
          receiver_client_ids = [receiver_client_ids] unless receiver_client_ids.is_a? Array
          receiver_client_ids.each do |client_id|
            if @qsif[:web_sockets][client_id.to_sym].nil?
              @qsif[:notificator].notify(:type => :error, :code => 10010, :receivers => @qsif[:web_sockets][sender_client_id], :params => {:client_id => client_id, :payload => payload})
            else
              @qsif[:web_sockets][client_id.to_sym].send(payload) # TODO: send/relay message according to protocol
            end
          end
        end

        #
        # Sends payload to the server, one or more clients, and/or one or more
        # channels. A channel consists of many subscribers (clients) to which
        # the message is sent. The :broadcast channel is used to send (broadcast)
        # to all clients of the server.
        #
        # * sender_client_id - The sender (originator) of the message
        # * params:
        #   * channels => array of channels (e.g. ['broadcast', 'detectives'])
        #   * payload => any object (preferably a JSON hash)
        # * version - The protocol version
        #
        def handle_send(sender_client_id, params, version)
          channels = params['channels']
          receiver_client_ids = params['receivers']
          if channels.nil? && receiver_client_ids.nil?
            @qsif[:notificator].notify(:type => :warn, :code => 10020, :receivers => @qsif[:web_sockets][sender_client_id], :params => {})
          else
            send_to_channels(sender_client_id, channels, params['payload'])
            send_to_receivers(sender_client_id, receiver_client_ids, params['payload'])
          end
        end

        def handle_subscribe_to_channels(params)
          # TODO: implement
        end

        def handle_unsubscribe_from_channels(params)
          # TODO: implement
        end

      end
    end
  end
end
