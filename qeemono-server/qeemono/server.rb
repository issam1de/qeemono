#
# This is the qeemono server.
# A lightwight, Web Socket and EventMachine based server.
#
# (c) 2011, Mark von Zeschau
#
#
# Core features:
# --------------
#
#   - lightweight
#   - modular
#   - event-driven
#   - bi-directional push (Web Socket)
#   - stateful
#   - session aware
#   - resistant against session hijacking
#   - thin JSON protocol
#   - automatic protocol validation
#   - no thick framework underlying
#   - communication can be 1-to-1, 1-to-many, 1-to-channel(s), 1-to-broadcast, and 1-to-server
#       (broadcast and channel communication is possible with 'bounce' flag)
#   - message handlers use observer pattern to register
#
# Requirements on server-side:
# ----------------------------
#
#   Needed Ruby Gems:
#     - eventmachine (https://rubygems.org/gems/eventmachine)
#     - em-websocket (https://rubygems.org/gems/em-websocket) [depends on eventmachine]
#     - iconv (https://rubygems.org/gems/iconv - see also http://rvm.beginrescueend.com/packages/iconv/)
#     - json (https://rubygems.org/gems/json [depends on iconv]
#     - log4r (https://rubygems.org/gems/log4r)
#     - [needed for testing] em-http-request (https://rubygems.org/gems/em-http-request)
#
#   To install them all just execute the following in a terminal window:
#   gem install em-websocket json log4r em-http-request
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
#   - EventMachine (http://rubyeventmachine.com/)
#
#
#
# [ The qeemono server and all its dependencies are tested under Ruby 1.9.x ]
#


require 'em-websocket'
require 'json'
require 'log4r'

require_relative 'lib/util/common_utils'
require_relative 'lib/exception/qeemono_standard_error'
require_relative 'notificator'
require_relative 'message_handler_manager'
require_relative 'channel_manager'
require_relative 'client_manager'
require_relative 'message_handler/base'
require_relative 'message_handler/core/system'
require_relative 'message_handler/core/communication'
require_relative 'message_handler/core/candidate_collection'


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
  # Start the server with the start method.
  #
  class Server

    include Log4r

    APPLICATION_VERSION = '0.1.4'

    attr_reader :message_handler_manager


    #
    # Available options are:
    #
    #   * :ws_debug (boolean) - If true the server logs web socket debug information. Defaults to false.
    #   * :log_file_fq_path - The full qualified log file path - Defaults to ./log/qeemono_server.log
    #
    def initialize(host, port, options = {})
      options[:log_file_fq_path] ||= 'log/qeemono_server.log'

      init_logger("#{host}:#{port}", options[:log_file_fq_path])

      # ************************

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

      @qsif_public = @qsif # Set the public server interface used by all message handlers
      # ... until now internal == public qsif

      # ************************

      Qeemono::Notificator.new(@qsif) # Must be the first because all following are going to use the Notificator
      @message_handler_manager = Qeemono::MessageHandlerManager.new(@qsif, @qsif_public)
      Qeemono::ChannelManager.new(@qsif)
      Qeemono::ClientManager.new(@qsif)
    end

    def start

      EventMachine.run do
        EventMachine::WebSocket.start(:host => @qsif[:host], :port => @qsif[:port], :debug => @qsif[:options][:ws_debug]) do |ws|

          ws.onopen do
            begin
              client_id = @qsif[:client_manager].bind(ws)
              begin
                @qsif[:channel_manager].subscribe(client_id, :broadcast) # Every client is automatically subscribed to the broadcast channel
                @qsif[:channel_manager].subscribe(client_id, :broadcastwb, {:bounce => true}) # Every client is automatically subscribed to the broadcastwb (wb = with bounce) channel
                notify(:type => :debug, :code => 6000, :receivers => @qsif[:channel_manager].channel(:channel => :broadcast), :params => {:client_id => client_id, :wss => ws.signature})
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
                client_id = @qsif[:client_manager].unbind(ws)
                notify(:type => :debug, :code => 6020, :receivers => @qsif[:channel_manager].channel(:channel => :broadcast), :params => {:client_id => client_id, :wss => ws.signature})
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
      message_handlers = @qsif[:message_handler_manager].message_handlers(:method => method_name, :modules => @qsif[:client_manager].modules(client_id), :version => message_hash[:version])
      if message_handlers.empty?
        notify(:type => :error, :code => 9500, :receivers => @qsif[:client_manager].web_socket(:client_id => client_id), :params => {:method_name => method_name, :client_id => client_id, :version => message_hash[:version], :modules => @qsif[:client_manager].modules(client_id).inspect, :message_hash => message_hash.inspect})
      else
        message_handlers.each do |message_handler|
          handle_method_sym = "handle_#{method_name}".to_sym
          if message_handler.respond_to?(handle_method_sym)
            begin
              # Here, the actual dispatch to the message handler happens!
              # The origin client id (the sender) is passed as first argument, the actual message as second...
              message_handler.send(handle_method_sym, client_id, message_hash[:params])
            rescue Qeemono::QeemonoStandardError => e
              notify(:type => :error, :code => 9515, :receivers => @qsif[:client_manager].web_socket(:client_id => client_id), :params => {:handle_method_name => handle_method_sym.to_s, :message_handler_name => message_handler.name, :message_handler_class => message_handler.class, :client_id => client_id, :message_hash => message_hash.inspect, :err_msg => e.to_s}, :exception => e, :no_log => true)
            rescue => e
              notify(:type => :fatal, :code => 9510, :receivers => @qsif[:client_manager].web_socket(:client_id => client_id), :params => {:handle_method_name => handle_method_sym.to_s, :message_handler_name => message_handler.name, :message_handler_class => message_handler.class, :client_id => client_id, :message_hash => message_hash.inspect, :err_msg => e.to_s}, :exception => e)
            end
          else
            notify(:type => :fatal, :code => 9520, :receivers => @qsif[:client_manager].web_socket(:client_id => client_id), :params => {:message_handler_name => message_handler.name, :message_handler_class => message_handler.class, :method_name => method_name, :handle_method_name => handle_method_sym.to_s, :client_id => client_id, :version => message_hash[:version], :message_hash => message_hash.inspect})
          end
        end
      end
    end

    def init_logger(logger_name, log_file)
      @logger = Logger.new logger_name
      file_outputter = FileOutputter.new('file_outputter', :filename => log_file)
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
