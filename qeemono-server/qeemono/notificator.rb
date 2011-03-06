require './qeemono/lib/exception/mandatory_key_missing_error'

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
      :client_id, # * The originator (some client or the server) which initially has sent the message
                  #     - Can be passed implicitly and/or explicitly
                  #     - If not passed, an anonymous client id is creates and allocated
      :method,    # * The method to call (respective message handler(s) have to subscribe in the first place)
      :params,    # * The parameters to pass to the method
      :version    # * The protocol version to use (if not given the default (latest) version is assumed)
    ]

    SERVER_CLIENT_ID = :__server

    NOTIFICATION_MESSAGES = {
      0    => "${msg}",

      1000 => "*** The qeemono server has been started on host ${host}:${port} at ${current_time}. Version: ${app_version}   -   Have Fun...",

      2000 => "Client '${client_id}' has been subscribed to channel ${channel_symbol} (subscriber id is ${channel_subscriber_id}).",
      2010 => "Client '${client_id}' has been subscribed to channels ${channel_symbols} (subscriber ids are ${channel_subscriber_ids}).",
      2020 => "Client '${client_id}' has been unsubscribed from channel ${channel_symbol} (subscriber id was ${channel_subscriber_id}).",
      2030 => "Client '${client_id}' has been unsubscribed from channels ${channel_symbols} (subscriber ids were ${channel_subscriber_ids}).",

      5000 => "Message handler '${message_handler_name}' has been registered for methods ${handled_methods}.",
      5010 => "Total amount of registered message handlers: ${amount}",
      5020 => "Unregistered ${amount} message handlers. (Details: ${message_handler_names})",
      5030 => "Total amount of registered message handlers: ${amount}",
      5100 => "${clazz} is not a message handler! Must subclass '${parent_class}'.",
      5110 => "Message handler ${clazz} must have a non-empty name!",
      5120 => "Message handler '${message_handler_name}' does not listen to any method! (Details: ${clazz})",
      5130 => "Message handler '${message_handler_name}' tries to listen to invalid method! Methods must be strings or symbols. (Details: ${clazz})",
      5140 => "Message handler '${message_handler_name}' is already registered! (Details: ${clazz})",
      5150 => "A message handler with name '${message_handler_name}' already exists! Names must be unique. (Details: ${clazz})",
      5160 => "Message handler '${message_handler_name}' must have a non-empty version! (Details: ${clazz})",

      6000 => "Client '${client_id}' has been connected. (Web socket signature: ${wss})",
      6010 => "Received valid message from client '${client_id}'. Going to dispatch. (Message: ${message_hash})",
      6020 => "Client '${client_id}' has been disconnected. (Web socket signature: ${wss})",

      7000 => "Client did not send its client_id! Allocating unique anonymous client id '${new_client_id}'. (Web socket signature: ${wss})",
      7010 => "Attempt to hijack (steal) session from client '${client_id}' by using its client id! Not allowed. Instead allocating unique anonymous client id '${new_client_id}'. (Web socket signature: ${wss})",
      7020 => "Attempt to use client id '#{SERVER_CLIENT_ID}'! Not allowed. Is reserved for the server only. Instead allocating unique anonymous client id '${new_client_id}'. (Web socket signature: ${wss})",

      9000 => "${err_msg}",
      9001 => "Error occured! (Sent from client '${client_id}') Error message: ${err_msg}",
      9002 => "Error occured! (Sent from client '${client_id}' with message ${message_hash}) Error message: ${err_msg}",

      9500 => "Did not find any message handler registered for method '${method_name}'! Ignoring. (Sent from client '${client_id}' with message ${message_hash})",
      9510 => "Method '${handle_method_name}' of message handler '${message_handler_name}' (${message_handler_class}) failed! (Sent from client '${client_id}' with message ${message_hash}) Error message: ${err_msg}",
      9520 => "Message handler '${message_handler_name}' (${message_handler_class}) is registered to handle method '${method_name}' but does not respond to '${handle_method_name}'! (Sent from client '${client_id}' with message ${message_hash})",
    }


    def initialize(server_interface)
      @qsif = server_interface
      @qsif[:notificator] = self
    end

    #
    # Notifies the receivers (clients) either directly or via channels about the given incident.
    # Additionally, the incident will be logged unless suppressed.
    #
    # Options:
    # * :type (symbol) - Can be one of :info, :debug, :warn, :error, :fatal (aka log level)
    # * :code (integer) - The notification message code
    # * :receivers (web sockets (associated with the resp. client) and/or channels) - The receivers of the notification message
    # * :params (hash) - The template variables for the notification message
    # * :no_log (boolean) - Defaults to false. If true the notification will not be logged
    # * :exception (exception) - Defaults to nil; otherwise the backtrace of the passed exception will be logged
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

      # Notify to all receivers...
      receivers = options[:receivers]
      if receivers
        receivers = [receivers] unless receivers.is_a? Array
        receivers.each do |receiver|
          relay_internal(SERVER_CLIENT_ID, receiver, {
                  :client_id => SERVER_CLIENT_ID,
                  :method => :notify,
                  :params => {
                          # Pass all arguments in order that clients can analyse and interpret the message
                          :arguments => options.reject { |key, value| [:receivers, :exception, :no_log].include?(key) },
                          :msg => "#{type} : #{msg}"
                  },
                  :version => PROTOCOL_VERSION
          }, true)
        end
      end

      unless options[:no_log]
        logger.send(type.to_sym, "#{options[:code]} : #{msg}" + Qeemono::Util::CommonUtils.backtrace(options[:exception]))
      end
    end

    #
    # Relays (send or broadcast) the JSON message hash to the receiver (web socket or channel).
    # origin_client_id is the client id of the sender of the message.
    #
    # In this method the message is actually sent to the receiver. The receiver can be
    # a web socket (aka client) or a channel. If sent to a channel the actual sending
    # to the destination clients is done in the Ruby block passed to the EM::Channel#subscribe
    # method which is called in Qeemono::ChannelSubscriptionManager#subscribe.
    #
    def relay(origin_client_id, receiver, message)
      relay_internal(origin_client_id, receiver, message, false)
    end

    #
    # Returns true if all mandatory keys are existent in the JSON message
    # (message) and no error during parsing occurred; otherwise false is returned.
    #
    # Additionally, optional keys like the originator (sender) client id (:client_id)
    # and the protocol version (:version) are added to the JSON message if not existent.
    #
    # If some error occurs an exception is raised.
    # If no error occurs the given block is executed.
    #
    def parse_message(origin_client_id, message, &block)
      parse_message_internal(origin_client_id, message, false, &block)
    end

    protected

    #
    # See relay
    #
    def relay_internal(origin_client_id, receiver, message, send_from_server=false)
      parse_message_internal(origin_client_id, message, send_from_server) do |message_hash|
        receiver.send(message_hash)
      end
    end

    #
    # See parse_message
    #
    def parse_message_internal(origin_client_id, message, send_from_server=false)
      if message.is_a? Hash
        message_hash = message
      else
        begin
          message_hash = JSON.parse(message, :symbolize_names => true)
        rescue JSON::ParserError => e
          raise JSON::ParserError.new("Received invalid message! Must be JSON. Ignoring. (Details: #{e.to_s})")
        end
      end

      if message_hash.nil?
        raise "Message is nil! Ignoring."
      end

      if message_hash[:client_id] != nil
        message_hash[:client_id] = message_hash[:client_id].to_sym
      end

      if !send_from_server && message_hash[:client_id] == SERVER_CLIENT_ID
        raise "The client id '#{SERVER_CLIENT_ID}' is reserved for the server only! Ignoring."
      end

      explicit_client_id = message_hash[:client_id]
      if explicit_client_id && explicit_client_id.to_sym != origin_client_id
        raise "Ambiguous client id! Client id is given both, implicitly and explicitly, but not identical. Ignoring. ('#{origin_client_id}' vs. '#{explicit_client_id }')"
      else
        message_hash[:client_id] = origin_client_id.to_sym
      end

      # If no protocol version is given, the latest/current version is assumed and added...
      message_hash[:version] ||= PROTOCOL_VERSION

      # Check for all mandatory keys...
      MANDATORY_KEYS.each do |key|
        self.class.check_message_for_mandatory_key(key, message_hash)
      end

      keys = message_hash.keys - MANDATORY_KEYS
      if keys.size > 0
        raise "JSON message contains not allowed keys ${keys}! Ignoring."
      end

      yield message_hash

      return true
    end

    #
    # Returns true if the given key is existent in the JSON message;
    # raises an exception otherwise.
    #
    def self.check_message_for_mandatory_key(key, message_hash)
      if message_hash[key.to_sym].nil?
        raise Qeemono::MandatoryKeyMissingError.new("Key :#{key} is missing in the JSON message!")
      end
      return true
    end

    def message(options)
      msg = NOTIFICATION_MESSAGES[options[:code]]
      return nil unless msg
      options[:params].each do |key, value|
        msg = msg.gsub("${#{key.to_s}}", value.to_s)
      end
      msg
    end

    private

    def logger
      @qsif[:logger]
    end

  end
end
