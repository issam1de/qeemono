#
# This is the qeemono server.
# A lightwight, Web Socket based server.
#
#   - by Mark von Zeschau, Qeevee
#
# (c) 2011
#
#
# Core features:
# --------------
#
#   - pure Ruby
#   - lightweight
#   - modular
#   - event-driven
#   - no boilerplate code (like e.g. queueing)
#   - bi-directional push (Web Socket)
#   - stateful
#   - session aware
#   - resistant against session hijacking attempts
#   - thin JSON protocol
#   - no thick framework underlying
#   - communication can be broadcast, 1-to-1, and 1-to-channels(s) (channel == user group)
#   - clean and mean implemented
#   - message handlers use observer pattern to register
#
# Requirements on server-side:
# ----------------------------
#
#   Needed Ruby Gems:
#     - em-websocket (https://github.com/igrigorik/em-websocket)
#     - json
#     - log4r
#
# Requirements on client-side:
# ----------------------------
#
#    - jQuery
#    - jStorage
#    - Web Socket support - built-in in most modern browsers. If not built-in, you can
#                           utilize e.g. the HTML5 Web Socket implementation powered
#                           by Flash (see https://github.com/gimite/web-socket-js).
#                           All you need is to load the following JavaScript files in
#                           your HTML page:
#                             - swfobject.js
#                             - FABridge.js
#                             - web_socket.js
#
# External documentation:
# -----------------------
#
#   - Web Sockets (http://www.w3.org/TR/websockets/)
#   - EventMachine
#


require 'em-websocket'
require 'json'
require 'log4r'

require './qeemono/message_handler_registration_manager'
require './qeemono/message_handler/base'
require './qeemono/message_handler/core/system'
require './qeemono/message_handler/core/communication'
require './qeemono/message_handler/core/candidate_collection'


module Qeemono
  #
  # This is the qeemono server. It is the main class of the qeemono server project.
  #
  # Associated classes can interact with the qeemono server via the
  # qeemono server interface (qsif).
  #
  class Server

    include Log4r

    PROTOCOL_VERSION = '1.0'
    MANDATORY_KEYS = ['method', 'params', 'version']

    attr_reader :logger
    attr_reader :message_handler_registration_manager


    #
    # Available options are:
    #
    # * :debug (boolean) - If true the server logs debug information. Defaults to false.
    #
    def initialize(host, port, options)
      init_logger "#{host}:#{port}"

      @qsif = {   # The Server interface
        :logger => @logger,
        :host => host,
        :port => port,
        :options => options,
        :web_sockets => {}, # key = client id; value = web socket object
        :channels => {}, # key = channel symbol; value = channel object
        :channel_subscriptions => {}, # key = client id; value = hash of channel symbols and channel subscriber ids {channel symbol => channel subscriber id}
        :registered_message_handlers_for_method => {}, # key = method; value = message handler
        :registered_message_handlers => [] # all registered message handlers
      }
      @qsif[:channels][:broadcast] = EM::Channel.new

      @message_handler_registration_manager = Qeemono::MessageHandlerRegistrationManager.new(@qsif)
    end

    def init_logger(logger_name)
      @logger = Logger.new logger_name
      @logger.outputters = Outputter.stdout
    end

    def start

      EventMachine.run do
        EventMachine::WebSocket.start(:host => @qsif[:host], :port => @qsif[:port], :debug => @qsif[:options][:debug]) do |ws|

          ws.onopen do
            client_id = client_id(ws)
            if client_id
              subscribe_to_channels(client_id, :broadcast) # Every client is automatically subscribed to the broadcast channel
            end
          end

          ws.onmessage do |message|
            client_id = client_id(ws)
            if client_id
              begin
                message_hash = JSON.parse message
                result = self.class.parse_message(message_hash)
                if result == :ok
                  logger.debug "Received valid message. Going to dispatch. (Details: #{message_hash.inspect})"
                  dispatch_message(client_id, message_hash)
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
            end
          end # end - ws.onmessage

          ws.onclose do
            forget_client_web_socket_association(ws)
          end

        end # end - EventMachine::WebSocket.start

        logger.info "The qeemono server has been started on host #{@qsif[:host]}:#{@qsif[:port]} at #{Time.now}."
      end # end - EventMachine.run

    end # end - start

    #
    # Subscribes the client represented by client_id to the channels represented by
    # the channel_symbols array (instead of an array also a single channel symbol
    # can be passed). Channels are created on-the-fly if not existent yet.
    #
    # Returns the channel subscriber ids (array) of all channels being subscribed to.
    #
    def subscribe_to_channels(client_id, channel_symbols)
      channel_symbols = [channel_symbols] unless channel_symbols.is_a? Array

      channel_subscriber_ids = []

      channel_symbols.each do |channel_symbol|
        channel = (@qsif[:channels][channel_symbol] ||= EM::Channel.new)
        # Create a subscriber id for the client...
        channel_subscriber_id = channel.subscribe do |message|
          # Broadcast (push) message to all subscribers...
          @qsif[:web_sockets][client_id].send message
        end
        # ... and add the channel (a hash of the channel symbol and subscriber id) to
        # the hash of channel subscriptions for the resp. client...
        (@qsif[:channel_subscriptions][client_id] ||= {})[channel_symbol] = channel_subscriber_id
        channel_subscriber_ids << channel_subscriber_id
      end

      msg = "Client '#{client_id}' has been subscribed to channels #{channel_symbols.inspect} (subscriber ids are #{channel_subscriber_ids.inspect})."
      @qsif[:channels][:broadcast].push msg
      logger.debug msg

      return channel_subscriber_ids
    end

    #
    # Unsubscribes the client represented by client_id from the channels represented by
    # the channel_symbols array (instead of an array also a single channel symbol can
    # be passed). If :all is passed as channel symbol the client is unsubscribed from
    # all channels it is subscribed to.
    #
    # Returns the channel subscriber ids (array) of all channels being unsubscribed from.
    #
    def unsubscribe_from_channels(client_id, channel_symbols)
      channel_symbols = [channel_symbols] unless channel_symbols.is_a? Array

      channel_subscriber_ids = []

      if channel_symbols == [:all]
        channel_symbols = @qsif[:channel_subscriptions][client_id].keys
      end

      channel_symbols.each do |channel_symbol|
        channel_subscriber_id = @qsif[:channel_subscriptions][client_id][channel_symbol]
        @qsif[:channels][channel_symbol].unsubscribe(channel_subscriber_id)
        @qsif[:channel_subscriptions][client_id].delete(channel_symbol)
        channel_subscriber_ids << channel_subscriber_id
      end

      msg = "Client '#{client_id}' has been unsubscribed from channels #{channel_symbols.inspect} (subscriber ids were #{channel_subscriber_ids.inspect})."
      @qsif[:channels][:broadcast].push msg
      logger.debug msg

      #Test
      channel_symbols.each do |channel_symbol|
        raise "ERROR" if !@qsif[:channel_subscriptions][client_id][channel_symbol].nil?
      end

      return channel_subscriber_ids
    end

    #
    # Extracts the client_id (which must be persistently stored on client-side) from
    # the given web socket and returns it. Additionally, the given web socket is
    # associated with its contained client id so that the web socket can be accessed
    # via the client_id.
    #
    # Since web sockets are not session aware and therefore can change over time
    # (e.g. when the refresh button of the browser was hit) the association has to be
    # refreshed in order that the client_id always points to the current web socket
    # for this resp. client.
    #
    # If no client_id is contained in the web socket an error is sent back to the
    # requesting client and false is returned. Further processing of the request is
    # ignored.
    #
    # If another client is trying to steal another client's session (by passing the
    # same client_id) an error is sent back to the requesting client and false is
    # returned. Further processing of the request is ignored.
    #
    # Returns true if everything went well.
    #
    def client_id(web_socket)
      client_id = web_socket.request['Query']['client_id'].to_sym # Extract client_id from web socket
      if client_id.nil?
        msg = "Client did not send its client_id! Ignoring. (Web socket: #{web_socket})"
        web_socket.send msg
        logger.error msg
        return false
      else
        if session_hijacking_attempt?(web_socket, client_id)
          msg = "Attempt to steal session from client '#{client_id}'! Not allowed. Ignoring. (Web socket: #{web_socket})"
          web_socket.send msg
          logger.fatal msg
          return false
        end
        # Remeber the web socket for this client (establish the client/web socket association)...
        @qsif[:web_sockets][client_id] = web_socket
        return client_id
      end
    end

    #
    # Returns true if there is already a different web socket for the same client_id;
    # false otherwise.
    #
    def session_hijacking_attempt?(web_socket, client_id)
      older_web_socket = @qsif[:web_sockets][client_id]
      return true if older_web_socket && older_web_socket.object_id != web_socket.object_id
      return false
    end

    #
    # Forgets the association between the given web socket and its contained client.
    # For more information read the documentation  of
    # remember_client_web_socket_association
    #
    # Returns the client_id of the unlearned association.
    #
    def forget_client_web_socket_association(web_socket)
      client_id_to_forget, ___web_socket = @qsif[:web_sockets].rassoc(web_socket)
      if client_id_to_forget
        unsubscribe_from_channels(client_id_to_forget, :all)
        @qsif[:web_sockets].delete(client_id_to_forget)
        return client_id_to_forget
      end
    end

    #
    # Returns :ok if all mandatory keys are existent in the JSON message;
    # otherwise an array [:error, <err_msg>] containing :error as the first
    # and the resp. error message as the second element is returned.
    #
    def self.parse_message(message_hash)
      return [:error, 'Message is nil'] if message_hash.nil?

      # Check for all mandatory keys...
      (MANDATORY_KEYS-['version']).each do |key|
        check_message_for_mandatory_key(key, message_hash)
      end
      # end - Check for all mandatory keys

      # If no protocol version is given, the latest/current version is assumed and added...
      message_hash['version'] = PROTOCOL_VERSION

      return :ok
    rescue => e
      return [:error, e.to_s]
    end

    #
    # Returns true if the given key is existent in the JSON message;
    # raises an exception otherwise.
    #
    def self.check_message_for_mandatory_key(key, message_hash)
      if message_hash[key.to_s].nil?
        raise "Key '#{key.to_s}' is missing in the JSON message! Ignoring." # TODO: raise dedicated exception here
      end
      return true
    end

    #
    # Dispatches the received message to the responsible message handler.
    #
    def dispatch_message(client_id, message_hash)
      method_name = message_hash['method'].to_s
      message_handlers = @qsif[:registered_message_handlers_for_method][method_name] || []
      if message_handlers.empty?
        logger.warn "Did not found any message handler registered for method '#{method_name}'! Ignoring."
      else
        message_handlers.each do |message_handler|
          handle_method_sym = "handle_#{method_name}".to_sym
          if message_handler.respond_to?(handle_method_sym)
            begin
              # Here's the actual dispatch...
              message_handler.send(handle_method_sym, message_hash['params'])
            rescue => e
              backtrace = e.backtrace.map { |line| "\n#{line}" }.join
              logger.fatal "Method '#{handle_method_sym.to_s}' of message handler '#{message_handler.name}' (#{message_handler.class}) is buggy! (Details: #{e.to_s})#{backtrace}"
            end
          else
            err_msg = "Message handler '#{message_handler.name}' does not respond to method '#{method_name}'! (Details: #{message_handler}, Params: #{message_hash['params'].inspect})"
            logger.error err_msg
            @qsif[:web_sockets][client_id].send err_msg
          end
        end
      end
    end

  end # end - class Server
end # end - module Qeemono
