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
#   - communication can be broadcast, 1-to-1, and 1-to-channel (broadcast and channel communication possible with 'except-me' flag)
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
#    - jQuery (http://jquery.com)
#    - jStorage (http://www.jstorage.info)
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
#
#
# [ qeemono server is tested under Ruby 1.9.x ]
#


require 'em-websocket'
require 'json'
require 'log4r'

require './qeemono/notificator'
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

    attr_reader :message_handler_registration_manager


    #
    # Available options are:
    #
    # * :debug (boolean) - If true the server logs debug information. Defaults to false.
    #
    def initialize(host, port, options)
      init_logger "#{host}:#{port}"

      @anonymous_client_id = 0

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

      @notificator = Qeemono::Notificator.new(@qsif)
      @message_handler_registration_manager = Qeemono::MessageHandlerRegistrationManager.new(@qsif)
    end

    def start

      EventMachine.run do
        EventMachine::WebSocket.start(:host => @qsif[:host], :port => @qsif[:port], :debug => @qsif[:options][:debug]) do |ws|

          ws.onopen do
            begin
              client_id = client_id(ws)
              subscribe_to_channels(client_id, :broadcast) # Every client is automatically subscribed to the broadcast channel
              msg = "Client '#{client_id}' has been connected. (Web socket signature: #{ws.signature})"
              @qsif[:channels][:broadcast].push msg
              logger.debug msg
            rescue => e
              ws.send e.to_s
              logger.fatal backtrace(e)
            end
          end

          ws.onmessage do |message|
            begin
              client_id = client_id(ws)
              message_hash = JSON.parse message
              result = self.class.parse_message(message_hash)
              if result == :ok
                logger.debug "Received valid message from client '#{client_id}'. Going to dispatch. (Message: #{message_hash.inspect})"
                dispatch_message(client_id, message_hash)
              else
                err_msg = result[1]
                ws.send err_msg
                logger.error err_msg
              end
            rescue JSON::ParserError => e
              msg = "Received invalid message! Must be JSON. Ignoring. (Details: #{e.to_s})"
              ws.send msg
              logger.error msg
            rescue => e
              ws.send e.to_s
              logger.fatal backtrace(e)
            end
          end # end - ws.onmessage

          ws.onclose do
            begin
              client_id = forget_client_web_socket_association(ws)
              msg = "Client '#{client_id}' has been disconnected. (Web socket signature: #{ws.signature})"
              @qsif[:channels][:broadcast].push msg
              logger.debug msg
            rescue => e
              ws.send e.to_s
              logger.fatal backtrace(e)
            end
          end

        end # end - EventMachine::WebSocket.start

        logger.info "The qeemono server has been started on host #{@qsif[:host]}:#{@qsif[:port]} at #{Time.now}. Have Fun..."
      end # end - EventMachine.run

    end # end - start

    protected

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
          # Broadcast (push) message to all subscribers of this channel...
          @qsif[:web_sockets][client_id].send message
          puts "*****************"   # TODO
        end
        # ... and add the channel (a hash of the channel symbol and subscriber id) to
        # the hash of channel subscriptions for the resp. client...
        (@qsif[:channel_subscriptions][client_id] ||= {})[channel_symbol] = channel_subscriber_id
        channel_subscriber_ids << channel_subscriber_id

        msg = "Client '#{client_id}' has been subscribed to channel #{channel_symbol.inspect} (subscriber id is #{channel_subscriber_id})."
        @qsif[:channels][channel_symbol].push msg
      end

      logger.debug "Client '#{client_id}' has been subscribed to channels #{channel_symbols.inspect} (subscriber ids are #{channel_subscriber_ids.inspect})."

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

        msg = "Client '#{client_id}' has been unsubscribed from channel #{channel_symbol.inspect} (subscriber id was #{channel_subscriber_id})."
        @qsif[:channels][channel_symbol].push msg
      end

      logger.debug "Client '#{client_id}' has been unsubscribed from channels #{channel_symbols.inspect} (subscriber ids were #{channel_subscriber_ids.inspect})."

      return channel_subscriber_ids
    end

    #
    # This is the first thing what happens when client and
    # qeemono server connect.
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
      new_client_id = nil

      if client_id.nil?
        new_client_id = anonymous_client_id
        msg = "Client did not send its client_id! Allocating unique anonymous client id '#{new_client_id}'. (Web socket signature: #{web_socket.signature})"
        web_socket.send msg
        logger.warn msg
      end

      if session_hijacking_attempt?(web_socket, client_id)
        new_client_id = anonymous_client_id
        msg = "Attempt to hijack (steal) session from client '#{client_id}' by using its client id! Not allowed. Instead allocating unique anonymous client id '#{new_client_id}'. (Web socket signature: #{web_socket.signature})"
        web_socket.send msg
        logger.fatal msg
      end

      client_id = new_client_id if new_client_id

      # Remeber the web socket for this client (establish the client/web socket association)...
      @qsif[:web_sockets][client_id] = web_socket

      return client_id
    end

    #
    # Generates and returns a unique client id.
    # Used when a client does not submit its client id.
    #
    def anonymous_client_id
      "__anonymous-client-#{(@anonymous_client_id += 1)}"
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
    # This is the last thing what happens when client and
    # qeemono server disconnect (e.g. caused by browser refresh).
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
      method_name = message_hash['method'].to_sym
      message_handlers = @qsif[:registered_message_handlers_for_method][method_name] || []
      if message_handlers.empty?
        err_msg = "Did not find any message handler registered for method '#{method_name}'! Ignoring. (Sent from client '#{client_id}' with message #{message_hash.inspect})"
        @qsif[:web_sockets][client_id].send err_msg
        logger.warn err_msg
      else
        message_handlers.each do |message_handler|
          handle_method_sym = "handle_#{method_name}".to_sym
          if message_handler.respond_to?(handle_method_sym)
            begin
              # Here's the actual dispatch...
              message_handler.send(handle_method_sym, message_hash['params'])
            rescue => e
              err_msg = "Method '#{handle_method_sym.to_s}' of message handler '#{message_handler.name}' (#{message_handler.class}) failed! (Sent from client '#{client_id}' with message #{message_hash.inspect})#{backtrace(e)}"
              @qsif[:web_sockets][client_id].send err_msg
              logger.fatal err_msg
            end
          else
            err_msg = "Message handler '#{message_handler.name}' (#{message_handler.class}) is registered to handle method '#{method_name}' but does not respond to '#{handle_method_sym.to_s}'! (Sent from client '#{client_id}' with message #{message_hash.inspect})"
            @qsif[:web_sockets][client_id].send err_msg
            logger.error err_msg
          end
        end
      end
    end

    def init_logger(logger_name)
      @logger = Logger.new logger_name
      file_outputter = FileOutputter.new('file_outputter', :filename => 'log/qeemono_server.log')
      @logger.outputters << Outputter.stdout
      @logger.outputters << file_outputter
    end

    def logger
      @logger
    end

    def backtrace(exception)
      "\n" + exception.to_s + exception.backtrace.map { |line| "\n#{line}" }.join
    end

  end # end - class Server
end # end - module Qeemono
