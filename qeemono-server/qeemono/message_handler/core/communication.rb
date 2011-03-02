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

        #
        # receiver_type = :channels or :web_sockets
        #
        def send_to_channels_or_clients(origin_client_id, receivers, receiver_type, message)
          return false if receivers.nil?
          receivers = [receivers] unless receivers.is_a? Array
          receivers.each do |receiver|
            receiver = receiver.to_sym

            if receiver_type == :channels
              receiver_type_name = 'channel'
            elsif receiver_type == :web_sockets
              receiver_type_name = 'client'
            else
              raise "Unknown receiver type '#{receiver_type.to_s}'!"
            end

            if @qsif[receiver_type][receiver].nil?
              raise "Failed to send to #{receiver_type_name} '#{receiver}'. Unknown."
            else
              @qsif[:notificator].relay(origin_client_id, @qsif[receiver_type][receiver], message)
            end
          end
        end

        #
        # Sends a JSON message to one or more clients and/or one or more channels.
        # A channel consists of many subscribers (clients) who the message is
        # broadcasted to. The :broadcast channel is used to broadcast to all
        # clients of the server.
        #
        # * origin_client_id - The originator (sender) of the message
        # * params:
        #   - :channels => array of channels (e.g. [:broadcast, :detectives])
        #   - :client_ids => array of client ids (e.g. [:client_4711, :mark])
        #   - :message => the JSON message (following the qeemono protocol) to be sent
        #   - :include_me => Note: has an effect only when broadcasting to channels!
        #             If true the message will also be sent (bounce) to the sender (origin client) provided
        #             that the client is subscribed to the resp. channel. If false (the default) the sender
        #             will not receive the message although being subscribed to the channel.
        #
        def handle_send(origin_client_id, params)
          channels = params[:channels]
          receiver_client_ids = params[:client_ids]
          # TODO: has to be implemented
          include_me = params[:include_me]
          if channels.nil? && receiver_client_ids.nil?
            raise "Neither parameter 'channels' nor 'client_ids' is set! At least one target (channels and/or client_ids) must be specified."
          elsif params[:message].nil?
            raise "Parameter 'message' (a qeemono JSON message) is missing! Must be specified."
          else
            send_to_channels_or_clients(origin_client_id, channels, :channels, params[:message])
            send_to_channels_or_clients(origin_client_id, receiver_client_ids, :web_sockets, params[:message])
          end
        end

        def handle_subscribe_to_channels(origin_client_id, params)
          # TODO: implement
        end

        def handle_unsubscribe_from_channels(origin_client_id, params)
          # TODO: implement
        end

      end
    end
  end
end
