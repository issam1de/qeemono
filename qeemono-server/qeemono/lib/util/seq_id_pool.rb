module Qeemono
  module Util
    #
    # This module provides the means to assign sequence ids to the
    # current thread resp. load a certain sequence id for the current
    # thread.
    #
    module SeqIdPool

      SEQ_ID_POOL = {} # Key = Current thread id; value = seq_id (Integer)
      EMPTY_SEQ_ID = :none


      def self.store(seq_id)
        SEQ_ID_POOL[Thread.current.__id__] = seq_id.to_i
      end

      def self.load
        SEQ_ID_POOL[Thread.current.__id__] || EMPTY_SEQ_ID
      end

      def self.delete
        SEQ_ID_POOL.delete(Thread.current.__id__)
      end

    end
  end
end
