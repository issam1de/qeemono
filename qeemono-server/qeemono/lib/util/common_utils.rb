module Qeemono
  module Util
    class CommonUtils
      def self.backtrace(exception)
        return '' if exception.nil?
        "\n" + exception.class.to_s + ": " + exception.to_s + exception.backtrace.map { |line| "\n#{line}" }.join
      end
    end
  end
end
