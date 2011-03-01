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

        def send_to_channels(sender_client_id, channels, message)
          return false if channels.nil?
          channels = [channels] unless channels.is_a? Array
          channels.each do |channel|
            if @qsif[:channels][channel.to_sym].nil?
              raise "Failed to send to channel! Unknown channel."
            else
              @qsif[:notificator].relay(sender_client_id, @qsif[:channels][channel.to_sym], message)
            end
          end
        end

        def send_to_receivers(sender_client_id, receiver_client_ids, message)
          return false if receiver_client_ids.nil?
          receiver_client_ids = [receiver_client_ids] unless receiver_client_ids.is_a? Array
          receiver_client_ids.each do |client_id|
            if @qsif[:web_sockets][client_id.to_sym].nil?
              raise "Failed to send to client. Unknown client id."
            else
              @qsif[:notificator].relay(sender_client_id, @qsif[:web_sockets][client_id.to_sym], message)
            end
          end
        end

        #
        # Sends message to the server, one or more clients, and/or one or more
        # channels. A channel consists of many subscribers (clients) to which
        # the message is sent. The :broadcast channel is used to send (broadcast)
        # to all clients of the server.
        #
        # * sender_client_id - The sender (originator) of the message
        # * params:
        #   * channels => array of channels (e.g. ['broadcast', 'detectives'])
        #   * message => JSON message following the qeemono protocol
        # * version - The protocol version
        #
        def handle_send(sender_client_id, params, version)
          channels = params[:channels]
          receiver_client_ids = params[:receivers]
          if channels.nil? && receiver_client_ids.nil?
            raise "Neither parameter 'channels' nor 'receivers' is set! At least one target (channels and/or receivers) must be specified."
          elsif params[:message].nil?
            raise "Parameter 'message' (a JSON message) is missing! Must be specified."
          else
            send_to_channels(sender_client_id, channels, params[:message])
            send_to_receivers(sender_client_id, receiver_client_ids, params[:message])
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
