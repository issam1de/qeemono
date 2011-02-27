module Qeemono
  class CommonUtils
    def self.backtrace(exception)
      "\n" + exception.to_s + exception.backtrace.map { |line| "\n#{line}" }.join
    end
  end
end
