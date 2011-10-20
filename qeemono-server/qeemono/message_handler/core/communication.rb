#
# (c) 2011, Mark von Zeschau
#


require_relative '../../lib/exception/unknown_receiver_type_error'
require_relative '../../lib/exception/unknown_receiver_error'
require_relative '../../lib/exception/no_receiver_given_error'
require_relative '../../lib/exception/no_message_given_error'

module Qeemono
  module MessageHandler
    module Core
      #
      # This message handler deals with core communication.
      #
      class Communication < Qeemono::MessageHandler::Base

        def name
          :'qeemono::comm'
        end

        def description
          'This message handler deals with core communication.'
        end

        def handled_methods
          [:send, :create_channels, :destroy_channels, :subscribe_to_channels, :unsubscribe_from_channels]
        end

        def modules
          [:core]
        end

        # **************************************************************
        # **************************************************************
        # **************************************************************

        #
        # Sends a JSON message to one or more clients and/or one or more channels.
        # A channel consists of many subscribers (clients) who the message is
        # broadcasted to. The :broadcast channel is used to broadcast to all
        # clients of the server. The :broadcastwb channel (wb = with bounce) does
        # the same but also sends (bounces) the message to the origin client (sender).
        #
        # * origin_client_id - The originator (sender) of the message.
        # * params:
        #   - :channels => Array of channels to broadcast to (e.g. [:broadcast, :detectives]).
        #                  Can be strings or symbols.
        #   - :client_ids => Array of client ids to send to (e.g. [:client_4711, :mark]).
        #                    Can be strings or symbols.
        #   - :message => The JSON message (following the qeemono protocol) to be sent.
        #
        def handle_send(origin_client_id, params)
          channels = params[:channels]
          receiver_client_ids = params[:client_ids]
          # TODO: move raise into actual send method and send a notification instead of raising an exception
          if channels.nil? && receiver_client_ids.nil?
            raise Qeemono::NoReceiverGivenError.new("Neither parameter 'channels' nor 'client_ids' is set! At least one target (channels and/or client_ids) must be specified.")
          elsif params[:message].nil?
            raise Qeemono::NoMessageGivenError.new("Parameter 'message' (a qeemono JSON message) is missing! Must be specified.")
          else
            send_to_channels_or_clients(origin_client_id, channels, :channels, params[:message])
            send_to_channels_or_clients(origin_client_id, receiver_client_ids, :client_ids, params[:message])
          end
        end

        #
        # Creates new channels.
        #
        # * origin_client_id - The originator (sender) of the message.
        # * params:
        #   - :channels => Array of channels to create (e.g. [:my_new_channel, :foo_channel_1]).
        #                  Can be strings or symbols.
        #
        def handle_create_channels(origin_client_id, params)
          channel_symbols = params[:channels]
          options = {}
          @qsif[:channel_manager].create_channels(origin_client_id, channel_symbols, options)
        end

        #
        # Destroys channels.
        #
        # * origin_client_id - The originator (sender) of the message.
        # * params:
        #   - :channels => Array of channels to destroy (e.g. [:my_new_channel, :foo_channel_1]).
        #                  Can be strings or symbols.
        #
        def handle_destroy_channels(origin_client_id, params)
          channel_symbols = params[:channels]
          options = {}
          @qsif[:channel_manager].destroy_channels(origin_client_id, channel_symbols, options)
        end

        #
        # Subscribes the client (origin_client_id) to channels.
        #
        # * origin_client_id - The originator (sender) of the message (who has to be subscribed).
        # * params:
        #   - :channels => Array of channels to subscribe to (e.g. [:broadcast, :detectives]).
        #                  Can be strings or symbols.
        #   - :bounce => If true the message will also be sent (bounced) to the origin client (sender)
        #                provided that the client is subscribed to the resp. channel. If false (the default)
        #                the sender will not receive the message although being subscribed to the channel.
        #   - :create_lazy => If true, the channel(s) is/are automatically created if not existent yet. If
        #                     false (the default), an error notification is sent back and nothing will be done.
        #
        def handle_subscribe_to_channels(origin_client_id, params)
          channel_symbols = params[:channels]
          options = {}
          options[:bounce] = (params[:bounce] == 'true')
          options[:create_lazy] = (params[:create_lazy] == 'true')
          @qsif[:channel_manager].subscribe(origin_client_id, channel_symbols, options)
        end

        #
        # Unsubscribes the client (origin_client_id) from channels.
        #
        # * origin_client_id - The originator (sender) of the message (who has to be unsubscribed).
        # * params:
        #   - :channels => Array of channels to unsubscribe from (e.g. [:broadcast, :detectives]).
        #                  Can be strings or symbols. If :_all_ or '_all_' is passed the client is
        #                  unsubscribed from all channels it is subscribed to.
        #
        def handle_unsubscribe_from_channels(origin_client_id, params)
          channel_symbols = params[:channels]
          options = {}
          @qsif[:channel_manager].unsubscribe(origin_client_id, channel_symbols, options)
        end

        private

        #
        # receivers - Array of client ids or array of channels (depending on the receiver_type).
        #             An array of strings or symbols.
        # receiver_type - A symbol. Either :channels or :client_ids
        # message - The message to send.
        #
        def send_to_channels_or_clients(origin_client_id, receivers, receiver_type, message)
          return false if receivers.nil?
          receivers = [receivers] unless receivers.is_a? Array
          receivers.each do |receiver|
            receiver = receiver.to_sym

            if receiver_type == :channels
              receiver_type_name = 'channel'
              relay_destination = @qsif[:channel_manager].channel(:channel => receiver)
            elsif receiver_type == :client_ids
              receiver_type_name = 'client'
              relay_destination = @qsif[:client_manager].web_socket(:client_id => receiver)
            else
              raise Qeemono::UnknownReceiverTypeError.new("Unknown receiver type '#{receiver_type.to_s}'!")
            end

            if relay_destination.nil?
              raise Qeemono::UnknownReceiverError.new("Failed to send to #{receiver_type_name} '#{receiver}'. Unknown.")
            else
              relay(origin_client_id, relay_destination, message)
            end
          end
        end

      end # end - class
    end # end - module
  end # end - module
end # end - module
