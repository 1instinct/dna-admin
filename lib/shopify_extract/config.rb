module ShopifyExtract
  class Config
    attr_reader :api_base, :access_token, :api_version, :locales,
                :output_dir, :max_image_mb, :parallelism

    def initialize(
      api_base:, access_token:, api_version:, locales:,
      output_dir:, max_image_mb:, parallelism:
    )
      @api_base = api_base
      @access_token = access_token
      @api_version = api_version
      @locales = locales
      @output_dir = output_dir
      @max_image_mb = max_image_mb
      @parallelism = parallelism
    end

    def graphql_url
      "#{api_base}/admin/api/#{api_version}/graphql.json"
    end

    def rest_base_url
      "#{api_base}/admin/api/#{api_version}"
    end

    def locale_dir(locale)
      File.join(output_dir, locale)
    end

    def shared_dir
      File.join(output_dir, "shared")
    end

    def meta_dir
      File.join(output_dir, "_meta")
    end
  end
end
