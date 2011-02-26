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

        #
        # Send payload to one or more channels. A channel consists of
        # many subscribers (clients) to which the message is sent. The
        # 'broadcast' channel is used to send/broadcast to all clients.
        #
        # Params:
        #
        # * channels => array of channels (e.g. ['broadcasts', 'detectives'])
        # * payload => any object
        #
        def handle_send(sif, params)
          channels = params['channels']
          if channels.nil?
            raise "Parameter 'channels' is nil!"
          else
            channels = [channels] unless channels.is_a? Array
            channels.each do |channel|
              sif[:channels][channel.to_sym].push(params['payload'].to_json)
            end
          end
        end

        def handle_subscribe_to_channels(sif, params)
          # TODO: implement
        end

        def handle_unsubscribe_from_channels(sif, params)
          # TODO: implement
        end

      end
    end
  end
end
