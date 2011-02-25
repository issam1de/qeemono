module Qeemono
  module MessageHandler
    #
    # This is the base class of all message handlers.
    # All message handlers have to subclass it.
    #
    class Base

      MANDATORY_METHODS = {
        :handled_methods => Array,
        :name => String
      }


      def handled_methods
        []
      end

      def name
        nil
      end

    end
  end
end
