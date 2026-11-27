# Admin data types the Spree Admin Native app shows under More (spree_admin_native 0.4,
# SpreeAdminNative.resources): generic list, detail and edit screens plus member actions, from
# GET /api/admin_native/v1/resources. A type whose model or table is missing is left out, so forks
# that drop a feature keep this file as it is; a fork adds its own types in its own initializer.
#
# Writes follow the Rails admin: a field is writable only when the admin controller permits it,
# and create / update / delete are off where the admin has no such action (or needs an upload or
# a third-party call the app can't make). Member actions call the same services and model methods
# as the admin controllers, with the same conditions. Secret-looking columns are never exposed by
# the gem; stream keys, raw store payloads and device tokens are left out here as well.
#
# Foreign keys to types registered here are :reference fields; keys to Spree's own records (users,
# products, variants, orders, stores) are plain ids, since the app shows those on its own screens.

Rails.application.config.to_prepare do
  next unless defined?(SpreeAdminNative) && SpreeAdminNative.respond_to?(:resources)

  resources = SpreeAdminNative.resources
  read_only = ->(r) { r.actions create: false, update: false, destroy: false }
  user_class = Spree.user_class(constantize: false)
  # Option lists come from the models' constants; nil when the model isn't in this install (the
  # type is then left out anyway), so a missing model never breaks boot.
  options = ->(constant) { constant.safe_constantize }

  # --- Storefront ----------------------------------------------------------------------------

  resources.register 'menu_locations' do |r|
    r.model 'MenuLocation'
    r.label 'Menu locations'
    r.group 'Storefront'
    r.icon 'list.bullet.rectangle'
    r.title :title
    r.subtitle :location
    r.list :title, :location, :is_visible
    r.search :title, :location
    r.filter :is_visible
    r.order :created_at, :desc
    r.field :title, :string
    r.field :location, :string
    r.field :is_visible, :boolean, label: 'Visible'
    r.field :created_at
    r.field :updated_at
  end

  resources.register 'menu_items' do |r|
    r.model 'MenuItem'
    r.label 'Menu items'
    r.group 'Storefront'
    r.icon 'list.bullet.indent'
    r.title :name
    r.subtitle :url
    r.list :name, :url, :menu_location_id, :position
    r.search :name, :url
    r.order :position, :asc
    r.field :name, :string
    r.field :url, :url
    r.field :menu_location_id, :reference, resource: 'menu_locations', label: 'Menu'
    r.field :parent_id, :reference, resource: 'menu_items', label: 'Parent item'
    r.field :position, :integer
    r.field :item_class, :string, label: 'Item class'
    r.field :item_id, :string, label: 'Item id'
    r.field :item_target, :string, label: 'Link target'
    # Not in the admin's permitted params.
    r.field :is_visible, :boolean, label: 'Visible', readonly: true
    r.field :created_at
    r.field :updated_at
    # Deleting an item with children is refused by MenuItem, as in the admin.
  end

  resources.register 'homepage_sections' do |r|
    r.model 'HomepageSection'
    r.label 'Homepage sections'
    r.group 'Storefront'
    r.icon 'rectangle.stack'
    r.title :title
    r.subtitle :section_type
    r.list :title, :section_type, :position, :is_visible
    r.search :title, :content
    r.filter :section_type, options.call('HomepageSection::SECTION_TYPES')
    r.filter :is_visible
    r.order :position, :asc
    r.field :title, :string
    r.field :section_type, :enum, options: options.call('HomepageSection::SECTION_TYPES'), label: 'Type'
    r.field :content, :text
    r.field :position, :integer, hint: 'Left blank, the section goes last.'
    r.field :is_visible, :boolean, label: 'Visible'
    r.field :settings, :json,
            hint: 'Announcement bar: message, cta_label, cta_href, dismissible, starts_at, ends_at. ' \
                  'App links: ios_url, android_url. Links must start with http:// or https://.'
    r.field :created_at
    r.field :updated_at
  end

  resources.register 'app_settings' do |r|
    r.model 'AppSetting'
    r.label 'App versions'
    r.group 'Storefront'
    r.icon 'iphone.and.arrow.forward'
    r.title :version
    r.subtitle :platform
    r.list :version, :platform, :build, :updated_at
    r.filter :platform, options.call('AppSetting::PLATFORMS')
    r.order :updated_at, :desc
    r.field :name, :string, label: 'Bundle id'
    r.field :platform, :enum, options: options.call('AppSetting::PLATFORMS')
    r.field :version, :string, label: 'Minimum version', hint: 'Users below it are asked to update.'
    r.field :build, :string
    r.field :allow_ahead_of_store, :boolean, label: 'Allow ahead of the App Store',
                                             hint: 'Save an iOS minimum the App Store does not serve yet.'
    r.field :created_at
    r.field :updated_at
    # The admin adds and deletes gates; it doesn't edit them.
    r.actions update: false
  end

  resources.register 'admin_theme' do |r|
    r.model 'AdminTheme'
    r.label 'Admin theme'
    r.group 'Storefront'
    r.icon 'paintpalette'
    r.title :brand_name
    r.list :brand_name, :color_mode, :primary_color
    r.field :brand_name, :string
    r.field :logo, :image
    r.field :favicon, :image
    r.field :primary_color, :color
    r.field :secondary_color, :color
    r.field :surface_color, :color
    r.field :background_color, :color
    r.field :text_color, :color
    r.field :sidebar_color, :color
    r.field :border_radius, :string, hint: 'In pixels, e.g. 8px.'
    r.field :font_family, :enum, options: options.call('AdminTheme::FONT_PRESETS')
    r.field :color_mode, :enum, options: %w[light dark system]
    r.field :enable_animations, :boolean
    r.field :custom_css, :text, label: 'Custom CSS'
    r.field :updated_at
    # One row, edited in place (Spree::Admin::ThemeController).
    r.actions create: false, destroy: false
  end

  resources.register 'pages' do |r|
    r.model 'Spree::Page'
    r.label 'Pages'
    r.group 'Storefront'
    r.icon 'doc.richtext'
    r.title :title
    r.subtitle :slug
    r.list :title, :slug, :visible
    r.search :title, :slug
    r.filter :visible
    r.order :position, :asc
    r.field :title, :string
    r.field :slug, :string, hint: 'Starts with a slash; not needed for a foreign link.'
    r.field :body, :text
    r.field :foreign_link, :url
    r.field :visible, :boolean
    r.field :position, :integer
    r.field :show_in_header, :boolean
    r.field :show_in_footer, :boolean
    r.field :show_in_sidebar, :boolean
    r.field :layout, :string
    r.field :render_layout_as_partial, :boolean
    r.field :meta_title, :string
    r.field :meta_description, :string
    r.field :meta_keywords, :string
    r.field :created_at
    r.field :updated_at
  end

  # --- Engagement ----------------------------------------------------------------------------

  resources.register 'push_notifications' do |r|
    r.model 'PushNotification'
    r.label 'Push notifications'
    r.group 'Engagement'
    r.icon 'bell.badge'
    r.title :title
    r.subtitle :status
    r.list :title, :status, :target, :sent_count, :created_at
    r.search :title, :body
    r.filter :status, %w[draft sent failed]
    r.filter :notification_type, %w[custom product order promo]
    r.order :created_at, :desc
    r.field :title, :string
    r.field :body, :text
    r.field :notification_type, :enum, options: %w[custom product order promo], label: 'Type'
    r.field :target, :enum, options: %w[all user], hint: 'All devices, or one user (set the user id).'
    r.field :target_user_id, :integer, label: 'User id'
    r.field :data, :json, hint: 'Optional: screen, promoCode.'
    r.field :status, :enum, options: %w[draft sent failed], readonly: true
    r.field :sent_count, :integer, readonly: true
    r.field :error_count, :integer, readonly: true
    r.field :errors_log, :text, readonly: true, label: 'Errors'
    r.field :sent_by_id, :integer, readonly: true, label: 'Sent by (user id)'
    r.field :created_at
    r.field :updated_at
    # The app creates drafts and sends them with Send now; a sent notification can't be changed or
    # deleted (PushNotification refuses it).
    r.action :deliver, label: 'Send now', confirm: 'Send this notification now?', if: ->(n) { n.draft? } do |notification, admin|
      notification.deliver!(sent_by: admin)
      if notification.error_count.to_i.positive?
        "Sent to #{notification.sent_count} device(s) with #{notification.error_count} error(s)."
      else
        "Sent to #{notification.sent_count} device(s)."
      end
    end
  end

  resources.register 'push_subscriptions' do |r|
    r.model 'PushSubscription'
    r.label 'Push devices'
    r.group 'Engagement'
    r.icon 'iphone.radiowaves.left.and.right'
    r.title :device_name
    r.subtitle :platform
    r.list :device_name, :platform, :enabled, :user_id
    r.search :device_name
    r.filter :platform, %w[ios android]
    r.filter :enabled
    r.order :created_at, :desc
    # The push token is never shown.
    r.fields :auto, except: %i[token]
    r.field :user_id, :integer, label: 'User id'
    read_only.call(r)
  end

  resources.register 'live_streams' do |r|
    r.model 'LiveStream'
    r.label 'Live streams'
    r.group 'Engagement'
    r.icon 'video'
    r.title :title
    r.subtitle :status
    r.list :title, :status, :start_date, :is_active
    r.search :title, :description
    r.filter :is_active
    r.order :created_at, :desc
    r.field :title, :string
    r.field :description, :text
    r.field :start_date, :datetime
    r.field :is_active, :boolean, label: 'Active'
    r.field :actor_id, :integer, label: 'Host (user id)'
    # Set from Mux when the stream is created or refreshed in the admin; the stream key is left out.
    r.field :status, :string, readonly: true
    r.field :stream_url, :url, readonly: true
    r.field :stream_id, :string, readonly: true
    r.field :playback_ids, :readonly, label: 'Playback ids'
    r.field :thread_table_id, :reference, resource: 'threads', label: 'Thread', readonly: true
    r.field :created_at
    r.field :updated_at
    # Creating and deleting a stream go through Mux in the admin.
    r.actions create: false, destroy: false
  end

  resources.register 'contacts' do |r|
    r.model 'Contact'
    r.label 'Contacts'
    r.group 'Engagement'
    r.icon 'person.crop.rectangle'
    r.title :full_name
    r.subtitle :email
    r.list :full_name, :email, :phone
    r.search :full_name, :email
    r.order :created_at, :desc
    r.field :full_name, :string
    r.field :email, :email
    r.field :phone, :string
    r.field :ip, :string, label: 'IP'
    r.field :actor_id, :integer, label: 'Owner (user id)', required: true
    r.field :created_at
    r.field :updated_at
  end

  resources.register 'messages' do |r|
    r.model 'Message'
    r.label 'Messages'
    r.group 'Engagement'
    r.icon 'bubble.left'
    r.title :message
    r.list :message, :sender_type, :receiver_type, :is_read, :created_at
    r.search :message
    r.filter :is_read
    r.filter :is_received
    r.order :created_at, :desc
    r.field :message, :text
    r.field :sender_type, :enum, options: [user_class, 'Contact']
    r.field :sender_id, :integer
    r.field :receiver_type, :enum, options: [user_class, 'Contact']
    r.field :receiver_id, :integer
    r.field :is_read, :boolean, label: 'Read'
    r.field :is_received, :boolean, label: 'Received'
    r.field :sentiment, :integer
    r.field :thread_table_id, :reference, resource: 'threads', label: 'Thread', readonly: true
    r.field :created_at
    r.field :updated_at
  end

  resources.register 'threads' do |r|
    r.model 'ThreadTable'
    r.label 'Threads'
    r.group 'Engagement'
    r.icon 'bubble.left.and.bubble.right'
    r.list :id, :archived, :stale, :created_at
    r.filter :archived
    r.filter :stale
    r.order :created_at, :desc
    r.field :archived, :boolean
    r.field :stale, :boolean
    r.field :created_at
    r.field :updated_at
  end

  # --- Community and creators ----------------------------------------------------------------

  resources.register 'creator_applications' do |r|
    r.model 'Spree::CreatorApplication'
    r.label 'Creator applications'
    r.group 'Community and creators'
    r.icon 'person.badge.plus'
    r.title :display_name
    r.subtitle :status
    r.list :display_name, :status, :kinds, :created_at
    r.search :display_name
    r.filter :status, %w[pending approved rejected withdrawn]
    r.order :created_at, :desc
    r.fields :auto
    r.field :user_id, :integer, label: 'User id'
    r.field :reviewed_by_id, :integer, label: 'Reviewed by (user id)'
    r.field :kinds, :readonly
    read_only.call(r)
    # Creators::Approver, as in Spree::Admin::CreatorApplicationsController.
    r.action :approve, label: 'Approve', confirm: 'Make this applicant a creator?', if: ->(a) { a.pending? } do |application, admin|
      Creators::Approver.approve!(application, admin)
      "#{application.display_name} is now a creator."
    end
    r.action :reject, label: 'Reject', confirm: 'Reject this application?', destructive: true,
                      if: ->(a) { a.pending? } do |application, admin|
      Creators::Approver.reject!(application, admin)
      'Application rejected.'
    end
  end

  resources.register 'creator_accounts' do |r|
    r.model 'Spree::CreatorAccount'
    r.label 'Creators'
    r.group 'Community and creators'
    r.icon 'person.2'
    r.title :payout_email
    r.subtitle :status
    r.list :user_id, :status, :revenue_share_bps, :payout_email
    r.filter :status, %w[active suspended]
    r.order :created_at, :desc
    r.field :user_id, :integer, label: 'User id', readonly: true
    r.field :status, :enum, options: %w[active suspended], readonly: true
    r.field :revenue_share_bps, :integer, label: 'Revenue share (basis points)', hint: '7000 is 70%.'
    r.field :payout_email, :email
    r.field :payout_notes, :text
    r.field :created_at
    r.field :updated_at
    r.actions create: false, destroy: false
    # As in Spree::Admin::CreatorAccountsController.
    r.action :suspend, label: 'Suspend', confirm: 'Suspend this creator? Their portal closes; their products stay as they are.',
                       destructive: true, if: ->(a) { a.active? } do |account, _admin|
      account.update!(status: 'suspended')
      'Creator suspended.'
    end
    r.action :reinstate, label: 'Reinstate', if: ->(a) { a.suspended? } do |account, _admin|
      unless Creators.creator?(account.user)
        raise 'This user no longer has the creator role; approve a new application instead.'
      end

      account.update!(status: 'active')
      'Creator reinstated.'
    end
    r.action :revoke, label: 'Revoke creator role', confirm: 'Revoke the creator role? The account is suspended and earnings are kept.',
                      destructive: true, if: ->(a) { Creators.creator?(a.user) } do |account, _admin|
      Creators::Approver.revoke!(account.user)
      'Creator role revoked.'
    end
  end

  resources.register 'creator_reviews' do |r|
    r.model 'Spree::Product'
    r.label 'Creator product reviews'
    r.group 'Community and creators'
    r.icon 'checkmark.seal'
    r.title :name
    r.subtitle :review_state
    r.list :name, :creator_id, :submitted_at
    r.search :name
    r.order :submitted_at, :asc
    # The review queue: submitted creator products, as in Spree::Admin::CreatorReviewsController.
    r.scope { |rel| rel.where.not(creator_id: nil).where(review_state: 'submitted') }
    r.field :name, :string, readonly: true
    r.field :creator_id, :integer, label: 'Creator (user id)', readonly: true
    r.field :review_state, :string, readonly: true
    r.field :submitted_at, :datetime, readonly: true
    r.field :available_on, :datetime, readonly: true
    r.field :review_note, :text, label: 'Note for the creator',
                                 hint: 'Required to request changes or reject; shown to the creator.'
    r.actions create: false, destroy: false
    # Creators::Reviewer; the note is the saved review_note.
    r.action :approve, label: 'Approve and publish', confirm: 'Publish this product and put it on sale?' do |product, admin|
      Creators::Reviewer.approve!(product, admin, product.review_note)
      "#{product.name} approved and on sale."
    end
    r.action :request_changes, label: 'Request changes', confirm: 'Send the note back to the creator?',
                               if: ->(p) { p.review_note.present? } do |product, admin|
      Creators::Reviewer.request_changes!(product, admin, product.review_note)
      'Changes requested.'
    end
    r.action :reject, label: 'Reject', confirm: 'Reject this product?', destructive: true,
                      if: ->(p) { p.review_note.present? } do |product, admin|
      Creators::Reviewer.reject!(product, admin, product.review_note)
      'Product rejected.'
    end
  end

  resources.register 'creator_earnings' do |r|
    r.model 'Spree::CreatorEarning'
    r.label 'Creator earnings'
    r.group 'Community and creators'
    r.icon 'chart.line.uptrend.xyaxis'
    r.title :amount
    r.subtitle :state
    r.list :amount, :currency, :state, :creator_account_id, :created_at
    r.filter :state, options.call('Spree::CreatorEarning::STATES')
    r.order :created_at, :desc
    # Pending earnings past their hold become payable when the list is read, as in the admin.
    r.scope { |rel| Spree::CreatorEarning.sweep!; rel }
    r.fields :auto
    r.field :creator_account_id, :reference, resource: 'creator_accounts', label: 'Creator'
    r.field :creator_payout_id, :reference, resource: 'creator_payouts', label: 'Payout'
    read_only.call(r)
    r.action :void, label: 'Void', confirm: 'Void this earning? It will not be paid.', destructive: true,
                    if: ->(e) { e.pending? || e.payable? } do |earning, _admin|
      raise "Earning #{earning.id} is #{earning.state} and cannot be voided." unless earning.void_by_admin!

      'Earning voided.'
    end
  end

  resources.register 'creator_payouts' do |r|
    r.model 'Spree::CreatorPayout'
    r.label 'Creator payouts'
    r.group 'Community and creators'
    r.icon 'banknote'
    r.title :reference
    r.subtitle :amount
    r.list :reference, :amount, :currency, :paid_at
    r.search :reference
    r.order :paid_at, :desc
    r.fields :auto
    r.field :creator_account_id, :reference, resource: 'creator_accounts', label: 'Creator'
    # Recorded in the admin (Creators::Payouts), which settles the payable earnings.
    read_only.call(r)
  end

  resources.register 'content_reports' do |r|
    r.model 'Spree::ContentReport'
    r.label 'Reports'
    r.group 'Community and creators'
    r.icon 'flag'
    r.title :reason
    r.subtitle :status
    r.list :reason, :status, :reportable_type, :created_at
    r.filter :status, options.call('Spree::ContentReport::STATUSES')
    r.filter :reason, options.call('Spree::ContentReport::REASONS')
    r.order :created_at, :desc
    r.fields :auto
    r.field :reporter_id, :integer, label: 'Reporter (user id)'
    r.field :resolved_by_id, :integer, label: 'Resolved by (user id)'
    r.field :reportable_id, :integer, label: 'Reported item id'
    read_only.call(r)

    # As in Spree::Admin::ContentReportsController: each action resolves the report.
    open_report = ->(report) { report.status == 'open' }
    profile_report = ->(report) { open_report.call(report) && report.reportable.is_a?(Spree::UserProfile) }
    resolve = lambda do |report, admin, message|
      report.resolve!(status: 'actioned', by: admin, note: message)
      "#{message}."
    end
    r.action :dismiss, label: 'Dismiss', if: open_report do |report, admin|
      report.resolve!(status: 'dismissed', by: admin)
      'Report dismissed.'
    end
    r.action :hide_profile, label: 'Hide profile', confirm: 'Hide this profile from everyone?', destructive: true,
                            if: profile_report do |report, admin|
      Profiles::Moderation.hide(report.reportable, reason: "Report ##{report.id}: ")
      resolve.call(report, admin, 'Profile hidden')
    end
    r.action :remove_photo, label: 'Remove photo', confirm: 'Remove the profile photo?', destructive: true,
                            if: profile_report do |report, admin|
      Profiles::Moderation.remove_photo(report.reportable)
      resolve.call(report, admin, 'Photo removed')
    end
    r.action :clear_bio, label: 'Clear bio', confirm: 'Clear the profile bio?', destructive: true,
                         if: profile_report do |report, admin|
      Profiles::Moderation.clear_bio(report.reportable)
      resolve.call(report, admin, 'Bio cleared')
    end
    r.action :lock_account, label: 'Lock account', confirm: 'Lock this account? It is signed out everywhere.',
                            destructive: true, if: profile_report do |report, admin|
      Profiles::Moderation.lock(report.reportable.user)
      resolve.call(report, admin, 'Account locked')
    end
  end

  resources.register 'account_locks' do |r|
    r.model user_class
    r.label 'Account locks'
    r.group 'Community and creators'
    r.icon 'lock'
    r.title :email
    r.list :email, :locked_at
    r.search :email
    r.order :created_at, :desc
    # Only what the admin's user page shows for a lock; nothing else of the user.
    r.field :email, :email, readonly: true
    r.field :locked_at, :datetime, readonly: true
    r.field :created_at
    read_only.call(r)
    # Profiles::Moderation, as in Spree::Admin::AccountLocksController; admins can't be locked.
    r.action :lock, label: 'Lock account', confirm: 'Lock this account? It is signed out everywhere.', destructive: true,
                    if: ->(u) { u.locked_at.nil? && !u.admin? } do |user, _admin|
      Profiles::Moderation.lock(user)
      'Account locked.'
    end
    r.action :unlock, label: 'Unlock account', if: ->(u) { u.locked_at.present? } do |user, _admin|
      Profiles::Moderation.unlock(user)
      'Account unlocked.'
    end
  end

  resources.register 'user_profiles' do |r|
    r.model 'Spree::UserProfile'
    r.label 'Profiles'
    r.group 'Community and creators'
    r.icon 'person.crop.circle'
    r.title :handle
    r.subtitle :name
    r.list :handle, :name, :visibility, :hidden_at
    r.search :handle, :name
    r.filter :visibility, options.call('Spree::UserProfile::VISIBILITIES')
    r.order :created_at, :desc
    r.fields :auto
    r.field :avatar, :image, label: 'Photo'
    r.field :user_id, :integer, label: 'User id'
    read_only.call(r)
    # Profiles::Moderation, as in Spree::Admin::UserProfilesController.
    r.action :hide, label: 'Hide profile', confirm: 'Hide this profile from everyone?', destructive: true,
                    if: ->(p) { !p.hidden? } do |profile, _admin|
      Profiles::Moderation.hide(profile, reason: 'Hidden by an admin')
      'Profile hidden.'
    end
    r.action :unhide, label: 'Unhide profile', if: ->(p) { p.hidden? } do |profile, _admin|
      Profiles::Moderation.unhide(profile)
      'Profile visible again.'
    end
  end

  resources.register 'app_feedback' do |r|
    r.model 'AppFeedback'
    r.label 'App feedback'
    r.group 'Community and creators'
    r.icon 'exclamationmark.bubble'
    r.title :message
    r.subtitle :kind
    r.list :kind, :status, :rating, :app_version, :created_at
    r.search :message, :email
    r.filter :status, options.call('AppFeedback::STATUSES')
    r.filter :kind, options.call('AppFeedback::KINDS')
    r.order :created_at, :desc
    r.field :kind, :enum, options: options.call('AppFeedback::KINDS'), readonly: true
    r.field :user_id, :integer, label: 'User id', readonly: true
    {
      rating: :integer, message: :text, email: :email, install_id: :string, moment: :string, platform: :string,
      os_version: :string, device_model: :string, app_version: :string, build_number: :string, channel: :string,
      locale: :string, diagnostics: :json, sentry_event_id: :string
    }.each { |name, type| r.field name, type, readonly: true }
    r.field :screenshot, :image
    r.field :status, :enum, options: options.call('AppFeedback::STATUSES')
    r.field :admin_note, :text
    r.field :created_at
    r.field :updated_at
    # Triage only (status and note), as in Spree::Admin::AppFeedbacksController.
    r.actions create: false, destroy: false
  end

  # --- Commerce extras -----------------------------------------------------------------------

  resources.register 'affiliate_accounts' do |r|
    r.model 'AffiliateAccount'
    r.label 'Affiliates'
    r.group 'Commerce extras'
    r.icon 'link'
    r.title :code
    r.subtitle :status
    r.list :code, :status, :commission_bps, :created_at
    r.search :code
    r.filter :status, options.call('AffiliateAccount::STATUSES')
    r.order :created_at, :desc
    r.field :code, :string, readonly: true
    r.field :status, :enum, options: options.call('AffiliateAccount::STATUSES'), readonly: true
    r.field :user_id, :integer, label: 'User id', readonly: true
    r.field :commission_bps, :integer, label: 'Commission (basis points)', hint: 'Blank uses the default.'
    r.field :cookie_days, :integer
    r.field :payout_email, :email
    r.field :review_note, :text
    r.field :application, :json, readonly: true
    r.field :approved_at, :datetime, readonly: true
    r.field :reviewed_by_id, :integer, label: 'Reviewed by (user id)', readonly: true
    r.field :created_at
    r.field :updated_at
    r.actions create: false, destroy: false
    # As in Spree::Admin::AffiliateAccountsController (the note is the saved review_note).
    r.action :approve, label: 'Approve', confirm: 'Approve this affiliate?', if: ->(a) { a.pending? || a.rejected? } do |account, admin|
      account.update!(reviewed_by_id: admin&.id, status: 'approved', approved_at: Time.current)
      'Affiliate approved.'
    end
    r.action :reject, label: 'Reject', confirm: 'Reject this application?', destructive: true,
                      if: ->(a) { a.pending? } do |account, admin|
      account.update!(reviewed_by_id: admin&.id, status: 'rejected', approved_at: nil)
      'Application rejected.'
    end
    r.action :suspend, label: 'Suspend', confirm: 'Suspend this affiliate? They stop earning.', destructive: true,
                       if: ->(a) { a.approved? } do |account, admin|
      account.update!(reviewed_by_id: admin&.id, status: 'suspended')
      'Affiliate suspended.'
    end
    r.action :reinstate, label: 'Reinstate', if: ->(a) { a.suspended? } do |account, admin|
      account.update!(reviewed_by_id: admin&.id, status: 'approved', approved_at: account.approved_at || Time.current)
      'Affiliate reinstated.'
    end
  end

  resources.register 'affiliate_commissions' do |r|
    r.model 'AffiliateCommission'
    r.label 'Affiliate commissions'
    r.group 'Commerce extras'
    r.icon 'percent'
    r.title :amount
    r.subtitle :state
    r.list :amount, :currency, :state, :affiliate_account_id, :created_at
    r.filter :state, options.call('AffiliateCommission::STATES')
    r.order :created_at, :desc
    # Pending commissions past their hold are approved when the list is read, as in the admin.
    r.scope { |rel| AffiliateCommission.sweep!; rel }
    r.fields :auto
    r.field :affiliate_account_id, :reference, resource: 'affiliate_accounts', label: 'Affiliate'
    r.field :affiliate_payout_id, :reference, resource: 'affiliate_payouts', label: 'Payout'
    r.field :order_id, :integer, label: 'Order id'
    read_only.call(r)
    r.action :void, label: 'Void', confirm: 'Void this commission? It will not be paid.', destructive: true,
                    if: ->(c) { c.pending? || c.approved? } do |commission, _admin|
      commission.update!(state: 'void', void_reason: 'admin')
      'Commission voided.'
    end
  end

  resources.register 'affiliate_payouts' do |r|
    r.model 'AffiliatePayout'
    r.label 'Affiliate payouts'
    r.group 'Commerce extras'
    r.icon 'banknote'
    r.title :reference
    r.subtitle :amount
    r.list :reference, :amount, :currency, :paid_at
    r.search :reference
    r.order :created_at, :desc
    r.fields :auto
    r.field :affiliate_account_id, :reference, resource: 'affiliate_accounts', label: 'Affiliate'
    # Recorded in the admin (Affiliates::Payouts), which settles the approved commissions.
    read_only.call(r)
  end

  resources.register 'digital_assets' do |r|
    r.model 'Spree::DigitalAsset'
    r.label 'Digital assets'
    r.group 'Commerce extras'
    r.icon 'shippingbox'
    r.title :kind
    r.subtitle :status
    r.list :kind, :status, :version, :variant_id, :byte_size
    r.filter :status, options.call('Spree::DigitalAsset::STATUSES')
    r.order :updated_at, :desc
    r.fields :auto
    r.field :variant_id, :integer, label: 'Variant id'
    # Drafts and their files are edited on the product's Digital asset tab in the admin.
    read_only.call(r)
    r.action :publish, label: 'Publish', confirm: "Publish this draft as the variant's next version?",
                       if: ->(a) { a.draft? } do |asset, _admin|
      asset.publish!
      "Published version #{asset.version}."
    end
    r.action :retire, label: 'Retire', confirm: 'Retire this version? Buyers keep what they have.', destructive: true,
                      if: ->(a) { a.published? } do |asset, _admin|
      asset.retire!
      'Version retired.'
    end
  end

  resources.register 'digital_ownerships' do |r|
    r.model 'Spree::DigitalOwnership'
    r.label 'Digital ownerships'
    r.group 'Commerce extras'
    r.icon 'person.crop.circle.badge.checkmark'
    r.title :source
    r.list :user_id, :variant_id, :source, :granted_at, :revoked_at
    r.filter :source, options.call('Spree::DigitalOwnership::SOURCES')
    r.order :granted_at, :desc
    r.fields :auto
    r.field :user_id, :integer, label: 'User id'
    r.field :variant_id, :integer, label: 'Variant id'
    # Granting picks a user and a variant on the admin's user page.
    read_only.call(r)
    r.action :revoke, label: 'Revoke', confirm: 'Revoke this ownership?', destructive: true, if: ->(o) { o.active? } do |ownership, _admin|
      ownership.revoke!('admin_revoked')
      'Ownership revoked.'
    end
  end

  resources.register 'content_assets' do |r|
    r.model 'ContentAsset'
    r.label 'Content images'
    r.group 'Commerce extras'
    r.icon 'photo.on.rectangle'
    r.title :original_filename
    r.subtitle :tag
    r.list :original_filename, :tag, :alt_text, :created_at
    r.search :original_filename, :alt_text, :tag
    r.order :created_at, :desc
    r.field :file, :image
    r.field :alt_text, :string
    r.field :tag, :string
    r.field :original_filename, :string, readonly: true
    r.field :content_type, :string, readonly: true
    r.field :byte_size, :integer, readonly: true
    r.field :created_at
    r.field :updated_at
    # A new image needs an upload, which the generic screens don't do yet.
    r.actions create: false
  end

  resources.register 'entitlements' do |r|
    r.model 'Spree::Entitlement'
    r.label 'Entitlements'
    r.group 'Commerce extras'
    r.icon 'key'
    r.title :key
    r.list :key, :user_id, :active, :expires_at
    r.search :key
    r.filter :active
    r.order :updated_at, :desc
    r.fields :auto
    r.field :user_id, :integer, label: 'User id'
    r.field :iap_transaction_id, :reference, resource: 'iap_transactions', label: 'Purchase'
    # Derived from store transactions (EntitlementResolver); revoking needs a note, in the admin.
    read_only.call(r)
  end

  resources.register 'iap_products' do |r|
    r.model 'Spree::IapProduct'
    r.label 'In-app products'
    r.group 'Commerce extras'
    r.icon 'bag'
    r.title :product_id
    r.subtitle :name
    r.list :product_id, :platform, :kind, :entitlement, :active
    r.search :product_id, :name, :entitlement
    r.filter :platform, options.call('Spree::IapProduct::PLATFORMS')
    r.filter :active
    r.order :platform, :asc
    r.field :platform, :enum, options: options.call('Spree::IapProduct::PLATFORMS')
    r.field :product_id, :string, label: 'Store product id'
    r.field :kind, :enum, options: options.call('Spree::IapProduct::KINDS')
    r.field :entitlement, :string
    r.field :name, :string
    r.field :active, :boolean
    r.field :store_id, :integer, label: 'Store id'
    r.field :created_at
    r.field :updated_at
  end

  resources.register 'iap_transactions' do |r|
    r.model 'Spree::IapTransaction'
    r.label 'In-app purchases'
    r.group 'Commerce extras'
    r.icon 'creditcard'
    r.title :product_id
    r.subtitle :status
    r.list :product_id, :platform, :status, :price, :currency, :purchased_at
    r.search :product_id, :transaction_id, :original_transaction_id
    r.filter :platform, options.call('Spree::IapProduct::PLATFORMS')
    r.filter :status, options.call('Spree::IapTransaction::STATUSES')
    r.filter :environment, options.call('Spree::IapTransaction::ENVIRONMENTS')
    r.order :created_at, :desc
    # The signed store payload is left out; the decoded payload is what the admin shows.
    r.fields :auto, except: %i[signed_payload]
    r.field :user_id, :integer, label: 'User id'
    r.field :iap_product_id, :reference, resource: 'iap_products', label: 'Product'
    # Verified store records: never written from the app. Revoking needs a note, in the admin.
    read_only.call(r)
  end

  resources.register 'product_videos' do |r|
    r.model 'Spree::ProductVideo'
    r.label 'Product videos'
    r.group 'Commerce extras'
    r.icon 'film'
    r.title :alt
    r.list :alt, :product_id, :position
    r.search :alt
    r.order :created_at, :desc
    r.field :poster, :image
    r.field :video_url, :url, readonly: true, label: 'Video'
    r.field :product_id, :integer, label: 'Product id', readonly: true
    r.field :alt, :string, label: 'Alt text'
    r.field :position, :integer
    r.field :video_content_type, :readonly, label: 'Video type'
    r.field :video_byte_size, :readonly, label: 'Video size (bytes)'
    r.field :created_at
    r.field :updated_at
    # A new video needs the video and poster uploads.
    r.actions create: false
  end
end
