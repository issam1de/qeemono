module StringUtils
  #
  # Taken from Rails code
  #
  def self.camelize(lower_case_and_underscored_word, first_letter_in_uppercase = true)
    if first_letter_in_uppercase
      lower_case_and_underscored_word.to_s.gsub(/\/(.?)/) { "::#{$1.upcase}" }.gsub(/(?:^|_)(.)/) { $1.upcase }
    else
      lower_case_and_underscored_word.to_s[0].chr.downcase + camelize(lower_case_and_underscored_word)[1..-1]
    end
  end

  #
  # Taken from Rails code
  #
  def self.classify(table_name)
    # strip out any leading schema name
    camelize(table_name.to_s.sub(/.*\./, ''))
  end
end
