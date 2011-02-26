module Qeemono
  #
  # The registration manager for all message handlers.
  #
  class MessageHandlerRegistrationManager

    attr_reader :logger


    def initialize(server_interface)
      @sif = server_interface
      @logger = @sif[:logger]
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
            (@sif[:registered_message_handlers_for_method][method.to_s] ||= []) << message_handler
          end
          message_handler_name = message_handler.name.to_s
          @sif[:registered_message_handlers] << message_handler
          message_handler_names << message_handler_name
          logger.debug "Message handler '#{message_handler_name}' has been registered for methods #{handled_methods_as_strings.inspect}."
        end
      end
      logger.debug "Total amount of registered message handlers: #{@sif[:registered_message_handlers].size}"
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
          @sif[:registered_message_handlers_for_method][method.to_s].delete(message_handler)
          @sif[:registered_message_handlers].delete(message_handler)
        end
        message_handler_names << message_handler.name.to_s
      end
      logger.debug "Unregistered #{message_handler_names.size} message handlers. (Details: #{message_handler_names.inspect})"
      logger.debug "Total amount of registered message handlers: #{@sif[:registered_message_handlers].size}"
    end

    protected

    #
    # Returns true if the message handler is valid; false otherwise.
    #
    def check(message_handler)
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

      if @sif[:registered_message_handlers].include?(message_handler)
        logger.error "Message handler '#{message_handler.name}' is already registered! (Details: #{message_handler})"
        return false
      end

      if !@sif[:registered_message_handlers].select { |mh| mh.name == message_handler.name }.empty?
        logger.error "A message handler with name '#{message_handler.name}' already exists! Names must be unique. (Details: #{message_handler})"
        return false
      end

      return true
    end

  end
end
