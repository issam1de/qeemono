#
# (c) 2011, Mark von Zeschau
#


module Qeemono
  module Util
    #
    # This module provides a convenient way to store and access data
    # as thread local variables.
    #
    module ThreadLocalPool

      SEQ_ID_POOL = {} # Key = Current thread id; value = seq_id (Integer)
      WEB_SOCKET_POOL = {} # Key = Current thread id; value = web socket object

      EMPTY_SEQ_ID = :none


      def self.store_seq_id(seq_id)
        if seq_id.is_a?(Integer)
          SEQ_ID_POOL[Thread.current.__id__] = seq_id.to_i
        end
      end

      def self.load_seq_id
        SEQ_ID_POOL[Thread.current.__id__] || EMPTY_SEQ_ID
      end

      def self.delete_seq_id
        SEQ_ID_POOL.delete(Thread.current.__id__)
      end

      # --------------

      def self.store_client_id(ws)
        WEB_SOCKET_POOL[Thread.current.__id__] = ws
      end

      def self.load_client_id
        WEB_SOCKET_POOL[Thread.current.__id__]
      end

      def self.delete_client_id
        WEB_SOCKET_POOL.delete(Thread.current.__id__)
      end

    end
  end
end
