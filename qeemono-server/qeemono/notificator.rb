require './qeemono/utils/exceptions/mandatory_key_missing_error'

module Qeemono
  #
  # The notificator is responsible for logging and informing client(s)
  # about relevant system information like e.g. errors.
  #
  class Notificator

    #
    # The default (latest) protocol version used by the qeemono server
    #
    PROTOCOL_VERSION = '1.0'

    #
    # Every message send to or from the server must be a JSON message
    # containing the following keys:
    #
    MANDATORY_KEYS = [
      :client_id, # The originator (some client or the server) which initially has sent the message
                   #   - Can be given implicitly and/or explicitly
                   #   - If not given, an anonymous client id is creates and allocated
      :method,    # The method to call (respective message handler(s) have to subscribe in the first place)
      :params,    # The parameters to pass to the method
      :version    # The protocol version to use (if not given the default (latest) version is assumed)
    ]

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
      9020  => "Received invalid message! Must be JSON. Ignoring. (Details: ${err_msg})",

      9500  => "Did not find any message handler registered for method '${method_name}'! Ignoring. (Sent from client '${client_id}' with message ${message_hash})",
      9510  => "Method '${handle_method_name}' of message handler '${message_handler_name}' (${message_handler_class}) failed! (Sent from client '${client_id}' with message ${message_hash}) Error message: ${err_msg}",
      9520  => "Message handler '${message_handler_name}' (${message_handler_class}) is registered to handle method '${method_name}' but does not respond to '${handle_method_name}'! (Sent from client '${client_id}' with message ${message_hash})",

      9600  => "Message is nil! Ignoring. (Sent from client '${client_id}')",
      9610  => "Ambiguous client id! Client id is given both, implicitly and explicitly, but not identical. Ignoring. ('${sender_client_id}' vs. '${explicit_client_id }')",
      9620  => "Key '${key}' is missing in the JSON message! Ignoring. (Sent from client '${sender_client_id}' with message ${message_hash})"
    }


    def initialize(server_interface)
      @qsif = server_interface
      @qsif[:notificator] = self
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
          # TODO: allow also client ids as receivers

          # Push to channel or send to web socket (client)...
          relay(:'__server', receiver, {
                  :client_id => :'__server',
                  :method => :notify,
                  :params => {
                          # Send all arguments in order that clients can analyse and interpret the message
                          :arguments => options.reject { |key, value| [:receivers, :exception, :no_log].include?(key) },
                          :msg => "#{type} : #{msg}"
                  },
                  :version => PROTOCOL_VERSION
          })
        end
      end

      unless options[:no_log]
        logger.send(type.to_sym, "#{options[:code]} : #{msg}" + CommonUtils.backtrace(options[:exception]))
      end
    end

    #
    # Relays (send or broadcast) the JSON message hash to
    # the receiver client or channel.
    #
    def relay(origin, receiver, message)
      @qsif[:notificator].parse_message(origin, message) do |message_hash|
        #
        # ***** Here the message is actually sent! *****
        #
        receiver.send(message_hash)
      end
    end

    #
    # Returns [:ok, <message_hash>] containing :ok as the first and the message hash
    # as the second element if all mandatory keys are existent in the JSON message
    # (message); otherwise an array [:error, <err_msg>] containing :error as the
    # first and the resp. error message as the second element is returned.
    #
    # Additionally, optional keys like the originator client id (:client_id) and the
    # protocol version (:version) are added to the JSON message if not existent.
    #
    def parse_message(sender_client_id, message)
      begin

        web_socket = @qsif[:web_sockets][sender_client_id.to_sym]

        if message.is_a? Hash
          message_hash = message
        else
          message_hash = JSON.parse(message, :symbolize_names => true)
        end

        if message_hash.nil?
          notify(:type => :error, :code => 9600, :receivers => web_socket, :params => {:client_id => sender_client_id})
          return false
        end

        explicit_client_id = message_hash[:client_id]
        if explicit_client_id && explicit_client_id.to_sym != sender_client_id
          notify(:type => :error, :code => 9610, :receivers => web_socket, :params => {:sender_client_id => sender_client_id, :explicit_client_id  => explicit_client_id})
          return false
        else
          message_hash[:client_id] = sender_client_id
        end

        # If no protocol version is given, the latest/current version is assumed and added...
        message_hash[:version] = PROTOCOL_VERSION

        begin
          # Check for all mandatory keys...
          MANDATORY_KEYS.each do |key|
            self.class.check_message_for_mandatory_key(key, message_hash)
          end
        rescue MandatoryKeyMissingError => e
          notify(:type => :error, :code => 9620, :receivers => web_socket, :params => {:key => e.to_s, :sender_client_id => sender_client_id, :message_hash => message_hash})
          return false
        end

        yield message_hash
      rescue JSON::ParserError => e
        notify(:type => :error, :code => 9020, :receivers => web_socket, :params => {:err_msg => e.to_s})
        return false
      rescue e
        notify(:type => :fatal, :code => 9000, :receivers => web_socket, :params => {:err_msg => e.to_s}, :exception => e)
        return false
      end

      return true
    end

    #
    # Returns true if the given key is existent in the JSON message;
    # raises an exception otherwise.
    #
    def self.check_message_for_mandatory_key(key, message_hash)
      if message_hash[key.to_sym].nil?
        raise MandatoryKeyMissingError.new(key.to_s)
      end
      return true
    end

    protected

    def logger
      @qsif[:logger]
    end

    def message(options)
      msg = NOTIFICATION_MESSAGES[options[:code]]
      return nil unless msg
      options[:params].each do |key, value|
        msg = msg.gsub("${#{key.to_s}}", value.to_s)
      end
      msg
    end

  end
end
