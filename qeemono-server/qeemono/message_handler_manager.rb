module Qeemono
  #
  # The manager for all message handlers.
  #
  class MessageHandlerManager

    def initialize(server_interface, public_server_interface)
      @qsif = server_interface
      @qsif[:message_handler_manager] = self
      @qsif_public = public_server_interface

      @registered_message_handlers_for_method = {} # key = method; value = message handler
      @registered_message_handlers = [] # all registered message handlers
    end

    #
    # Returns message handlers filtered by the given conditions hash.
    #
    # conditions:
    #   * :method - (symbol) - Filters the message handlers to only those
    #                          which are registered for the given method
    #                          name. This condition is mandatory!
    #   * :modules - (array of symbols) - Filters the message handlers to
    #                                     only those which belong to *any* of
    #                                     the given modules or the :core module
    #                                     See the Qeemono::ClientManager#assign_to_modules
    #                                     method for detailed information.
    #
    def message_handlers(conditions = {})
      raise "Condition :method is missing!" if conditions[:method].nil?

      message_handlers = @registered_message_handlers_for_method[conditions[:method].to_sym] || []

      modules = conditions[:modules] || []
      modules = [modules] unless modules.is_a? Array

      version = conditions[:version]

      if modules.empty?
        message_handlers = message_handlers.select { |mh| mh.modules.include?(:core) && mh.version == version }
      else
        message_handlers = message_handlers.select { |mh| ( (mh.modules & modules) != [] || mh.modules.include?(:core) ) && mh.version == version }
      end

      message_handlers
    end

    #
    # Registers the given message handlers (of type Qeemono::MessageHandler::Base).
    #
    # options:
    #   * :context (symbol) - The context the to be registered message handler will run in (TODO: not implemented yet)
    #
    def register(message_handlers, options={})
      message_handler_names = []
      message_handlers = [message_handlers] unless message_handlers.is_a? Array
      message_handlers.each do |message_handler|
        if check(message_handler)
          handled_methods = message_handler.handled_methods || []
          handled_methods = [handled_methods] unless handled_methods.is_a? Array
          handled_methods_as_strings = []
          handled_methods.each do |method|
            handled_methods_as_strings << method.to_s
            (@registered_message_handlers_for_method[method.to_sym] ||= []) << message_handler
          end
          message_handler_name = message_handler.name.to_s
          @registered_message_handlers << message_handler
          message_handler.qsif = @qsif_public # Set the public service interface so that it is available in the message handler
          message_handler_names << message_handler_name
          notify(:type => :debug, :code => 5000, :params => {:message_handler_name => message_handler_name, :handled_methods => handled_methods_as_strings.inspect})
        end
      end
      notify(:type => :debug, :code => 5010, :params => {:amount => @registered_message_handlers.size})
    end

    #
    # Unregisters the given message handlers (of type Qeemono::MessageHandler::Base).
    #
    # options:
    #   * :context (symbol) - The context the to be unregistered message handler runs in (TODO: not implemented yet)
    #
    def unregister(message_handlers, options={})
      message_handler_names = []
      message_handlers = [message_handlers] unless message_handlers.is_a? Array
      message_handlers.each do |message_handler|
        handled_methods = message_handler.handled_methods || []
        handled_methods = [handled_methods] unless handled_methods.is_a? Array
        handled_methods.each do |method|
          @registered_message_handlers_for_method[method.to_sym].delete(message_handler) if @registered_message_handlers_for_method[method.to_sym]
          @registered_message_handlers.delete(message_handler)
        end
        message_handler_names << message_handler.name.to_s
      end
      notify(:type => :debug, :code => 5020, :params => {:amount => message_handler_names.size, :message_handler_names => message_handler_names.inspect})
      notify(:type => :debug, :code => 5030, :params => {:amount => @registered_message_handlers.size})
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

      if !Qeemono::Util::CommonUtils.non_empty_symbol(message_handler.name)
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
        if !Qeemono::Util::CommonUtils.non_empty_symbol(method)
          notify(:type => :error, :code => 5130, :params => {:message_handler_name => message_handler.name, :clazz => message_handler.class})
          return false
        end
      end

      if @registered_message_handlers.include?(message_handler)
        notify(:type => :error, :code => 5140, :params => {:message_handler_name => message_handler.name, :clazz => message_handler.class})
        return false
      end

      matching_modules = nil
      if !@registered_message_handlers.select { |mh| mh.name == message_handler.name && (matching_modules=(mh.modules & message_handler.modules)) != []  }.empty?
        notify(:type => :error, :code => 5150, :params => {:message_handler_name => message_handler.name, :clazz => message_handler.class, :matching_modules => matching_modules.inspect})
        return false
      end

      if !Qeemono::Util::CommonUtils.non_empty_string(message_handler.version)
        notify(:type => :error, :code => 5160, :params => {:message_handler_name => message_handler.name, :clazz => message_handler.class})
        return false
      end

      if message_handler.modules.nil? || !message_handler.modules.is_a?(Array)
        notify(:type => :error, :code => 5170, :params => {:message_handler_name => message_handler.name, :clazz => message_handler.class})
        return false
      end

      if message_handler.modules.empty?
        notify(:type => :error, :code => 5180, :params => {:message_handler_name => message_handler.name, :clazz => message_handler.class})
        return false
      end

      message_handler.modules.each do |module_name|
        if !Qeemono::Util::CommonUtils.non_empty_symbol(module_name)
          notify(:type => :error, :code => 5190, :params => {:message_handler_name => message_handler.name, :clazz => message_handler.class})
          return false
        end
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
