module Qeemono
  #
  # The manager for all message handlers.
  #
  class MessageHandlerManager

    def initialize(server_interface, public_server_interface)
      @qsif = server_interface
      @qsif[:message_handler_manager] = self
      @qsif_public = public_server_interface

      @registered_message_handlers_for_method = {} # key = method; value = array of message handler objects (of type Qeemono::MessageHandler::Base)
      @registered_message_handlers = [] # all registered message handlers (of type Qeemono::MessageHandler::Base)
      @registered_message_handlers_by_fq_name = {} # key = full-qualified message handler name (fq_name) as symbol; value = message handler object (of type Qeemono::MessageHandler::Base)
    end

    #
    # Returns message handlers filtered by the given conditions hash.
    #
    # conditions:
    #   * :method - (symbol) - Filters the message handlers to only those
    #                          which are registered for the given method
    #                          name. (This condition is mandatory)
    #   * :name - (symbol) - Filters the message handlers to only those which
    #                        match the given message handler name. (Optional)
    #   * :modules - (array of symbols) - Filters the message handlers to
    #                                     only those which belong to *any* of
    #                                     the given modules or the :core module
    #                                     See the Qeemono::ClientManager#assign_to_modules
    #                                     method for detailed information. (Optional)
    #   * :version - (string) - Filters the message handlers to only those which
    #                           match the given protocol version. (Optional)
    #
    def message_handlers(conditions = {})
      method = conditions[:method]

      raise "Condition :method is missing!" if method.nil?

      message_handlers = @registered_message_handlers_for_method[method.to_sym] || []

      name = conditions[:name]
      modules = conditions[:modules] || []
      modules = [modules] unless modules.is_a? Array
      version = conditions[:version]

      if name
        message_handlers = message_handlers.select { |mh| mh.name == name }
      end

      if modules.empty?
        message_handlers = message_handlers.select { |mh| mh.modules.include?(:core) }
      else
        message_handlers = message_handlers.select { |mh| (mh.modules & modules) != [] || mh.modules.include?(:core) }
      end

      if version
        message_handlers = message_handlers.select { |mh| mh.version == version }
      end

      message_handlers
    end

    #
    # Registers the given message handler objects (of type Qeemono::MessageHandler::Base)
    # on behalf of the client given via client_id (can be nil if performed directly on
    # server-side).
    #
    def register(client_id, message_handlers, options={})
      receiver = receiver(client_id)
      message_handler_names = []
      message_handlers = [message_handlers] unless message_handlers.is_a? Array
      message_handlers.each do |message_handler|
        if check(client_id, message_handler)
          handled_methods = message_handler.handled_methods || []
          handled_methods = [handled_methods] unless handled_methods.is_a? Array
          handled_methods_as_strings = []
          handled_methods.each do |method|
            handled_methods_as_strings << method.to_s
            (@registered_message_handlers_for_method[method.to_sym] ||= []) << message_handler
          end
          message_handler_name = message_handler.name.to_s
          @registered_message_handlers << message_handler
          @registered_message_handlers_by_fq_name[message_handler.fq_name] = message_handler
          message_handler.qsif = @qsif_public # Set the public service interface so that it is available in the message handler
          message_handler_names << message_handler_name
          notify(:type => :debug, :code => 5000, :receivers => receiver, :params => {:message_handler_name => message_handler_name, :handled_methods => handled_methods_as_strings.inspect, :modules => message_handler.modules.inspect, :message_handler_class => message_handler.class, :version => message_handler.version })
        end
      end
      notify(:type => :debug, :code => 5010, :receivers => receiver, :params => {:amount => @registered_message_handlers.size})
    end

    #
    # Unregisters the given message handlers (either objects of type Qeemono::MessageHandler::Base
    # or full-qualified message handler names according to the fq_name method) on behalf of the
    # client given via client_id (can be nil if performed directly on server-side).
    #
    def unregister(client_id, message_handlers, options={})
      # Important internal note for qeemono developers:
      # Clients must not be unassigned from their modules when message handlers,
      # having these modules, are unregistered!
      # The one has nothing to do with the other!

      receiver = receiver(client_id)
      message_handler_names = []
      message_handlers = [message_handlers] unless message_handlers.is_a? Array
      message_handlers.each do |message_handler|
        if !message_handler.is_a?(Qeemono::MessageHandler::Base)
          # If it's not a message handler object it's probably
          # a full-qualified message handler name (see fq_name)...
          message_handler = @registered_message_handlers_by_fq_name[message_handler.to_sym]
        end
        if !message_handler.is_a?(Qeemono::MessageHandler::Base)
          # Still not a message handler object...? => Error
          notify(:type => :error, :code => 5040, :receivers => receiver, :params => {:message_handler => message_handler.inspect})
        else
          handled_methods = message_handler.handled_methods || []
          handled_methods = [handled_methods] unless handled_methods.is_a? Array
          handled_methods.each do |method|
            @registered_message_handlers_for_method[method.to_sym].delete(message_handler) if @registered_message_handlers_for_method[method.to_sym]
            @registered_message_handlers.delete(message_handler)
            @registered_message_handlers_by_fq_name.delete(message_handler.fq_name)
          end
          message_handler_names << message_handler.name.to_s
        end
      end
      notify(:type => :debug, :code => 5020, :receivers => receiver, :params => {:amount => message_handler_names.size, :message_handler_names => message_handler_names.inspect})
      notify(:type => :debug, :code => 5030, :receivers => receiver, :params => {:amount => @registered_message_handlers.size})
    end

    protected

    #
    # Returns true if the message handler is valid; false otherwise.
    # client_id is the client who has initially performed the register
    # resp. unregister call.
    #
    def check(client_id, message_handler)
      receiver = receiver(client_id)

      if !message_handler.is_a?(Qeemono::MessageHandler::Base)
        notify(:type => :error, :code => 5100, :receivers => receiver, :params => {:parent_class => Qeemono::MessageHandler::Base.to_s, :clazz => message_handler.class})
        return false
      end

      if !Qeemono::Util::CommonUtils.non_empty_symbol(message_handler.name, :dots_allowed => false)
        notify(:type => :error, :code => 5110, :receivers => receiver, :params => {:clazz => message_handler.class})
        return false
      end

      if !Qeemono::Util::CommonUtils.non_empty_string(message_handler.description)
        notify(:type => :error, :code => 5111, :receivers => receiver, :params => {:clazz => message_handler.class})
        return false
      end

      handled_methods = message_handler.handled_methods || []
      handled_methods = [handled_methods] unless handled_methods.is_a? Array
      if handled_methods.empty?
        notify(:type => :error, :code => 5120, :receivers => receiver, :params => {:message_handler_name => message_handler.name, :clazz => message_handler.class})
        return false
      end

      handled_methods.each do |method|
        if !Qeemono::Util::CommonUtils.non_empty_symbol(method)
          notify(:type => :error, :code => 5130, :receivers => receiver, :params => {:message_handler_name => message_handler.name, :clazz => message_handler.class})
          return false
        end
      end

      if @registered_message_handlers.include?(message_handler)
        notify(:type => :error, :code => 5140, :receivers => receiver, :params => {:message_handler_name => message_handler.name, :message_handler_class => message_handler.class, :version => message_handler.version})
        return false
      end

      matching_modules = nil
      if !@registered_message_handlers.select { |mh| mh.name == message_handler.name && (matching_modules=(mh.modules & message_handler.modules)) != [] && mh.version == message_handler.version }.empty?
        # Check if name is unique per module and version...
        notify(:type => :error, :code => 5150, :receivers => receiver, :params => {:message_handler_name => message_handler.name, :message_handler_class => message_handler.class, :matching_modules => matching_modules.inspect, :version => message_handler.version})
        return false
      end

      if message_handler.modules.nil? || !message_handler.modules.is_a?(Array)
        notify(:type => :error, :code => 5170, :receivers => receiver, :params => {:message_handler_name => message_handler.name, :clazz => message_handler.class})
        return false
      end

      if message_handler.modules.empty?
        notify(:type => :error, :code => 5180, :receivers => receiver, :params => {:message_handler_name => message_handler.name, :clazz => message_handler.class})
        return false
      end

      message_handler.modules.each do |module_name|
        if !Qeemono::Util::CommonUtils.non_empty_symbol(module_name)
          notify(:type => :error, :code => 5190, :receivers => receiver, :params => {:message_handler_name => message_handler.name, :clazz => message_handler.class})
          return false
        end
      end

      if !Qeemono::Util::CommonUtils.non_empty_string(message_handler.version)
        notify(:type => :error, :code => 5160, :receivers => receiver, :params => {:message_handler_name => message_handler.name, :clazz => message_handler.class})
        return false
      end

      return true
    end

    private

    def receiver(client_id)
      if client_id
        receiver = @qsif[:client_manager].web_socket(:client_id => client_id)
      else
        receiver = nil
      end
      return receiver
    end

    def logger
      @qsif[:logger]
    end

    def notify(*args)
      @qsif[:notificator].notify(*args)
    end

  end
end
