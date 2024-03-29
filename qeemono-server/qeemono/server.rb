#
# This is the qeemono server.
#
# (c) 2011, Mark von Zeschau
#
require 'em-websocket'
require 'json'
require 'log4r'

require_relative 'lib/util/common_utils'
require_relative 'lib/util/string_utils'
require_relative 'lib/util/thread_local_pool'
require_relative 'lib/extensions/string_extensions'
require_relative 'lib/exception/qeemono_standard_error'
require_relative 'notificator'
require_relative 'message_handler_manager'
require_relative 'channel_manager'
require_relative 'client_manager'
require_relative 'message_handler/base'
require_relative 'message_handler/core/system'
require_relative 'message_handler/core/communication'
require_relative 'message_handler/core/candidate_collection'
require_relative 'message_handler/core/candidate_collection2'


class EM::Channel
  #
  # For convenience: introduce relay method which delegates to push.
  #
  # Note for developers: This method is called only from within the
  # Qeemono::Notificator#relay_internal method.
  #
  def relay(*args)
    # Broadcasts to all subscribers of this channel (EM::Channel object).
    #
    # The actual sending to the clients is done in the Ruby block passed
    # to the EM::Channel#subscribe method which is called from within the
    # Qeemono::ChannelManager#subscribe method.
    push(*args)
  end
end

module EventMachine
  module WebSocket
    class Connection
      #
      # For convenience: introduces a relay method which delegates to send.
      #
      # Note for developers: This method is called only from within the
      # Qeemono::Notificator#relay_internal method and from within the
      # 'channel.subscribe' block in the Qeemono::ChannelManager#subscribe
      # method.
      #
      def relay(message_hash)
        send(message_hash.to_json)
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

    APPLICATION_VERSION = '0.2.3'
    MESSAGE_DISPATCH_THREAD_TIMEOUT_IN_SECONDS = 3


    attr_reader :message_handler_manager


    #
    # Available options are:
    #
    #   * :ws_debug (boolean) - If true the server logs web socket debug information. Defaults to false.
    #   * :log_file_fq_path - The full qualified log file path - Defaults to ./log/qeemono_server.log
    #   * :enable_persistence - If true the persistence message handler is required (and activated). Defaults to false.
    #
    def initialize(host, port, options = {})
      if options[:enable_persistence]
        require_relative 'message_handler/core/persistence'
      end
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
        :client_manager => nil, # Is set by the ClientManager itself
        :server => self
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
            bind_parse_and_dispatch(ws, message) do |message_hash|
              dispatch_message_externally_triggered(message_hash)
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

      # TODO: important: In case of Ctrl-C, kill the process nicely...

    end # end - start

    #
    # Used for internal message handler execution. That is, if
    # some message handler method is called from withing a
    # method of another message handler of the same qeemono
    # server.
    #
    # For more details see __dispatch_message__ method.
    #
    def dispatch_message(message)
      client_id = Qeemono::Util::ThreadLocalPool.load_client_id
      ws = @qsif[:client_manager].web_socket(:client_id => client_id)
      bind_parse_and_dispatch(ws, message) do |message_hash|
        __dispatch_message__(message_hash, false)
      end
    end

    protected

    #
    # Used for external message handler execution. That is, if
    # some message handler method is called by an external
    # client (e.g. Javascript client) via the JSON-based
    # qeemono protocol.
    #
    # For more details see __dispatch_message__ method.
    #
    def dispatch_message_externally_triggered(message_hash)
      __dispatch_message__(message_hash, true)
    end

    #
    # Dispatches the received message (which has already been parsed and
    # is known to be well-formed and correct) to the responsible message
    # handler. Either no message handler is given at all then the message
    # is sent to all matching message handlers responsible for the given
    # method. Otherwise, if a message handler is given prefixing the method,
    # the respective message handler is addressed.
    #
    # If (and only if) called externally, that is from e.g. a Javascript
    # client via the qeemono JSON protocol, execution is timed out after
    # MESSAGE_DISPATCH_THREAD_TIMEOUT_IN_SECONDS seconds. This is to
    # prevent infinite loops and methods taking too long to execute.
    # If called internally, the timeout is disabled since it has already
    # been activated by the initial external request which came beforehand.
    #
    # Example:
    #
    # {"method":"qeemono::cand.echo", "params":{"a":"123"}}
    #
    #      sends methods 'echo' to message handler 'qeemono::cand' while
    #
    # {"method":"echo", "params":{"a":"123"}}
    #
    #      sends methods 'echo' to *all* suitable message handlers.
    #
    def __dispatch_message__(message_hash, enable_timeout_thread)
      Qeemono::Util::ThreadLocalPool.store_seq_id(message_hash[:seq_id])

      client_id = message_hash[:client_id]
      fq_method_name = message_hash[:method].to_sym
      message_handler_name, method_name = extract_message_handler_name_from_method_name(fq_method_name)

      # Get all registered message handlers filtered by the given conditions hash...
      message_handlers = @qsif[:message_handler_manager].message_handlers(:method => method_name, :name => message_handler_name, :modules => @qsif[:client_manager].modules(client_id), :version => message_hash[:version])

      if message_handlers.empty?
        # If no message handler matches the above condition send an error notification and abort processing...
        message_handler_names_for_notification = message_handler_name ? [message_handler_name] : 'all'
        notify(:type => :error, :code => 9500, :receivers => @qsif[:client_manager].web_socket(:client_id => client_id), :params => {:method_name => method_name, :message_handler_names => message_handler_names_for_notification, :client_id => client_id, :version => message_hash[:version], :modules => @qsif[:client_manager].modules(client_id).inspect, :message_hash => message_hash.inspect})
      else
        message_handlers.each do |message_handler|
          handle_method_sym = "handle_#{method_name}".to_sym
          if message_handler.respond_to?(handle_method_sym)
            begin
              if enable_timeout_thread
                # Here, the actual dispatch to the message handler happens!
                # The origin client id (the sender) is passed as first argument, the actual message as second...
                message_handler_thread = Thread.new(handle_method_sym, client_id, message_hash[:params], message_hash[:seq_id]) do |tl_handle_method_sym, tl_client_id, tl_params, tl_seq_id|
                  Qeemono::Util::ThreadLocalPool.store_seq_id(tl_seq_id)
                  Qeemono::Util::ThreadLocalPool.store_client_id(tl_client_id)
                  message_handler.send(tl_handle_method_sym, tl_client_id, tl_params)
                  Qeemono::Util::ThreadLocalPool.delete_seq_id
                  Qeemono::Util::ThreadLocalPool.delete_client_id
                end
                thread_join_result = message_handler_thread.join(MESSAGE_DISPATCH_THREAD_TIMEOUT_IN_SECONDS) # The execution of the message handler method must not last longer than 3 seconds
                if thread_join_result.nil?
                  # Thread has been aborted (because timeout has been exceeded)...
                  notify(:type => :fatal, :code => 9530, :receivers => @qsif[:client_manager].web_socket(:client_id => client_id), :params => {:handle_method_name => handle_method_sym.to_s, :message_handler_name => message_handler.name, :message_handler_class => message_handler.class, :version => message_handler.version, :client_id => client_id, :message_hash => message_hash.inspect, :thread_timeout => MESSAGE_DISPATCH_THREAD_TIMEOUT_IN_SECONDS})
                end
              else
                message_handler.send(handle_method_sym, client_id, message_hash[:params])
              end
            rescue Qeemono::QeemonoStandardError => e
              notify(:type => :error, :code => 9515, :receivers => @qsif[:client_manager].web_socket(:client_id => client_id), :params => {:handle_method_name => handle_method_sym.to_s, :message_handler_name => message_handler.name, :message_handler_class => message_handler.class, :version => message_handler.version, :client_id => client_id, :message_hash => message_hash.inspect, :err_msg => e.to_s}, :exception => e, :no_log => true)
            rescue => e
              notify(:type => :fatal, :code => 9510, :receivers => @qsif[:client_manager].web_socket(:client_id => client_id), :params => {:handle_method_name => handle_method_sym.to_s, :message_handler_name => message_handler.name, :message_handler_class => message_handler.class, :version => message_handler.version, :client_id => client_id, :message_hash => message_hash.inspect, :err_msg => e.to_s}, :exception => e)
            end
          else
            notify(:type => :fatal, :code => 9520, :receivers => @qsif[:client_manager].web_socket(:client_id => client_id), :params => {:message_handler_name => message_handler.name, :message_handler_class => message_handler.class, :version => message_hash[:version], :method_name => method_name, :handle_method_name => handle_method_sym.to_s, :client_id => client_id, :message_hash => message_hash.inspect})
          end
        end
      end

      Qeemono::Util::ThreadLocalPool.delete_seq_id
    end

    def init_logger(logger_name, log_file)
      @logger = Logger.new logger_name
      file_outputter = FileOutputter.new('file_outputter', :filename => log_file)
      @logger.outputters << Outputter.stdout
      @logger.outputters << file_outputter
    end

    #
    # Extracts the message handler name from the given (full qualified) method name.
    #
    # Each method name can be prefixed with a message handler name. If so the
    # message handler name must be separated with a dot ('.') from the method name.
    #
    # Example: my_message_handler.my_method_name
    #
    # Returns an two-element array containing the message handler name (or nil
    # if not given) as first element and the method name as second element.
    #
    # TODO: postponed: allow for addressing multiple message handlers at once
    #
    def extract_message_handler_name_from_method_name(fq_method_name)
      fq_method_name = fq_method_name.to_s
      if index=fq_method_name.index('.')
        message_handler_name = fq_method_name[0...index].strip.to_sym
        method_name = fq_method_name[index+1..-1]
      else
        message_handler_name = nil
        method_name = fq_method_name
      end
      [message_handler_name, method_name.strip.to_sym]
    end

    private

    def bind_parse_and_dispatch(ws, message)
      begin
        client_id = @qsif[:client_manager].bind(ws)
        begin
          @qsif[:notificator].parse_message(client_id, message) do |message_hash|
            notify(:type => :debug, :code => 6010, :params => {:client_id => client_id, :message_hash => message_hash.inspect})
            yield(message_hash)
          end
        rescue => e
          notify(:type => :fatal, :code => 9002, :receivers => ws, :params => {:client_id => client_id, :message_hash => message.inspect, :err_msg => e.to_s}, :exception => e)
        end
      rescue => e
        notify(:type => :fatal, :code => 9000, :receivers => ws, :params => {:err_msg => e.to_s}, :exception => e)
      end
    end

    def logger
      @logger
    end

    def notify(*args)
      @qsif[:notificator].notify(*args)
    end

  end # end - class Server
end # end - module Qeemono
