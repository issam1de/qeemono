module Qeemono
  module MessageHandler
    #
    # This is the base class of all message handlers.
    # All message handlers have to subclass it.
    #
    # Actual message handling must not be done here.
    #
    # Every message handler must implement the following action:
    # * handled_methods
    # * name
    # * version (defaults to the current protocol version)
    #
    # Additionally, the message handler must implement one handle_<*m*> method
    # per handled qeemono method *m*. qeemono methods function like protocol
    # actions. Each handle method looks like this:
    #
    # def handle_<*m*>(server_interface, args*)
    #   # ...
    # end
    #
    # Where <*m*> is replaced with the resp. method name.
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
    # Both notify and relay send qeemono-protocol conform messages.
    #
    # Returned values from handle methods are ignored.
    #
    # All message handlers can interact with the qeemono server via the
    # qeemono server interface (qsif).
    #
    class Base

      attr_writer :qsif # The qeemono server interface


      def handled_methods
        []
      end

      def name
        nil
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
