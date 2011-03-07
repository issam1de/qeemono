require './qeemono/lib/exception/unknown_receiver_type_error'
require './qeemono/lib/exception/unknown_receiver_error'
require './qeemono/lib/exception/no_receiver_given_error'
require './qeemono/lib/exception/no_message_given_error'

module Qeemono
  module MessageHandler
    module Core
      #
      # All message handlers dealing with core communication.
      #
      class Communication < Qeemono::MessageHandler::Base

        def handled_methods
          [:send, :subscribe, :unsubscribe]
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
              raise Qeemono::UnknownReceiverTypeError.new("Unknown receiver type '#{receiver_type.to_s}'!")
            end

            if @qsif[receiver_type][receiver].nil?
              raise Qeemono::UnknownReceiverError.new("Failed to send to #{receiver_type_name} '#{receiver}'. Unknown.")
            else
              relay(origin_client_id, @qsif[receiver_type][receiver], message)
            end
          end
        end

        #
        # Sends a JSON message to one or more clients and/or one or more channels.
        # A channel consists of many subscribers (clients) who the message is
        # broadcasted to. The :broadcast channel is used to broadcast to all
        # clients of the server. The :broadcastwb channel (wb = with bounce) does
        # the same but also sends (bounces) the message to the origin client.
        #
        # * origin_client_id - The originator (sender) of the message
        # * params:
        #   - :channels => array of channels to broadcast to (e.g. [:broadcast, :detectives])
        #   - :client_ids => array of client ids to send to (e.g. [:client_4711, :mark])
        #   - :message => the JSON message (following the qeemono protocol) to be sent
        #
        def handle_send(origin_client_id, params)
          channels = params[:channels]
          receiver_client_ids = params[:client_ids]
          if channels.nil? && receiver_client_ids.nil?
            raise Qeemono::NoReceiverGivenError.new("Neither parameter 'channels' nor 'client_ids' is set! At least one target (channels and/or client_ids) must be specified.")
          elsif params[:message].nil?
            raise Qeemono::NoMessageGivenError.new("Parameter 'message' (a qeemono JSON message) is missing! Must be specified.")
          else
            send_to_channels_or_clients(origin_client_id, channels, :channels, params[:message])
            send_to_channels_or_clients(origin_client_id, receiver_client_ids, :web_sockets, params[:message])
          end
        end

        #
        # Subscribes the client (origin_client_id) to channels.
        #
        # * origin_client_id - The originator (sender) of the message (who has to be subscribed)
        # * params:
        #   - :channels => array of channels to subscribe to (e.g. [:broadcast, :detectives])
        #   - :bounce => If true the message will also be sent (bounce) to the sender (origin client) provided
        #                that the client is subscribed to the resp. channel. If false (the default) the sender
        #                will not receive the message although being subscribed to the channel.
        #
        def handle_subscribe(origin_client_id, params)
          channel_symbols = params[:channels]
          options = {}
          options[:bounce] = (params[:bounce] == 'true')
          @qsif[:channel_subscription_manager].subscribe(origin_client_id, channel_symbols, options)
        end

        #
        # Unsubscribes the client (origin_client_id) from channels.
        #
        # * origin_client_id - The originator (sender) of the message (who has to be unsubscribed)
        # * params:
        #   - :channels => array of channels to unsubscribe from (e.g. [:broadcast, :detectives])
        #
        def handle_unsubscribe(origin_client_id, params)
          channel_symbols = params[:channels]
          options = {}
          @qsif[:channel_subscription_manager].unsubscribe(origin_client_id, channel_symbols, options)
        end

        #TODO: add create/destroy_channels handle methods
      end
    end
  end
end
