require_relative 'lib/exception/mandatory_key_missing_error'
require_relative 'lib/exception/ambiguous_client_id_error'
require_relative 'lib/exception/invalid_client_id_error'
require_relative 'lib/exception/invalid_key_error'
require_relative 'lib/exception/no_message_given_error'
require_relative 'lib/exception/invalid_format_error'

module Qeemono
  #
  # The notificator is responsible for logging and informing client(s)
  # about relevant system information like e.g. errors.
  #
  class Notificator

    #
    # The default (latest) protocol version used for qeemono JSON messages
    #
    PROTOCOL_VERSION = '1.0'

    #
    # Every qeemono message send to or received from the server must
    # be a JSON message and contains the following keys:
    #
    QEEMONO_PROTOCOL_KEYS = [
      :client_id, # * The originator (some client or the server) which initially has sent the message
                  #     - Can be passed implicitly and/or explicitly
                  #     - If not passed, an anonymous client id is created and allocated
      :method,    # * The method to call (respective message handler(s) have to subscribe in the first place)
      :params,    # * The parameters to pass to the method
      :seq_id,    # * The sequencer id. Used to uniquely identify and associate responses to their related requests
                  #     - Optional. If not passed, seq_id is :none
      :version    # * The protocol version to use (if not passed the default (latest) version is assumed)
    ]

    SERVER_CLIENT_ID = :__server

    NOTIFICATION_MESSAGES = {
      0    => "${msg}",

      1000 => "*** The qeemono server has been started on host ${host}:${port} at ${current_time}. Version: ${app_version}   -   Have Fun...",

      2000 => "Client '${client_id}' has been subscribed to channel '${channel_symbol}' (subscriber id is ${channel_subscriber_id}).",
      2001 => "Client '${client_id}' has already been subscribed to channel '${channel_symbol}' (subscriber id is ${channel_subscriber_id}).",
      2020 => "Client '${client_id}' has been unsubscribed from channel '${channel_symbol}' (subscriber id was ${channel_subscriber_id}).",
      2021 => "Client '${client_id}' is not subscribed to channel '${channel_symbol}'.",
      2030 => "Client '${client_id}' cannot be subscribed to channel '${channel_symbol}'! Not existing.",
      2040 => "Client '${client_id}' has created channel '${channel_symbol}'.",
      2050 => "Client '${client_id}' has destroyed channel '${channel_symbol}'.",
      2051 => "Client '${client_id}' tried to destroy channel '${channel_symbol}'! Not possible since it is a system channel.",
      2052 => "Client '${client_id}' tried to destroy non-existing channel '${channel_symbol}'! Ignoring.",
      2053 => "Client '${client_id}' tried to create already existing channel '${channel_symbol}'! Ignoring.",

      3000 => "Client '${client_id}' has been assigned to module '${module_name}'.",
      3010 => "Client '${client_id}' has already been assigned to module '${module_name}'.",
      3020 => "Client '${client_id}' has been unassigned from module '${module_name}'.",
      3030 => "Client '${client_id}' is not assigned to module '${module_name}'.",

      3100 => "Client '${client_id}' cannot be assigned to modules! No modules given.",
      3110 => "Client '${client_id}' cannot be assigned to module! Invalid module name given. Must be a non-empty symbol.",
      3120 => "Client '${client_id}' cannot be unassigned from modules! No modules given.",
      3130 => "Client '${client_id}' cannot be unassigned from module! Invalid module name given. Must be a non-empty symbol.",

      4000 => "Client '${client_id}' successfully stored ClientData object.",

      5000 => "Message handler '${message_handler_name}' (${message_handler_class}, Version: '${version}') has been registered for methods ${handled_methods} and modules ${modules}.",
      5010 => "Total amount of registered message handlers: ${amount}", # For the register method
      5020 => "Unregistered ${amount} message handlers. (Details: ${message_handler_names})",
      5030 => "Total amount of registered message handlers: ${amount}", # For the unregister method
      5040 => "Not a message handler object '${message_handler}'! Ignoring.",

      5100 => "${clazz} is not a message handler! Must subclass '${parent_class}'.",
      5110 => "Message handler ${clazz} has an invalid name! Must be a non-empty symbol!",
      5111 => "Message handler ${clazz} has an invalid description! Must be a non-empty string!",
      5120 => "Message handler '${message_handler_name}' does not listen to any method! (Details: ${clazz})",
      5130 => "Message handler '${message_handler_name}' tries to listen to an invalid method! Method names must be non-empty symbols. (Details: ${clazz})",
      5140 => "Message handler '${message_handler_name}' (${message_handler_class}, Version: '${version}') is already registered!",
      5150 => "A message handler with name '${message_handler_name}' (${message_handler_class}) already exists for modules ${matching_modules} and version '${version}'! Names must be unique per module and version.",
      5160 => "Message handler '${message_handler_name}' must have a non-empty version string! (Details: ${clazz})",
      5170 => "Message handler '${message_handler_name}' must have a modules array! (Details: ${clazz})",
      5180 => "Message handler '${message_handler_name}' must have at least one non-empty module name! (Details: ${clazz})",
      5190 => "Message handler '${message_handler_name}' has an invalid module! Module names must be non-empty symbols! (Details: ${clazz})",
      5200 => "Filename '${filename}' does not point to a valid message handler location! Ignoring.",
      5210 => "Error in filename '${filename}'! '.rb' suffix is missing. Ignoring.",
      5220 => "Could not find message handler for filename '${filename}'! Ignoring.",

      6000 => "Client '${client_id}' has been connected. (Web socket signature: ${wss})",
      6010 => "Received valid message from client '${client_id}'. Going to dispatch. (Message: ${message_hash})",
      6020 => "Client '${client_id}' has been disconnected. (Web socket signature: ${wss})",

      7000 => "Client did not send its client_id! Allocating unique anonymous client id '${new_client_id}'. (Web socket signature: ${wss})",
      7010 => "Attempt to hijack (steal) session from client '${client_id}' by using its client id! Not allowed. Instead allocating unique anonymous client id '${new_client_id}'. (Web socket signature: ${wss})",
      7020 => "Attempt to use client id '#{SERVER_CLIENT_ID}'! Not allowed. Is reserved for the server only. Instead allocating unique anonymous client id '${new_client_id}'. (Web socket signature: ${wss})",

      9000 => "${err_msg}",
      9001 => "Error occured! (Origin was client '${client_id}') Error message: ${err_msg}",
      9002 => "Error occured! (Origin was client '${client_id}' with message ${message_hash}) Error message: ${err_msg}",

      9500 => "Did not find any message handler of version '${version}' registered for method '${method_name}'! Requesting client '${client_id}' is assigned to modules ${modules}. Addressed message handlers: ${message_handler_names}. Ignoring. (Origin was client '${client_id}' with message ${message_hash})",
      9510 => (CODE_9510="Method '${handle_method_name}' of message handler '${message_handler_name}' (${message_handler_class}, Version: '${version}') failed! (Origin was client '${client_id}' with message ${message_hash}) Error message: ${err_msg}"),
      9515 => CODE_9510,
      9520 => "Message handler '${message_handler_name}' (${message_handler_class}, Version: '${version}') is registered to handle method '${method_name}' but does not respond to '${handle_method_name}'! (Origin was client '${client_id}' with message ${message_hash})",
      9530 => "Execution of method '${handle_method_name}' of message handler '${message_handler_name}' (${message_handler_class}, Version: '${version}') has been aborted because the time limit of ${thread_timeout} seconds has been reached. (Origin was client '${client_id}' with message ${message_hash})"
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
    #   {:type => :error, :code => 100, :receivers => @qsif[:channel_manager].channel(:channel => :broadcast), :params => {:client_id => client_id, :wss => ws.signature}, :no_log => true}
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
    # origin_client_id is the client id of the sender of the qeemono JSON message (message).
    #
    # In this method the message is actually sent to the receiver. The receiver can be
    # a web socket (aka client) or a channel. If sent to a channel the actual sending
    # to the destination clients is done in the Ruby block passed to the EM::Channel#subscribe
    # method which is called in Qeemono::ChannelManager#subscribe.
    #
    def relay(origin_client_id, receiver, message)
      relay_internal(origin_client_id, receiver, message, false)
    end

    #
    # Returns true if all mandatory keys are existent in the qeemono JSON message
    # (message) and no error during parsing occurred; otherwise false is returned.
    #
    # Additionally, optional keys like the originator (sender) client id (:client_id),
    # the protocol version (:version), and the sequencer id (:seq_id) are added to
    # the qeemono JSON message if not existent.
    #
    # If some error occurs an exception is raised.
    # If no error occurs the given block is executed.
    #
    def parse_message(origin_client_id, message, &block)
      parse_message_internal(origin_client_id, message, false, &block)
    end

    protected

    #
    # See relay method
    #
    def relay_internal(origin_client_id, receiver, message, send_from_server=false)
      parse_message_internal(origin_client_id, message, send_from_server) do |message_hash|
        # The receiver is either a web socket object (EventMachine::WebSocket::Connection)
        # or a channel object (EM::Channel)...
        message_hash.merge!(:seq_id => Qeemono::Util::SeqIdPool.load)
        receiver.relay(message_hash)
      end
    end

    #
    # See parse_message method
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
        raise Qeemono::NoMessageGivenError.new("Message is nil! Ignoring.")
      end

      if message_hash[:client_id] != nil
        message_hash[:client_id] = message_hash[:client_id].to_sym
      end

      if !send_from_server && message_hash[:client_id] == SERVER_CLIENT_ID
        raise Qeemono::InvalidClientIdError.new("The client id '#{SERVER_CLIENT_ID}' is reserved for the server only! Ignoring.")
      end

      explicit_client_id = message_hash[:client_id]
      if explicit_client_id && explicit_client_id.to_sym != origin_client_id
        raise Qeemono::AmbiguousClientIdError.new("Ambiguous client id! Client id is given both, implicitly and explicitly, but not identical. Ignoring. ('#{origin_client_id}' vs. '#{explicit_client_id }')")
      else
        message_hash[:client_id] = origin_client_id.to_sym
      end

      # If no protocol version is given, the latest/current version is assumed and added...
      message_hash[:version] ||= PROTOCOL_VERSION

      # If no seq_id is given, it is set to :none...
      message_hash[:seq_id] ||= Qeemono::Util::SeqIdPool::EMPTY_SEQ_ID

      if message_hash[:seq_id] != Qeemono::Util::SeqIdPool::EMPTY_SEQ_ID && !message_hash[:seq_id].is_a?(Integer)
        raise Qeemono::InvalidFormatError.new("The sequencer id (:seq_id) must be of type Integer or :none! Ignoring.")
      end

      # Check for all mandatory keys...
      QEEMONO_PROTOCOL_KEYS.each do |key|
        self.class.check_message_for_mandatory_key(key, message_hash)
      end

      keys = message_hash.keys - QEEMONO_PROTOCOL_KEYS
      if keys.size > 0
        raise Qeemono::InvalidKeyError.new("JSON message contains not allowed keys ${keys}! Ignoring.")
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
