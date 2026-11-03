module Profiles
  # JSON for profiles. Never includes email, real names, user ids or addresses.
  #
  #   Profiles::Presenter.new(profile, viewer: user_or_nil, base_url: request.base_url)
  #     .public_json   # what anyone sees (private profiles: handle, name, avatar, visibility, viewer)
  #     .own_json      # the owner's editable view
  #     .identity_json # { handle, name, avatar } for lists
  class Presenter
    attr_reader :profile, :viewer, :base_url

    def initialize(profile, viewer: nil, base_url: nil)
      @profile = profile
      @viewer = viewer&.persisted? ? viewer : nil
      @base_url = base_url
    end

    def user
      profile.user
    end

    def public_json
      return private_json unless profile.public_visibility?

      {
        handle: profile.handle,
        name: profile.name,
        bio: profile.bio,
        website: profile.website,
        avatar: avatar,
        links: profile.links || {},
        is_creator: creator?,
        joined: joined,
        visibility: profile.visibility,
        counts: counts,
        viewer: viewer_state,
        sections: sections,
        favorites: favorites
      }
    end

    def own_json
      {
        handle: profile.handle,
        name: profile.name,
        bio: profile.bio,
        website: profile.website,
        avatar: avatar,
        links: profile.links || {},
        is_creator: creator?,
        joined: joined,
        visibility: profile.visibility,
        counts: counts,
        hidden: profile.hidden?,
        handle_changeable_at: profile.handle_changeable_at&.iso8601
      }
    end

    def identity_json
      { handle: profile.handle, name: profile.name, avatar: avatar }
    end

    def avatar
      if profile.avatar.attached? && profile.avatar.blob.persisted?
        Profiles.config.avatar_variants.keys.index_with { |size| variant_url(profile.avatar_variant(size)) }
      else
        fallback = Profiles.config.avatar_fallback&.call(user)
        Profiles.config.avatar_variants.keys.index_with { fallback } if Profiles.config.avatar_url_allowed?(fallback)
      end
    end

    private

    def private_json
      {
        handle: profile.handle,
        name: profile.name,
        avatar: avatar,
        visibility: profile.visibility,
        viewer: viewer_state
      }
    end

    def creator?
      user.respond_to?(:is_creator) ? user.is_creator == true : false
    end

    def joined
      user&.created_at&.utc&.strftime('%Y-%m')
    end

    def counts
      return { followers: 0, following: 0 } unless user&.id

      {
        followers: UserFollow.where(following_id: user.id).count,
        following: UserFollow.where(follower_id: user.id).count
      }
    end

    def viewer_state
      is_self = viewer.present? && user.present? && viewer.id == user.id
      following = viewer.present? && !is_self && UserFollow.where(follower_id: viewer.id, following_id: user.id).exists?
      { is_self: is_self, following: following }
    end

    # Content blocks this profile has, in order. The app renders the keys it knows.
    def sections
      list = []
      list << 'favorites' if favorites.any?
      list
    end

    def favorites
      @favorites ||= begin
        rows = user ? public_favorites : []
        rows.map { |fav| favorite_json(fav) }.compact.uniq { |f| f[:product_id] }
      end
    end

    def public_favorites
      user.favorites.public_favorites.recent
          .joins(variant: :product).merge(Spree::Product.not_deleted)
          .includes(variant: { product: { master: :images } })
          .limit(Profiles.config.favorites_limit)
    end

    def favorite_json(fav)
      variant = fav.variant
      product = variant&.product
      return unless product

      price = variant.price || product.price
      {
        product_id: product.id,
        slug: product.slug,
        name: product.name,
        price: price ? format('%.2f', price) : nil,
        image: product_image(product, variant)
      }
    end

    def product_image(product, variant)
      image = variant.images.first || product.master.images.first
      return unless image&.attachment&.attached?

      path = image.style(:product)&.dig(:url)
      path && base_url ? "#{base_url}#{path}" : path
    rescue StandardError
      nil
    end

    def variant_url(variant)
      return unless variant

      if base_url
        Rails.application.routes.url_helpers.rails_representation_url(variant, host: base_url)
      else
        Rails.application.routes.url_helpers.rails_representation_path(variant, only_path: true)
      end
    end
  end
end
