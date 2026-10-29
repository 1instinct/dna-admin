# In-app purchase verification for the App Store and Google Play.
# Configuration comes from ENV (see Iap::Configuration); tests swap it with
# Iap.config = ...
module Iap
  class << self
    def config
      @config ||= Iap::Configuration.from_env
    end

    attr_writer :config

    def reset_config!
      @config = nil
    end
  end
end
