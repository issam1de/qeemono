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
#   - communication can be 1-to-1, 1-to-channel, 1-to-broadcast, and 1-to-server
#       (broadcast and channel communication is possible with 'except-me' flag)
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

require './qeemono/lib/util/common_utils'
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

    attr_reader :message_handler_registration_manager


    class EM::Channel
      #
      # For convenience: introduce send method which
      # delegates to push.
      #
      def send(*args)
        push(*args)
      end
    end

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
        :registered_message_handlers => [], # all registered message handlers
        :notificator => nil, # Is set by the Notificator itself
        :message_handler_registration_manager => nil # Is set by the MessageHandlerRegistrationManager itself
      }
      @qsif[:channels][:broadcast] = EM::Channel.new

      # ************************

      Qeemono::Notificator.new(@qsif) # Must be the first because all following are going to use the Notificator
      @message_handler_registration_manager = Qeemono::MessageHandlerRegistrationManager.new(@qsif)
    end

    def start

      EventMachine.run do
        EventMachine::WebSocket.start(:host => @qsif[:host], :port => @qsif[:port], :debug => @qsif[:options][:debug]) do |ws|

          ws.onopen do
            begin
              client_id = client_id(ws)
              begin
                subscribe_to_channels(client_id, :broadcast) # Every client is automatically subscribed to the broadcast channel
                notify(:type => :debug, :code => 6000, :receivers => @qsif[:channels][:broadcast], :params => {:client_id => client_id, :wss => ws.signature})
              rescue => e
                notify(:type => :fatal, :code => 9001, :receivers => ws, :params => {:client_id => client_id, :err_msg => e.to_s}, :exception => e)
              end
            rescue => e
              notify(:type => :fatal, :code => 9000, :receivers => ws, :params => {:err_msg => e.to_s}, :exception => e)
            end
          end

          ws.onmessage do |message|
            begin
              client_id = client_id(ws)
              begin
                @qsif[:notificator].parse_message(client_id, message) do |message_hash|
                  notify(:type => :debug, :code => 6010, :params => {:client_id => client_id, :message_hash => message_hash.inspect})
                  dispatch_message(message_hash)
                end
              rescue => e
                notify(:type => :fatal, :code => 9002, :receivers => ws, :params => {:client_id => client_id, :message_hash => message.inspect, :err_msg => e.to_s}, :exception => e)
              end
            rescue => e
              notify(:type => :fatal, :code => 9000, :receivers => ws, :params => {:err_msg => e.to_s}, :exception => e)
            end
          end # end - ws.onmessage

          ws.onclose do
            begin
              begin
                client_id = forget_client_web_socket_association(ws)
                notify(:type => :debug, :code => 6020, :receivers => @qsif[:channels][:broadcast], :params => {:client_id => client_id, :wss => ws.signature})
              rescue => e
                notify(:type => :fatal, :code => 9001, :receivers => ws, :params => {:client_id => client_id, :err_msg => e.to_s}, :exception => e)
              end
            rescue => e
              notify(:type => :fatal, :code => 9000, :receivers => ws, :params => {:err_msg => e.to_s}, :exception => e)
            end
          end

        end # end - EventMachine::WebSocket.start

        notify(:type => :info, :code => 1000, :params => {:host => @qsif[:host], :port => @qsif[:port], :current_time => Time.now})
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
          # TODO: implement 'except-me' flag behavior
          # Broadcast the message to all subscribers of this channel...
          @qsif[:web_sockets][client_id].send message # DO NOT MODIFY THIS LINE!
        end
        # ... and add the channel (a hash of the channel symbol and subscriber id) to
        # the hash of channel subscriptions for the resp. client...
        (@qsif[:channel_subscriptions][client_id] ||= {})[channel_symbol] = channel_subscriber_id
        channel_subscriber_ids << channel_subscriber_id

        notify(:type => :debug, :code => 2000, :receivers => @qsif[:channels][channel_symbol], :params => {:client_id => client_id, :channel_symbol => channel_symbol.inspect, :channel_subscriber_id => channel_subscriber_id}, :no_log => true)
      end

      notify(:type => :debug, :code => 2010, :params => {:client_id => client_id, :channel_symbols => channel_symbols.inspect, :channel_subscriber_ids => channel_subscriber_ids.inspect})

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

        notify(:type => :debug, :code => 2020, :receivers => @qsif[:channels][channel_symbol], :params => {:client_id => client_id, :channel_symbol => channel_symbol.inspect, :channel_subscriber_id => channel_subscriber_id}, :no_log => true)
      end

      notify(:type => :debug, :code => 2030, :params => {:client_id => client_id, :channel_symbols => channel_symbols.inspect, :channel_subscriber_ids => channel_subscriber_ids.inspect})

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

      if client_id.nil? || client_id.to_s.strip == ''
        new_client_id = anonymous_client_id
        notify(:type => :warn, :code => 7000, :receivers => web_socket, :params => {:new_client_id => new_client_id, :wss => web_socket.signature})
      end

      if session_hijacking_attempt?(web_socket, client_id)
        new_client_id = anonymous_client_id
        notify(:type => :error, :code => 7010, :receivers => web_socket, :params => {:client_id => client_id, :new_client_id => new_client_id, :wss => web_socket.signature})
      end

      if client_id == Notificator::SERVER_CLIENT_ID
        new_client_id = anonymous_client_id
        notify(:type => :error, :code => 7020, :receivers => web_socket, :params => {:new_client_id => new_client_id, :wss => web_socket.signature})
      end

      client_id = new_client_id if new_client_id

      # Remember the web socket for this client (establish the client/web socket association)...
      @qsif[:web_sockets][client_id] = web_socket

      return client_id
    end

    #
    # Generates and returns a unique client id.
    # Used when a client does not submit its client id.
    #
    def anonymous_client_id
      "__anonymous-client-#{(@anonymous_client_id += 1)}".to_sym
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
    # Dispatches the received message to the responsible message handler.
    #
    def dispatch_message(message_hash)
      client_id = message_hash[:client_id]
      method_name = message_hash[:method].to_sym
      message_handlers = @qsif[:registered_message_handlers_for_method][method_name] || []
      if message_handlers.empty?
        notify(:type => :error, :code => 9500, :receivers => @qsif[:web_sockets][client_id], :params => {:method_name => method_name, :client_id => client_id, :message_hash => message_hash.inspect})
      else
        message_handlers.each do |message_handler|
          handle_method_sym = "handle_#{method_name}".to_sym
          if message_handler.respond_to?(handle_method_sym)
            begin
              # Here, the actual dispatch to the message handler happens!
              # The origin client id (the sender) is passed as first argument, the actual message as second...
              # TODO: load the message handler to dispatch to depending on the given protocol version (message_hash[:version])
              message_handler.send(handle_method_sym, client_id, message_hash[:params])
            rescue => e
              notify(:type => :fatal, :code => 9510, :receivers => @qsif[:web_sockets][client_id], :params => {:handle_method_name => handle_method_sym.to_s, :message_handler_name => message_handler.name, :message_handler_class => message_handler.class, :client_id => client_id, :message_hash => message_hash.inspect, :err_msg => e.to_s}, :exception => e)
            end
          else
            notify(:type => :fatal, :code => 9520, :receivers => @qsif[:web_sockets][client_id], :params => {:message_handler_name => message_handler.name, :message_handler_class => message_handler.class, :method_name => method_name, :handle_method_name => handle_method_sym.to_s, :client_id => client_id, :message_hash => message_hash.inspect})
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

    def notify(*args)
      @qsif[:notificator].notify(*args)
    end

  end # end - class Server
end # end - module Qeemono
