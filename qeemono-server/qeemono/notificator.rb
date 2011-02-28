module Qeemono
  #
  # The notificator is responsible for logging and informing client(s)
  # about relevant system information like e.g. errors.
  #
  class Notificator

    NOTIFICATION_MESSAGES = {
      0     => "${msg}",

      1000  => "The qeemono server has been started on host ${host}:${port} at ${current_time}. Have Fun...",

      2000  => "Client '${client_id}' has been subscribed to channel ${channel_symbol} (subscriber id is ${channel_subscriber_id}).",
      2010  => "Client '${client_id}' has been subscribed to channels ${channel_symbols} (subscriber ids are ${channel_subscriber_ids}).",
      2020  => "Client '${client_id}' has been unsubscribed from channel ${channel_symbol} (subscriber id was ${channel_subscriber_id}).",
      2030  => "Client '${client_id}' has been unsubscribed from channels ${channel_symbols} (subscriber ids were ${channel_subscriber_ids}).",

      6000  => "Client '${client_id}' has been connected. (Web socket signature: ${wss})",
      6010  => "Received valid message from client '${client_id}'. Going to dispatch. (Message: ${message_hash})",
      6020  => "Client '${client_id}' has been disconnected. (Web socket signature: ${wss})",

      7000  => "Client did not send its client_id! Allocating unique anonymous client id '${new_client_id}'. (Web socket signature: ${wss})",
      7010  => "Attempt to hijack (steal) session from client '${client_id}' by using its client id! Not allowed. Instead allocating unique anonymous client id '${new_client_id}'. (Web socket signature: ${wss})",

      9000  => "${err_msg}",
      9010  => "${err_msg}",
      9020  => "Received invalid message! Must be JSON. Ignoring. (Details: ${err_msg})",

      9500  => "Did not find any message handler registered for method '${method_name}'! Ignoring. (Sent from client '${client_id}' with message ${message_hash})",
      9510  => "Method '${handle_method_name}' of message handler '${message_handler_name}' (${message_handler_class}) failed! (Sent from client '${client_id}' with message ${message_hash}) Error message: ${err_msg}",
      9520  => "Message handler '${message_handler_name}' (${message_handler_class}) is registered to handle method '${method_name}' but does not respond to '${handle_method_name}'! (Sent from client '${client_id}' with message ${message_hash})",

      10000 => "Failed to send to channel '${channel}'! Unknown channel. (Payload: ${payload})",
      10010 => "Failed to send to client '${client_id}'! Unknown client id. (Payload: ${payload})",
      10020 => "Neither parameter 'channels' nor 'receivers' is set for method send! At least one target (channels and/or receivers) must be specified"
    }


    def initialize(logger)
      @logger = logger
      check_notification_messages
    end

    #
    # Notifies the receivers (clients) about the given incident.
    # Additionally, the incident will be logged unless suppressed.
    #
    # Options:
    # * :type (symbol) - Can be one of :info, :debug, :warn, :error, :fatal (aka log level)
    # * :code (integer) - The notification message code
    # * :receivers (client ids, web sockets and/or channels) - The receivers of the notification message
    # * :params (hash) - The template variables for the notification message
    # * :no_log (boolean) - Defaults to false. If true the notification will not be logged
    # * :exception (exception) - Defaults to nil. If given the backtrace will be logged
    #
    # Example:
    #   {:type => :error, :code => 100, :receivers => @qsif[:channels][:broadcast], :params => {:client_id => client_id, :wss => ws.signature}, :no_log => true}
    #
    def notify(options)
      msg = message(options)
      if msg.nil? || msg.strip == ''
        msg = "*** NO NOTIFICATION MESSAGE FOUND OR NOTIFICATION MESSAGE IS EMPTY FOR CODE #{options[:code]} ***"
      end

      type = options[:type]

      # Send to all receivers...
      receivers = options[:receivers]
      if receivers
        receivers = [receivers] unless receivers.is_a? Array
        receivers.each do |receiver|
          # TODO: send as protocol conform JSON message with code and all params so that client can parse and understand the notification message
          # TODO: allow also client ids as receivers

          # Push to channel or send to web socket (client)...
          receiver.send("#{type} : #{msg}")
        end
      end

      unless options[:no_log]
        logger.send(type.to_sym, msg + CommonUtils.backtrace(options[:exception]))
      end
    end

    protected

    def logger
      @logger
    end

    def message(options)
      msg = NOTIFICATION_MESSAGES[options[:code]]
      return nil unless msg
      options[:params].each do |key, value|
        msg = msg.gsub("${#{key.to_s}}", value.to_s)
      end
      msg
    end

    def check_notification_messages

    end

  end
end
