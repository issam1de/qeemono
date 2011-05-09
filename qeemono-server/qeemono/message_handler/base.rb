module Qeemono
  module MessageHandler
    #
    # This is the base class of all message handlers.
    # All message handlers have to subclass it.
    #
    # Message handlers are called either externally by clients via the
    # JSON-based qeemono protocol (in this case the requests are dispatched
    # in the Qeemono::Server#__dispatch_message__ method) or internally via the
    # Qeemono::MessageHandler::Base#dispatch_message method.
    # method. Calling internally means that message handler
    # methods call methods in other message handlers of the same qeemono
    # server.
    #
    # Actual message handling must not be done here.
    #
    # Every message handler defines a set of configuration options which
    # are represented via the following methods. They can either be
    # overridden (in order to statically set the configuration) or be set
    # via the respective setters (in order to dynamically set the
    # configuration). The configuration options are:
    #
    #   * name  [symbol]
    #   * description [String]
    #   * handled_methods  [symbol(s)]
    #   * modules (used to group related message handlers)  [symbol(s)]
    #   * version (defaults to the current protocol version)  [String]
    #
    # Each message handler can only be called (is available) if at least one
    # of its module names is contained in the list of the calling client's
    # module names. Core message handlers belong to the reserved module :core
    # and are always and automatically available for all clients.
    #
    # The fq_name method returns the unique full-qualified name (a symbol)
    # of the message handler object. It is assembled from the first module
    # name in the modules array and the message handler name. This method
    # may not be overridden.
    #
    # Additionally, the message handler must implement exactly one handle_<*m*>
    # method per handled qeemono method *m*. qeemono methods function like protocol
    # actions. Each handle method looks like this:
    #
    # def handle_<*m*>(origin_client_id, <*args*>)
    #   # Your implementation...
    # end
    #
    # Where <*m*> is replaced with the resp. method name. origin_client_id
    # is the client id of the sender of the message and is automatically set
    # by the qeemono framework. <*args*> are the comma separated method
    # parameters to be passed when calling the method.
    #
    # Each handle method must raise a suited exception if the coated
    # action(s) could not be executed successfully. But only use exceptions
    # when appropriate.
    #
    # Use the Qeemono::Notificator#notify method to send formatted information
    # to the server, other clients, and/or channels. This information can be
    # incident reports, arbitrary feedback, debug, or just normal information.
    # See Qeemono::Notificator#notify for more details.
    #
    # With the Qeemono::Notificator#relay method you send messages to clients
    # and/or channels. See Qeemono::Notificator#relay for more details.
    #
    # Both 'notify' and 'relay' send qeemono-protocol conform messages.
    #
    # Returned values from handle methods are ignored.
    #
    # All message handlers can interact with the qeemono server via the
    # qeemono server interface (qsif) which is available for all message
    # handlers via the qsif method.
    #
    class Base

      attr_reader :qsif # The qeemono server interface

      VENDOR_MESSAGE_HANDLER_MODULE_PREFIX = "Qeemono::MessageHandler::Vendor::"
      VENDOR_MESSAGE_HANDLER_PATH_PREFIX = "qeemono/message_handler/vendor/"

      attr_accessor :name, :description, :handled_methods, :modules, :version


      def initialize(attrs = {})
        @name = attrs[:name] || nil
        @description = attrs[:description] || nil
        @handled_methods = attrs[:handled_methods] || []
        @modules = attrs[:modules] || []
        @version = attrs[:version] || Qeemono::Notificator::PROTOCOL_VERSION
      end

      def qsif=(qsif)
        @qsif = qsif if @qsif.nil? # Only if not already set
      end

      # Do not override this method!
      def fq_name
        # It's ok to just take the first module since all
        # module/name pairs are always unique and there is
        # always at least one module in the array...
        "#{modules.first}##{name}".to_sym
      end

      protected

      def dispatch_message(message_hash)
        @qsif[:server].dispatch_message(message_hash)
      end

      def notify(*args)
        @qsif[:notificator].notify(*args)
      end

      def relay(*args)
        @qsif[:notificator].relay(*args)
      end

    end
  end
end
