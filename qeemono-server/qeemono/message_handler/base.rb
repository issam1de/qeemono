module Qeemono
  module MessageHandler
    #
    # This is the base class of all message handlers.
    # All message handlers have to subclass it.
    #
    # Actual message handling must not be done here.
    #
    # Every message handler must implement the following methods:
    #   * name  [symbol]
    #   * handled_methods  [symbol(s)]
    #   * modules (used to group related message handlers)  [symbol(s)]
    #   * version (defaults to the current protocol version)  [String]
    #
    # Each message handler can only be called (is available) if at least one
    # of its module names is contained in the list of the calling client's
    # module names. Core message handlers belong to the reserved module :core
    # and are always and automatically available for all clients.
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


      def qsif=(qsif)
        @qsif = qsif if @qsif.nil? # Only if not already set
      end

      def name
        nil
      end

      def handled_methods
        []
      end

      def modules
        []
      end

      def version
        Qeemono::Notificator::PROTOCOL_VERSION
      end

      protected

      def notify(*args)
        @qsif[:notificator].notify(*args)
      end

      def relay(*args)
        @qsif[:notificator].relay(*args)
      end

    end
  end
end
