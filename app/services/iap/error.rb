module Iap
  # Every IAP failure carries a stable code the API returns verbatim.
  class Error < StandardError
    HTTP_STATUS = {
      invalid_signature: 422,
      wrong_bundle: 422,
      wrong_environment: 422,
      invalid_payload: 422,
      invalid_platform: 422,
      unknown_product: 422,
      invalid_purchase: 422,
      already_owned_by_other_user: 409,
      account_token_mismatch: 403,
      unauthorized: 401,
      store_unreachable: 503,
      store_not_configured: 503
    }.freeze

    attr_reader :code

    def initialize(code, message = nil)
      @code = code.to_sym
      super(message || @code.to_s.humanize)
    end

    def http_status
      HTTP_STATUS.fetch(code, 422)
    end
  end
end
