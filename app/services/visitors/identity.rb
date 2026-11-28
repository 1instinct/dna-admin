module Visitors
  # Finds the contact behind a storefront request: the X-Visitor-Token the widget keeps, and the
  # signed-in user when the request carries a valid Spree token.
  #
  # 1. A token with a contact: that contact. A signed-in user is linked to it when it has no user
  #    yet (and fills a blank email).
  # 1. A contact that belongs to another user (a shared browser after someone else signed in):
  #    the signed-in user's own newest contact instead, or a new one with a new token, so one
  #    person never sees another's conversation.
  # 1. No contact yet: one is made only when create is true (a visit ping, a first message), with
  #    the widget's token when it sent a well-formed one, else a new token.
  #
  # The caller returns contact.visitor_token to the widget, which stores whatever comes back.
  class Identity
    def self.resolve(token:, user:, create:)
      new(token, user).resolve(create: create)
    end

    def initialize(token, user)
      @token = Contact.valid_visitor_token?(token) ? token : nil
      @user = user&.persisted? ? user : nil
    end

    def resolve(create:)
      contact = @token && Contact.find_by(visitor_token: @token)
      return link(contact) if contact && (@user.nil? || contact.user_id.nil? || contact.user_id == @user.id)

      if @user
        own = Contact.where(user_id: @user.id).where.not(visitor_token: nil).order(Arel.sql('last_seen_at DESC NULLS LAST, id DESC')).first
        return own if own
      end
      return unless create

      # A token another user's contact holds is never reused for this one.
      token = contact.nil? && @token ? @token : Contact.generate_visitor_token
      Contact.create!(visitor_token: token, user: @user, email: @user&.email)
    rescue ActiveRecord::RecordNotUnique
      Contact.find_by(visitor_token: token)
    end

    private

    def link(contact)
      return contact unless @user && contact.user_id.nil?

      contact.user = @user
      contact.email = @user.email if contact.email.blank?
      contact.save!
      contact
    end
  end
end
