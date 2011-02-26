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
    #
    # Additionally, the message handler must implement one handle_<*m*> method
    # per handled qeemono method *m*. qeemono methods function like protocol actions.
    # Each handle method looks like this:
    #
    # def handle_<*m*>(server_interface, args*)
    #   # ...
    # end
    #
    # Where <*m*> is replaced with the resp. method name.
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

    end
  end
end
