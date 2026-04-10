unless File.respond_to?(:exists?)
  class File
    class << self
      alias_method :exists?, :exist?
    end
  end
end
