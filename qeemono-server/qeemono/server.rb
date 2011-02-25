#
# This is the qeemono server.
# A lightwight, Web Socket based server.
#
#   - by Mark von Zeschau, Qeevee
#
# (c) 2011
#
# Needed Ruby Gems:
#   - em-websocket (https://github.com/igrigorik/em-websocket)
#   - json
#   - log4r
#
# External documentation:
#   - Web Sockets (http://www.w3.org/TR/websockets/)
#   - EventMachine
#


require 'em-websocket'
require 'json'
require 'log4r'
require './qeemono/message_handler/base'


module Qeemono
  class Server

    include Log4r
    include Qeemono::MessageHandler

    PROTOCOL_VERSION = '1.0'
    MANDATORY_KEYS = [:method, :params, :version]

    attr_reader :logger
    attr_reader :host
    attr_reader :port
    attr_reader :options


    #
    # Available options are:
    #
    # * :debug (boolean) - If true the server logs debug information. Defaults to false.
    #
    def initialize(host, port, options)
      @host = host
      @port = port
      @options = options
      @registered_message_handlers_for_method = {}
      @registered_message_handlers = []

      init_logger "#{host}:#{port}"
    end

    def init_logger(logger_name)
      @logger = Logger.new logger_name
      @logger.outputters = Outputter.stdout
    end

    #
    # Registers the given message handlers (of type Qeemono::MessageHandler::Base).
    #
    def register_message_handlers(message_handlers)
      message_handler_names = []
      message_handlers = [message_handlers] unless message_handlers.is_a? Array
      message_handlers.each do |message_handler|
        if check_message_handler(message_handler)
          handled_methods = message_handler.handled_methods || []
          handled_methods = [handled_methods] unless handled_methods.is_a? Array
          handled_methods_as_strings = []
          handled_methods.each do |method|
            handled_methods_as_strings << method.to_s
            (@registered_message_handlers_for_method[method.to_s] ||= []) << message_handler
          end
          message_handler_name = message_handler.name.to_s
          @registered_message_handlers << message_handler
          message_handler_names << message_handler_name
          logger.debug "Message handler '#{message_handler_name}' has been registered for methods #{handled_methods_as_strings.inspect}."
        end
      end
      logger.debug "Total amount of registered message handlers: #{@registered_message_handlers.size}"
    end

    #
    # Returns true if the message handler is valid; false otherwise.
    #
    def check_message_handler(message_handler)
      if !message_handler.is_a? Qeemono::MessageHandler::Base
        logger.error "This is not a message handler! Must subclass '#{Qeemono::MessageHandler::Base.to_s}'. (Details: #{message_handler})"
        return false
      end

      if message_handler.name.nil? || message_handler.name.to_s.strip.empty?
        logger.error "Message handler must have a non-empty name! (Details: #{message_handler})"
        return false
      end

      handled_methods = message_handler.handled_methods || []
      handled_methods = [handled_methods] unless handled_methods.is_a? Array
      if handled_methods.empty?
        logger.warn "Message handler '#{message_handler.name}' does not listen to any method! (Details: #{message_handler})"
        return false
      end

      handled_methods.each do |method|
        if method.nil? || method.to_s.strip.empty?
          logger.error "Message handler '#{message_handler.name}' tries to listen to invalid method! Methods must be strings or symbols. (Details: #{message_handler})"
          return false
        end
      end

      if @registered_message_handlers.include?(message_handler)
        logger.error "Message handler '#{message_handler.name}' is already registered! (Details: #{message_handler})"
        return false
      end

      if !@registered_message_handlers.select { |mh| mh.name == message_handler.name }.empty?
        logger.error "A message handler with name '#{message_handler.name}' already exists! Names must be unique. (Details: #{message_handler})"
        return false
      end

      return true
    end

    #
    # Unregisters the given message handlers (of type Qeemono::MessageHandler::Base).
    #
    def unregister_message_handlers(message_handlers)
      message_handler_names = []
      message_handlers = [message_handlers] unless message_handlers.is_a? Array
      message_handlers.each do |message_handler|
        handled_methods = message_handler.handled_methods || []
        handled_methods = [handled_methods] unless handled_methods.is_a? Array
        handled_methods.each do |method|
          @registered_message_handlers_for_method[method.to_s].delete(message_handler)
          @registered_message_handlers.delete(message_handler)
        end
        message_handler_names << message_handler.name.to_s
      end
      logger.debug "Unregistered #{message_handler_names.size} message handlers. (Details: #{message_handler_names.inspect})"
      logger.debug "Total amount of registered message handlers: #{@registered_message_handlers.size}"
    end

    def start

      @web_sockets = {} # key = web socket signature (aka client id); value = web socket object
      @channels = {} # key = channel symbol; value = channel object
      @channels[:broadcast] = EM::Channel.new
      @channel_subscriptions = {} # key = web socket signature (aka client id); value = hash of channel symbols and channel subscriber ids {channel symbol => channel subscriber id}

      EventMachine.run do
        EventMachine::WebSocket.start(:host => @host, :port => @port, :debug => @options[:debug]) do |ws|

          ws.onopen do
            remember_web_socket(ws)
            subscribe_to_channels(ws, :broadcast) # Every client is automatically subscribed to the broadcast channel
          end

          ws.onmessage do |message|
            begin
              message_as_json = JSON.parse message
              result = self.class.parse_message(message_as_json)
              if result == :ok
                logger.debug "Received valid message. Going to dispatch. (Details: #{message_as_json.inspect})"
                dispatch_message(ws, message_as_json)
              else
                err_msg = result[1]
                logger.error err_msg
                ws.send err_msg
              end
            rescue JSON::ParserError => e
              msg = "Received invalid message! Must be JSON. Ignoring. (Details: #{e.to_s})"
              ws.send msg
              logger.error msg
            end
          end # end - ws.onmessage

          ws.onclose do
            unsubscribe_from_channels(ws, :all)
            forget_web_socket(ws)
          end

        end # end - EventMachine::WebSocket.start

        logger.info "The qeemono server has been started on host #{@host}:#{@port} at #{Time.now}."
      end # end - EventMachine.run

    end # end - start

    #
    # Subscribes the client represented via the web socket object (web_socket) to
    # the channels represented via the channel_symbols array (instead of an array also
    # a single channel symbol can be passed). Channels are created on-the-fly if not
    # existent yet.
    #
    # Returns the channel subscriber ids (array) of all channels being subscribed to.
    #
    def subscribe_to_channels(web_socket, channel_symbols)
      channel_symbols = [channel_symbols] unless channel_symbols.is_a? Array

      client_id = web_socket.signature
      channel_subscriber_ids = []

      channel_symbols.each do |channel_symbol|
        channel = (@channels[channel_symbol] ||= EM::Channel.new)
        # Create a subscriber id for the web socket client...
        channel_subscriber_id = channel.subscribe do |message|
          # Broadcast (push) message to all subscribers...
          web_socket.send message
        end
        # ... and add the channel (a hash of the channel symbol and subscriber id) to
        # the hash of channel subscriptions for the resp. client...
        (@channel_subscriptions[client_id] ||= {})[channel_symbol] = channel_subscriber_id
        channel_subscriber_ids << channel_subscriber_id
      end

      msg = "New client ##{client_id} has been subscribed to channels #{channel_symbols.inspect} (subscriber ids are #{channel_subscriber_ids.inspect})."
      @channels[:broadcast].push msg
      logger.debug msg

      return channel_subscriber_ids
    end

    #
    # Unsubscribes the client represented via the web socket object (web_socket) from
    # the channels represented via the channel_symbols array (instead of an array also
    # a single channel symbol can be passed). If :all is passed as channel symbol the
    # client is unsubscribed from all channels it is subscribed to.
    #
    # Returns the channel subscriber ids (array) of all channels being unsubscribed from.
    #
    def unsubscribe_from_channels(web_socket, channel_symbols)
      channel_symbols = [channel_symbols] unless channel_symbols.is_a? Array

      client_id = web_socket.signature
      channel_subscriber_ids = []

      if channel_symbols == [:all]
        channel_symbols = @channel_subscriptions[client_id].keys
      end

      channel_symbols.each do |channel_symbol|
        channel_subscriber_id = @channel_subscriptions[client_id][channel_symbol]
        @channels[channel_symbol].unsubscribe(channel_subscriber_id)
        channel_subscriber_ids << channel_subscriber_id
      end

      msg = "Client ##{client_id} has been unsubscribed from channels #{channel_symbols.inspect} (subscriber ids were #{channel_subscriber_ids.inspect})."
      @channels[:broadcast].push msg
      logger.debug msg

      return channel_subscriber_ids
    end

    #
    # Remembers the given web socket (aka client) so that it is accessible
    # from any other web socket session.
    #
    def remember_web_socket(web_socket)
      # Store the web socket for this client...
      @web_sockets[web_socket.signature] = web_socket
    end

    #
    # Forgets the given web socket (aka client).
    #
    def forget_web_socket(web_socket)
      # Store the web socket for this client...
      @web_sockets.delete(web_socket.signature)
    end

    #
    # Returns :ok if all mandatory keys are existent in the JSON message;
    # otherwise an array [:error, <err_msg>] containing :error as the first
    # and the resp. error message as the second element is returned.
    #
    def self.parse_message(message_as_json)
      return [:error, 'Message is nil'] if message_as_json.nil?

      # Check for all mandatory keys...
      (MANDATORY_KEYS-[:version]).each do |key|
        check_message_for_mandatory_key(key, message_as_json) # aka action
        check_message_for_mandatory_key(key, message_as_json) # the method/action parameters
      end
      # end - Check for all mandatory keys

      # If no protocol version is given, the latest/current version is assumed and added...
      message_as_json[:version.to_s] = PROTOCOL_VERSION

      return :ok
    rescue => e
      return [:error, e.to_s]
    end

    #
    # Returns true if the given key is existent in the JSON message;
    # raises an exception otherwise.
    #
    def self.check_message_for_mandatory_key(key, message_as_json)
      if message_as_json[key.to_s].nil?
        raise "Key :#{key.to_s} is missing in the JSON message! Ignoring." # TODO: raise dedicated exception here
      end
      return true
    end

    #
    # Dispatches the received message to the responsible message handler.
    #
    def dispatch_message(web_socket, message_as_json)
      # TODO: implement
      @channels[:broadcast].push(message_as_json.to_s)
    end

  end # end - class Server
end # end - module Qeemono
