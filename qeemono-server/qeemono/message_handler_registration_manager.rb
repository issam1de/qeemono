module Qeemono
  #
  # The registration manager for all message handlers.
  #
  class MessageHandlerRegistrationManager

    def initialize(server_interface)
      @qsif = server_interface
      @qsif[:message_handler_registration_manager] = self
    end

    #
    # Registers the given message handlers (of type Qeemono::MessageHandler::Base).
    #
    def register(message_handlers)
      message_handler_names = []
      message_handlers = [message_handlers] unless message_handlers.is_a? Array
      message_handlers.each do |message_handler|
        if check(message_handler)
          handled_methods = message_handler.handled_methods || []
          handled_methods = [handled_methods] unless handled_methods.is_a? Array
          handled_methods_as_strings = []
          handled_methods.each do |method|
            handled_methods_as_strings << method.to_s
            (@qsif[:registered_message_handlers_for_method][method.to_sym] ||= []) << message_handler
          end
          message_handler_name = message_handler.name.to_s
          @qsif[:registered_message_handlers] << message_handler
          message_handler.qsif = @qsif # Set the service interface so that it is available in the message handler
          message_handler_names << message_handler_name
          notify(:type => :debug, :code => 5000, :params => {:message_handler_name => message_handler_name, :handled_methods => handled_methods_as_strings.inspect})
        end
      end
      notify(:type => :debug, :code => 5010, :params => {:amount => @qsif[:registered_message_handlers].size})
    end

    #
    # Unregisters the given message handlers (of type Qeemono::MessageHandler::Base).
    #
    def unregister(message_handlers)
      message_handler_names = []
      message_handlers = [message_handlers] unless message_handlers.is_a? Array
      message_handlers.each do |message_handler|
        handled_methods = message_handler.handled_methods || []
        handled_methods = [handled_methods] unless handled_methods.is_a? Array
        handled_methods.each do |method|
          @qsif[:registered_message_handlers_for_method][method.to_sym].delete(message_handler) if @qsif[:registered_message_handlers_for_method][method.to_sym]
          @qsif[:registered_message_handlers].delete(message_handler)
        end
        message_handler_names << message_handler.name.to_s
      end
      notify(:type => :debug, :code => 5020, :params => {:amount => message_handler_names.size, :message_handler_names => message_handler_names.inspect})
      notify(:type => :debug, :code => 5030, :params => {:amount => @qsif[:registered_message_handlers].size})
    end

    protected

    #
    # Returns true if the message handler is valid; false otherwise.
    #
    def check(message_handler)
      if !message_handler.is_a?(Qeemono::MessageHandler::Base)
        notify(:type => :error, :code => 5100, :params => {:parent_class => Qeemono::MessageHandler::Base.to_s, :clazz => message_handler.class})
        return false
      end

      if message_handler.name.nil? || message_handler.name.to_s.strip.empty?
        notify(:type => :error, :code => 5110, :params => {:clazz => message_handler.class})
        return false
      end

      handled_methods = message_handler.handled_methods || []
      handled_methods = [handled_methods] unless handled_methods.is_a? Array
      if handled_methods.empty?
        notify(:type => :error, :code => 5120, :params => {:message_handler_name => message_handler.name, :clazz => message_handler.class})
        return false
      end

      handled_methods.each do |method|
        if method.nil? || method.to_s.strip.empty?
          notify(:type => :error, :code => 5130, :params => {:message_handler_name => message_handler.name, :clazz => message_handler.class})
          return false
        end
      end

      if @qsif[:registered_message_handlers].include?(message_handler)
        notify(:type => :error, :code => 5140, :params => {:message_handler_name => message_handler.name, :clazz => message_handler.class})
        return false
      end

      if !@qsif[:registered_message_handlers].select { |mh| mh.name == message_handler.name }.empty?
        notify(:type => :error, :code => 5150, :params => {:message_handler_name => message_handler.name, :clazz => message_handler.class})
        return false
      end

      return true
    end

    private

    def logger
      @qsif[:logger]
    end

    def notify(*args)
      @qsif[:notificator].notify(*args)
    end

  end
end
