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
#   - lightweight
#   - modular
#   - event-driven
#   - no boilerplate code (like e.g. queueing)
#   - bi-directional push (Web Socket)
#   - stateful
#   - session aware
#   - resistant against session hijacking attempts
#   - thin JSON protocol
#   - automatic protocol validation
#   - no thick framework underlying
#   - communication can be 1-to-1, 1-to-channel, 1-to-broadcast, and 1-to-server
#       (broadcast and channel communication is possible with 'bounce' flag)
#   - clean and mean implemented
#   - message handlers use observer pattern to register
#
# Requirements on server-side:
# ----------------------------
#
#   Needed Ruby Gems:
#     - em-websocket (https://rubygems.org/gems/em-websocket)
#     - json (https://rubygems.org/gems/json
#     - log4r (https://rubygems.org/gems/log4r)
#     - rspec (https://rubygems.org/gems/rspec)
#
# Requirements on client-side:
# ----------------------------
#
#    - jQuery (http://jquery.com)
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
require './qeemono/lib/exception/qeemono_standard_error'
require './qeemono/notificator'
require './qeemono/message_handler_manager'
require './qeemono/channel_manager'
require './qeemono/client_manager'
require './qeemono/message_handler/base'
require './qeemono/message_handler/core/system'
require './qeemono/message_handler/core/communication'
require './qeemono/message_handler/core/candidate_collection'


class EM::Channel
  #
  # For convenience: introduce relay method which delegates to push.
  #
  def relay(*args)
    # Broadcast to all subscribers of the channel. Actual sending to
    # the clients is done in the Ruby block passed to the EM::Channel#subscribe
    # method which is called in Qeemono::ChannelManager#subscribe.
    push(*args)
  end
end

module EventMachine
  module WebSocket
    class Connection
      #
      # For convenience: introduce relay method which delegates to send.
      #
      def relay(data)
        send(data.to_json)
      end
    end
  end
end

module Qeemono
  #
  # This is the qeemono server. It is the main class of the qeemono server project.
  #
  # Associated classes can interact with the qeemono server via the
  # qeemono server interface (qsif).
  #
  class Server

    include Log4r

    APPLICATION_VERSION = '0.1.3'

    attr_reader :message_handler_manager


    #
    # Available options are:
    #
    # * :debug (boolean) - If true the server logs debug information. Defaults to false.
    #
    def initialize(host, port, options)
      init_logger "#{host}:#{port}"

      @qsif = {   # The internal server interface
        :logger => @logger,
        :host => host,
        :port => port,
        :options => options,
        :notificator => nil, # Is set by the Notificator itself
        :message_handler_manager => nil, # Is set by the MessageHandlerManager itself
        :channel_manager => nil,  # Is set by the ChannelManager itself
        :client_manager => nil # Is set by the ClientManager itself
      }

      # TODO: do not expose too much information! Create a public qsif for message handlers!
      @qsif_public = @qsif # The public server interface

      # ************************

      Qeemono::Notificator.new(@qsif) # Must be the first because all following are going to use the Notificator
      @message_handler_manager = Qeemono::MessageHandlerManager.new(@qsif, @qsif_public)
      Qeemono::ChannelManager.new(@qsif)
      Qeemono::ClientManager.new(@qsif)
    end

    def start

      EventMachine.run do
        EventMachine::WebSocket.start(:host => @qsif[:host], :port => @qsif[:port], :debug => @qsif[:options][:debug]) do |ws|

          ws.onopen do
            begin
              client_id = @qsif[:client_manager].bind(ws)
              begin
                @qsif[:channel_manager].subscribe(client_id, :broadcast) # Every client is automatically subscribed to the broadcast channel
                @qsif[:channel_manager].subscribe(client_id, :broadcastwb, {:bounce => true}) # Every client is automatically subscribed to the broadcastwb (wb = with bounce) channel
                notify(:type => :debug, :code => 6000, :receivers => @qsif[:channel_manager].get(:channel => :broadcast), :params => {:client_id => client_id, :wss => ws.signature})
              rescue => e
                notify(:type => :fatal, :code => 9001, :receivers => ws, :params => {:client_id => client_id, :err_msg => e.to_s}, :exception => e)
              end
            rescue => e
              notify(:type => :fatal, :code => 9000, :receivers => ws, :params => {:err_msg => e.to_s}, :exception => e)
            end
          end

          ws.onmessage do |message|
            begin
              client_id = @qsif[:client_manager].bind(ws)
              begin
                @qsif[:notificator].parse_message(client_id, message) do |message_hash|
                  #notify(:type => :debug, :code => 6010, :params => {:client_id => client_id, :message_hash => message_hash.inspect})
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
                client_id = @qsif[:client_manager].unbind(ws)
                notify(:type => :debug, :code => 6020, :receivers => @qsif[:channel_manager].get(:channel => :broadcast), :params => {:client_id => client_id, :wss => ws.signature})
              rescue => e
                notify(:type => :fatal, :code => 9001, :receivers => ws, :params => {:client_id => client_id, :err_msg => e.to_s}, :exception => e)
              end
            rescue => e
              notify(:type => :fatal, :code => 9000, :receivers => ws, :params => {:err_msg => e.to_s}, :exception => e)
            end
          end

        end # end - EventMachine::WebSocket.start

        notify(:type => :info, :code => 1000, :params => {:host => @qsif[:host], :port => @qsif[:port], :current_time => Time.now, :app_version => APPLICATION_VERSION})
      end # end - EventMachine.run

    end # end - start

    protected

    #
    # Dispatches the received message to the responsible message handler.
    #
    def dispatch_message(message_hash)
      client_id = message_hash[:client_id]
      method_name = message_hash[:method].to_sym
      message_handlers = @qsif[:message_handler_manager].get(:method => method_name)
      if message_handlers.empty?
        notify(:type => :error, :code => 9500, :receivers => @qsif[:client_manager].get(:client_id => client_id), :params => {:method_name => method_name, :client_id => client_id, :message_hash => message_hash.inspect})
      else
        message_handlers.each do |message_handler|
          handle_method_sym = "handle_#{method_name}".to_sym
          if message_handler.respond_to?(handle_method_sym)
            begin
              # Here, the actual dispatch to the message handler happens!
              # The origin client id (the sender) is passed as first argument, the actual message as second...
              # TODO: load the message handler to dispatch to depending on the given protocol version (message_hash[:version])
              message_handler.send(handle_method_sym, client_id, message_hash[:params])
            rescue Qeemono::QeemonoStandardError => e
              notify(:type => :error, :code => 9515, :receivers => @qsif[:client_manager].get(:client_id => client_id), :params => {:handle_method_name => handle_method_sym.to_s, :message_handler_name => message_handler.name, :message_handler_class => message_handler.class, :client_id => client_id, :message_hash => message_hash.inspect, :err_msg => e.to_s}, :exception => e, :no_log => true)
            rescue => e
              notify(:type => :fatal, :code => 9510, :receivers => @qsif[:client_manager].get(:client_id => client_id), :params => {:handle_method_name => handle_method_sym.to_s, :message_handler_name => message_handler.name, :message_handler_class => message_handler.class, :client_id => client_id, :message_hash => message_hash.inspect, :err_msg => e.to_s}, :exception => e)
            end
          else
            notify(:type => :fatal, :code => 9520, :receivers => @qsif[:client_manager].get(:client_id => client_id), :params => {:message_handler_name => message_handler.name, :message_handler_class => message_handler.class, :method_name => method_name, :handle_method_name => handle_method_sym.to_s, :client_id => client_id, :message_hash => message_hash.inspect})
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

    private

    def logger
      @logger
    end

    def notify(*args)
      @qsif[:notificator].notify(*args)
    end

  end # end - class Server
end # end - module Qeemono
