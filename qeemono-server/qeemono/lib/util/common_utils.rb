module Qeemono
  module Util
    class CommonUtils

      def self.backtrace(exception)
        return '' if exception.nil?
        "\n" + exception.class.to_s + ": " + exception.to_s + exception.backtrace.map { |line| "\n#{line}" }.join
      end

      def self.non_empty_symbol(s, options = {})
        dots_allowed = options[:special_chars]
        return false if s.nil? || s.to_s.strip.empty? || !s.is_a?(Symbol)
        return false if dots_allowed == false && s.index('.')
        return true
      end

      def self.non_empty_string(s)
        return false if s.nil? || s.to_s.strip.empty? || !s.is_a?(String)
        return true
      end

    end
  end
end
