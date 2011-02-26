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

      end
    end
  end
end
