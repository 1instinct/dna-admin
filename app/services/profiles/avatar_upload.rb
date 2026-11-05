require "image_processing/mini_magick"

module Profiles
  # Validates an uploaded avatar and stores a server-side re-encode: square JPEG of
  # Profiles.config.avatar_size px, auto-oriented, all metadata (EXIF, GPS, comments) stripped.
  # The client's original is never stored, so it can never be served.
  #
  #   Profiles::AvatarUpload.call(profile, uploaded_file) # => profile (saved)
  #
  # Raises Profiles::AvatarUpload::Error with #status 413 (too large), 415 (not jpeg/png/webp)
  # or 422 (missing or unreadable).
  class AvatarUpload
    class Error < StandardError
      attr_reader :status

      def initialize(message, status)
        super(message)
        @status = status
      end
    end

    # Refused before anything decodes the image (read from the file header).
    MAX_PIXELS = 16_000_000
    # Passed on every ImageMagick command, so a crafted file can't exhaust a dyno. Past memory and
    # map ImageMagick spills to disk, then fails; rescued below as an unreadable image.
    MAGICK_LIMITS = { memory: '128MiB', map: '256MiB', disk: '512MiB', time: '30' }.freeze

    def self.call(profile, upload)
      new(profile, upload).call
    end

    def initialize(profile, upload)
      @profile = profile
      @upload = upload
      @config = Profiles.config
    end

    def call
      check_upload!
      processed = process!
      begin
        @profile.avatar.attach(io: File.open(processed.path), filename: 'avatar.jpg', content_type: 'image/jpeg')
        @profile.save! if @profile.new_record? || @profile.changed?
        raise ActiveRecord::RecordInvalid, @profile unless @profile.errors.empty?
      ensure
        processed.close!
      end
      @profile
    end

    private

    def check_upload!
      unless @upload.respond_to?(:tempfile) || @upload.respond_to?(:path)
        raise Error.new('avatar must be an image file', 422)
      end
      raise Error.new("avatar must be at most #{@config.avatar_max_bytes / 1.megabyte} MB", 413) if @upload.size > @config.avatar_max_bytes

      detected = Marcel::MimeType.for(Pathname.new(path))
      return if @config.avatar_content_types.include?(detected)

      declared = @upload.respond_to?(:content_type) ? @upload.content_type.to_s : ''
      if detected.start_with?('image/') || !@config.avatar_content_types.include?(declared)
        raise Error.new('avatar must be a JPEG, PNG or WebP image', 415)
      end

      raise Error.new("avatar couldn't be read as an image", 422)
    end

    def process!
      width, height = header_dimensions
      raise Error.new("avatar couldn't be read as an image", 422) if width.to_i * height.to_i > MAX_PIXELS

      size = @config.avatar_size
      ImageProcessing::MiniMagick
        .source(path)
        .loader(page: 0)
        .limits(MAGICK_LIMITS)
        .resize_to_fill(size, size)
        .strip
        .convert('jpg')
        .saver(quality: 85)
        .call
    rescue MiniMagick::Error, MiniMagick::Invalid, ImageProcessing::Error => e
      Rails.logger.info("[profiles] avatar processing failed: #{e.class}")
      raise Error.new("avatar couldn't be read as an image", 422)
    end

    # Width and height of the first frame. -ping reads the header and stops, where a plain
    # identify (MiniMagick::Image#dimensions) decodes every pixel first.
    def header_dimensions
      output = MiniMagick::Tool::Identify.new do |identify|
        MAGICK_LIMITS.each { |resource, value| identify.limit(resource.to_s, value) }
        identify.ping
        identify.format('%w %h')
        identify << "#{path}[0]"
      end
      output.split.first(2).map(&:to_i)
    end

    def path
      @upload.respond_to?(:tempfile) ? @upload.tempfile.path : @upload.path
    end
  end
end
