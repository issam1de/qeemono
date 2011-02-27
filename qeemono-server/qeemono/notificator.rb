module Qeemono
  #
  # The notificator is responsible for logging and informing client(s)
  # about relevant system information like e.g. errors.
  #
  class Notificator

    NOTIFICATION_MESSAGES = {
      6000 => "Client '${client_id}' has been connected. (Web socket signature: ${wss})",
      6100 => "Received valid message from client '${client_id}'. Going to dispatch. (Message: ${message_hash})",
      9000 => "${err_msg}",
      9010 => "${err_msg}"
    }


    def initialize(server_interface)
      @qsif = server_interface
      @logger = @qsif[:logger]
    end

    #
    # Options:
    # * :type (symbol, :info, :debug, :warn, :error, :fatal)
    # * :code (integer)
    # * :receivers (web sockets and/or channels)
    # * :params (hash)
    # * :no_log (boolean) - Defaults to false
    # * :backtrace (string)
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
          # TODO: send as protocol conform JSON message with code and all params so that client can parse and understand the notification message
          receiver.send("#{type} : #{msg}")
        end
      end

      unless options[:no_log]
        logger.send(type.to_sym, msg + (options[:backtrace] || ''))
      end
    end

    protected

    def logger
      @logger
    end

    private

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
