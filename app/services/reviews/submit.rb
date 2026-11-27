module Reviews
  # Creates or edits a customer's review, then sends it through moderation.
  #
  #   Reviews::Submit.call(reviewable: product, user: user, params: { rating: 5, body: '...' })
  #   Reviews::Submit.call(reviewable: product, review_request: request, params: {...}, source: 'email')
  #   Reviews::Submit.call(reviewable: store, user: user, params: {...})   # store review
  #
  # Who may review: product reviews need an eligible purchase (Reviews::Eligibility), from the
  # signed-in user's orders or from the email link's order. Store reviews need a shipped order.
  # Submitting again for the same product edits the existing review, which goes back through
  # moderation. Raises Reviews::Error (:not_eligible, :forbidden); returns a Result whose review
  # carries validation errors when it couldn't be saved.
  class Submit
    PERMITTED = %i[rating title body display_name attribute_ratings photos locale].freeze
    Result = Struct.new(:review, :created, keyword_init: true) do
      def success?
        review.persisted? && review.errors.empty?
      end
    end

    def self.call(**args)
      new(**args).call
    end

    attr_reader :reviewable, :user, :review_request, :params, :source, :ip, :line_item_id, :settings

    def initialize(reviewable:, params:, user: nil, review_request: nil, source: nil, ip: nil, line_item_id: nil,
                   settings: Spree::ReviewSetting.current)
      @reviewable = reviewable
      @user = user
      @review_request = review_request
      @params = params.to_h.symbolize_keys.slice(*PERMITTED)
      @source = source || (review_request ? 'email' : 'web')
      @ip = ip
      @line_item_id = line_item_id
      @settings = settings
    end

    def call
      raise Reviews::Error, :not_enabled unless settings.enabled
      raise Reviews::Error.new(:forbidden, 'Staff accounts cannot review') if user&.admin?

      order, line_item = purchase!
      review = find_existing(order) || Spree::Review.new(reviewable: reviewable)
      created = review.new_record?
      assign(review, order, line_item)

      # Saved on its own first: photos upload when that save commits. Moderation runs after, so
      # its row lock (which reloads the record, dropping un-uploaded attachments) can't lose them.
      # Until moderation finishes the review is pending, so a failure there leaves it held.
      was_published = review.published?
      # An admin rejected or hid it: an edit goes back to a person, never straight to the page.
      overruled = %w[rejected hidden].include?(review.status_was)
      review.status = 'pending'
      review.moderation_reason = 'manual'
      return Result.new(review: review, created: created) unless review.save

      # An edit of a published review has just left the published set.
      Reviews::RefreshStats.call(reviewable) if was_published
      if overruled
        Reviews::Moderation.hold!(review, 'manual')
      else
        Reviews::Moderation.apply_initial_status!(review, settings: settings)
      end
      Result.new(review: review, created: created)
    end

    private

    def product?
      reviewable.is_a?(Spree::Product)
    end

    def store?
      reviewable.is_a?(Spree::Store)
    end

    # The order (and for products, line item) that proves the purchase.
    def purchase!
      order = review_request&.order
      if product?
        item = Reviews::Eligibility.item(product: reviewable, user: user, order: order, line_item_id: line_item_id)
        raise Reviews::Error.new(:not_eligible, "You can review this once it's shipped to you") unless item

        [item.order, item.line_item]
      elsif store?
        # An edit keeps the order the review was written for.
        order ||= own_store_review&.order || Reviews::Eligibility.latest_shipped_order(user)
        raise Reviews::Error.new(:not_eligible, 'You can review us once an order has shipped') unless order

        [order, nil]
      else
        raise ArgumentError, "can't review a #{reviewable.class.name}"
      end
    end

    def own_store_review
      user && Spree::Review.where(reviewable: reviewable).find_by(user_id: user.id)
    end

    def find_existing(order)
      scope = Spree::Review.where(reviewable: reviewable)
      (user && scope.find_by(user_id: user.id)) || scope.find_by(order_id: order.id)
    end

    def assign(review, order, line_item)
      buyer = user || order.user
      review.assign_attributes(
        rating: params[:rating].presence && Integer(params[:rating], exception: false),
        title: params[:title].to_s.strip.presence,
        body: params[:body].to_s.strip.presence,
        attribute_ratings: attribute_ratings(review),
        display_name: params[:display_name].to_s.strip.presence || review.display_name ||
                      Spree::Review.default_display_name(order: order, user: buyer),
        locale: params[:locale].presence || review.locale,
        user: review.user || user || order.user,
        order: order,
        line_item: line_item,
        variant: line_item&.variant,
        review_request: review.review_request || review_request,
        source: review.source.presence && !review.new_record? ? review.source : source,
        channel: Reviews::Channel.for(order: order, user: buyer),
        verified_purchase: true,
        ip_hash: ip.present? ? Digest::SHA256.hexdigest("review-ip:#{ip}") : review.ip_hash
      )
      review.incentivized = Reviews::AwardPoints.offered?(review.user, reviewable, settings: settings) if review.new_record?
      review.edited_at = Time.current unless review.new_record?
      review.photos.attach(Array(params[:photos]).compact_blank) if params[:photos].present?
    end

    # Only the questions asked about this product (or the store) are kept; others are refused.
    def attribute_ratings(review)
      given = params[:attribute_ratings]
      return review.attribute_ratings || {} if given.nil?

      given = given.to_unsafe_h if given.respond_to?(:to_unsafe_h)
      allowed = (product? ? Spree::ReviewAttribute.for_product(reviewable) : Spree::ReviewAttribute.for_store).pluck(:key)
      given.to_h.each_with_object({}) do |(key, value), out|
        next if value.blank?

        raise Reviews::Error.new(:invalid, "Unknown review question #{key}") unless allowed.include?(key.to_s)

        out[key.to_s] = Integer(value, exception: false) || value
      end
    end
  end
end
