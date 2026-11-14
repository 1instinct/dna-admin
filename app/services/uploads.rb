# Direct uploads (POST /api/v1/uploads): which files a signed-in user may upload straight to
# storage, by content type, extension and size. Settings live on Uploads.config; an app changes
# them with Uploads.configure in a to_prepare block (see config/initializers/uploads.rb).
module Uploads
  class Config
    # rules: { name => { content_types: [...], extensions: [...], max_bytes: Integer } }. A file
    # passes when one rule lists both its content type and its extension and it fits max_bytes.
    # rate_limit: per-user limit on upload slots.
    attr_accessor :rules, :rate_limit

    def initialize
      @rules = {
        audio: {
          content_types: %w[audio/wav audio/x-wav audio/wave audio/vnd.wave audio/aiff audio/x-aiff audio/flac
                            audio/x-flac audio/mpeg audio/mp3],
          extensions: %w[wav wave aif aiff flac mp3],
          max_bytes: 50.megabytes
        },
        image: {
          content_types: %w[image/png image/jpeg image/webp],
          extensions: %w[png jpg jpeg webp],
          max_bytes: 10.megabytes
        },
        text: {
          content_types: %w[application/json text/json text/plain text/x-glsl application/octet-stream],
          extensions: %w[json glsl],
          max_bytes: 256.kilobytes
        }
      }
      @rate_limit = { limit: 300, window: 1.hour }
    end

    # The rule a file falls under, or nil.
    def rule_for(filename, content_type)
      extension = File.extname(filename.to_s).delete_prefix('.').downcase
      type = content_type.to_s.downcase.split(';').first.to_s.strip
      rules.values.detect { |rule| rule[:content_types].include?(type) && rule[:extensions].include?(extension) }
    end
  end

  def self.config
    @config ||= Config.new
  end

  def self.configure(&block)
    configurers << block
    block.call(config)
  end

  # Tests use this to drop settings they changed.
  def self.reset_config!
    @config = nil
    configurers.each { |block| block.call(config) }
  end

  def self.configurers
    @configurers ||= []
  end
end
