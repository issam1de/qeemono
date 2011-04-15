class String
  #
  # Taken from Rails code
  #
  def starts_with?(prefix)
    prefix = prefix.to_s
    self[0, prefix.length] == prefix
  end

  #
  # Taken from Rails code
  #
  def ends_with?(suffix)
    suffix.respond_to?(:to_str) && self[-suffix.length, suffix.length] == suffix
  end
end
