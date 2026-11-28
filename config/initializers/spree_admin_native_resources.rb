# Admin data types the Spree Admin Native app shows under More (spree_admin_native 0.5,
# SpreeAdminNative.resources): generic list, detail and edit screens plus member actions, from
# GET /api/admin_native/v1/resources. A type whose model or table is missing is left out, so forks
# that drop a feature keep this file as it is; a fork adds its own types in its own initializer.
#
# Writes follow the Rails admin: a field is writable only when the admin controller permits it,
# and create / update / delete are off where the admin has no such action (or needs an upload or
# a third-party call the app can't make). Member actions call the same services and model methods
# as the admin controllers, with the same conditions, and ask for what the admin's forms ask for
# (a note, a payment reference) as action inputs. Per-record rules (editable_if / deletable_if) let
# the app hide what the models refuse anyway; the model validations stay, for every other client.
# Secret-looking columns are never exposed by the gem; stream keys, raw store payloads and device
# tokens are left out here as well.
#
# Foreign keys are :reference fields: to types registered here, or to the gem's built-in hidden
# lookups for Spree's own records (spree_users, spree_products, spree_variants, spree_orders,
# spree_taxons).
# Image fields are writable (upload with POST resources/uploads, then send the signed_id) only
# where the admin uploads the file as it is; elsewhere they are read-only.
#
# A fork changes one of these types (a column of its own, another action) from its own initializer,
# in any load order; the block runs now if the type is registered and again on every reload:
#
#   SpreeAdminNative.resources.configure('homepage_sections') do |r|
#     r.field :extra_column, :string
#   end
#
# The 0.4-era load hook still runs after each type here is registered, for forks that haven't
# moved to configure yet; it goes away in a later release:
#
#   ActiveSupport.on_load(:spree_admin_native_resource, yield: true) { |r| ... if r.key == '...' }

Rails.application.config.to_prepare do
  next unless defined?(SpreeAdminNative) && SpreeAdminNative.respond_to?(:resources)

  resources = SpreeAdminNative.resources
  register = lambda do |key, &block|
    resources.register(key) do |r|
      block.call(r)
      # Deprecated: forks use SpreeAdminNative.resources.configure(key) now. Kept for one release.
      ActiveSupport.run_load_hooks(:spree_admin_native_resource, r)
    end
  end
  read_only = ->(r) { r.actions create: false, update: false, destroy: false }
  user_class = Spree.user_class(constantize: false)
  # A user id as a reference to the gem's built-in user lookup (the title is the email).
  user_ref = lambda do |r, name, label, **opts|
    r.field name, :reference, resource: 'spree_users', label: label, **opts
  end
  # Money as the admin shows it: "7.00 USD".
  money = ->(amount, currency) { "#{format('%.2f', amount.to_d)} #{currency}" }
  # An optional note action input.
  note_input = lambda do |label = 'Note', name: :note, required: false, hint: nil|
    { name: name, type: :text, label: label, required: required, hint: hint }.compact
  end
  # Option lists come from the models' constants; nil when the model isn't in this install (the
  # type is then left out anyway), so a missing model never breaks boot.
  options = ->(constant) { constant.safe_constantize }

  # --- Storefront ----------------------------------------------------------------------------

  # The menu builder: a tree per menu location (app/services/admin_native/menus.rb).
  register.call('menu_locations') { |r| AdminNative::Menus.locations(r) }
  register.call('menu_items') { |r| AdminNative::Menus.items(r) }

  register.call 'homepage_sections' do |r|
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
    r.field :position, :integer, required: false, hint: 'Left blank, the section goes last.'
    r.field :is_visible, :boolean, label: 'Visible'
    r.field :settings, :json,
            hint: 'Announcement bar: message, cta_label, cta_href, dismissible, starts_at, ends_at. ' \
                  'App links: ios_url, android_url. Links must start with http:// or https://.'
    r.field :created_at
    r.field :updated_at
  end

  register.call 'app_settings' do |r|
    r.model 'AppSetting'
    r.label 'App versions'
    r.group 'Storefront'
    r.icon 'iphone.and.arrow.forward'
    r.title :version
    r.subtitle :platform
    r.list :version, :platform, :build, :updated_at
    r.filter :platform, options.call('AppSetting::PLATFORMS')
    r.order :updated_at, :desc
    # The admin's form prefills the app's bundle id.
    r.field :name, :string, label: 'Bundle id', default: options.call('AppSetting::DEFAULT_NAME')
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

  register.call 'admin_theme' do |r|
    r.model 'AdminTheme'
    r.label 'Admin theme'
    r.group 'Storefront'
    r.icon 'paintpalette'
    r.title :brand_name
    r.list :brand_name, :color_mode, :primary_color
    r.field :brand_name, :string
    # Uploaded as they are, as in the admin (AdminTheme checks type and size); null removes one.
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

  register.call 'pages' do |r|
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

  register.call 'push_notifications' do |r|
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
    r.field :target, :enum, options: %w[all user], hint: 'All devices, or one user (choose the user).'
    user_ref.call(r, :target_user_id, 'User')
    r.field :data, :json, hint: 'Optional: screen, promoCode.'
    r.field :status, :enum, options: %w[draft sent failed], readonly: true
    r.field :sent_count, :integer, readonly: true
    r.field :error_count, :integer, readonly: true
    r.field :errors_log, :text, readonly: true, label: 'Errors'
    user_ref.call(r, :sent_by_id, 'Sent by', readonly: true)
    r.field :created_at
    r.field :updated_at
    # The app creates drafts and sends them with Send now. A sent notification is the send history:
    # PushNotification refuses to change or delete it, and the app doesn't offer it.
    r.editable_if ->(n) { n.draft? }
    r.deletable_if ->(n) { n.draft? }
    # The admin records the admin who creates a notification; Send now records who sent it.
    r.before_save do |notification, admin, op|
      notification.sent_by ||= admin if op == :create
    end
    r.action :deliver, label: 'Send now', confirm: 'Send this notification now?', if: ->(n) { n.draft? } do |notification, admin|
      notification.deliver!(sent_by: admin)
      if notification.error_count.to_i.positive?
        "Sent to #{notification.sent_count} device(s) with #{notification.error_count} error(s)."
      else
        "Sent to #{notification.sent_count} device(s)."
      end
    end
  end

  register.call 'push_subscriptions' do |r|
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
    user_ref.call(r, :user_id, 'User')
    read_only.call(r)
  end

  register.call 'live_streams' do |r|
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
    user_ref.call(r, :actor_id, 'Host')
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

  # Contacts, messages and threads as flat records. The app's Inbox and Visitors screens replace
  # them (Chat::InboxAdapter, Visitors::Adapter), so they are hidden: still registered, as
  # reference targets (a live stream's thread, a message's thread) and for CRUD, but no longer
  # under More.

  register.call 'contacts' do |r|
    r.model 'Contact'
    r.label 'Contacts'
    r.group 'Engagement'
    r.icon 'person.crop.rectangle'
    r.title ->(contact) { contact.display_name || "Contact ##{contact.id}" }
    r.subtitle :email
    r.list :full_name, :email, :phone, :last_seen_at
    r.search :full_name, :name, :email
    r.order :created_at, :desc
    r.field :full_name, :string
    r.field :email, :email
    r.field :phone, :string
    r.field :ip, :string, label: 'IP'
    # actor_id is the admin form's name for the account; user_id follows it (Contact).
    user_ref.call(r, :actor_id, 'Account')
    # Set by the storefront chat.
    r.field :name, :string, label: 'Name in chat', readonly: true
    r.field :email_opt_in, :boolean, label: 'Email replies', readonly: true
    r.field :last_seen_at, :datetime, label: 'Last seen', readonly: true
    r.field :created_at
    r.field :updated_at
    r.hidden
  end

  register.call 'messages' do |r|
    r.model 'Message'
    r.label 'Messages'
    r.group 'Engagement'
    r.icon 'bubble.left'
    r.title :message
    r.list :message, :direction, :sender_type, :receiver_type, :is_read, :created_at
    r.search :message
    r.filter :is_read
    r.filter :is_received
    r.filter :direction, Message::DIRECTIONS
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
    # Set by the chat (Chat::Conversations).
    r.field :direction, :enum, options: Message::DIRECTIONS, readonly: true
    r.field :channel, :string, readonly: true
    user_ref.call(r, :author_id, 'Staff author', readonly: true)
    r.field :read_at, :datetime, readonly: true
    r.field :delivery_status, :string, label: 'Delivery', readonly: true
    r.field :created_at
    r.field :updated_at
    r.hidden
  end

  register.call 'threads' do |r|
    r.model 'ThreadTable'
    r.label 'Threads'
    r.group 'Engagement'
    r.icon 'bubble.left.and.bubble.right'
    r.list :id, :status, :contact_id, :last_message_at, :archived
    r.filter :archived
    r.filter :stale
    r.filter :status, ThreadTable::STATUSES
    r.order :created_at, :desc
    r.field :archived, :boolean
    r.field :stale, :boolean
    # Set by the chat (Chat::Conversations); the inbox changes them.
    r.field :status, :enum, options: ThreadTable::STATUSES, readonly: true
    r.field :channel, :string, readonly: true
    r.field :contact_id, :reference, resource: 'contacts', label: 'Contact', readonly: true
    user_ref.call(r, :assignee_id, 'Assignee', readonly: true)
    r.field :last_message_at, :datetime, label: 'Last message', readonly: true
    r.field :staff_unread_count, :integer, label: 'Unread (staff)', readonly: true
    r.field :created_at
    r.field :updated_at
    r.hidden
  end

  # --- Community and creators ----------------------------------------------------------------

  register.call 'creator_applications' do |r|
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
    user_ref.call(r, :user_id, 'User')
    user_ref.call(r, :reviewed_by_id, 'Reviewed by')
    r.field :kinds, :readonly
    read_only.call(r)
    # Creators::Approver, as in Spree::Admin::CreatorApplicationsController, with its optional note.
    r.action :approve, label: 'Approve', confirm: 'Make this applicant a creator?', if: ->(a) { a.pending? },
                       inputs: [note_input.call('Note for the applicant')] do |application, admin, input|
      Creators::Approver.approve!(application, admin, input[:note])
      "#{application.display_name} is now a creator."
    end
    r.action :reject, label: 'Reject', confirm: 'Reject this application?', destructive: true,
                      if: ->(a) { a.pending? }, inputs: [note_input.call('Note for the applicant')] do |application, admin, input|
      Creators::Approver.reject!(application, admin, input[:note])
      'Application rejected.'
    end
  end

  register.call 'creator_accounts' do |r|
    r.model 'Spree::CreatorAccount'
    r.label 'Creators'
    r.group 'Community and creators'
    r.icon 'person.2'
    r.title ->(account) { account.user&.email || account.payout_email }
    r.subtitle :status
    r.list :user_id, :status, :revenue_share_bps, :payout_email
    r.search :payout_email
    r.filter :status, %w[active suspended]
    r.order :created_at, :desc
    user_ref.call(r, :user_id, 'User', readonly: true)
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
    # Money moves outside the app; recording the payment's reference marks the account's payable
    # earnings in that currency paid (Creators::Payouts, as in Spree::Admin::CreatorPayoutsController).
    payable_earnings = lambda do |account|
      Spree::CreatorEarning.where(creator_account_id: account.id)
                           .where("state = 'payable' OR (state = 'pending' AND payable_at <= ?)", Time.current)
    end
    r.action :record_payout, label: 'Record payout', confirm: 'Record this payout? Every payable earning in the currency is marked paid.',
                             if: ->(a) { payable_earnings.call(a).exists? },
                             inputs: [{ name: :reference, type: :string, required: true, label: 'Payment reference' },
                                      { name: :currency, type: :string, label: 'Currency',
                                        hint: 'Blank pays the first currency with a payable balance.' },
                                      note_input.call] do |account, _admin, input|
      currency = input[:currency].to_s.strip.upcase.presence || Creators::Payouts.payable(account).keys.first ||
                 Spree::Store.default.default_currency.presence || Spree::Config[:currency]
      payout = Creators::Payouts.create!(account: account, reference: input[:reference], note: input[:note], currency: currency)
      "Payout of #{money.call(payout.amount, payout.currency)} recorded."
    end
  end

  register.call 'creator_reviews' do |r|
    r.model 'Spree::Product'
    r.label 'Creator product reviews'
    r.singular 'Product in review'
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
    user_ref.call(r, :creator_id, 'Creator', readonly: true)
    r.field :review_state, :string, readonly: true
    r.field :submitted_at, :datetime, readonly: true
    r.field :available_on, :datetime, readonly: true
    r.field :review_note, :text, label: 'Note for the creator',
                                 hint: 'Saved with each decision and shown to the creator.'
    r.actions create: false, destroy: false
    # Creators::Reviewer with the note from the admin's decision forms: optional to approve (blank
    # clears the saved note, as in the admin), required to request changes or reject.
    creator_note = ->(required) { note_input.call('Note for the creator', required: required) }
    r.action :approve, label: 'Approve and publish', confirm: 'Publish this product and put it on sale?',
                       inputs: [creator_note.call(false)] do |product, admin, input|
      Creators::Reviewer.approve!(product, admin, input[:note])
      "#{product.name} approved and on sale."
    end
    r.action :request_changes, label: 'Request changes', confirm: 'Send the note back to the creator?',
                               inputs: [creator_note.call(true)] do |product, admin, input|
      Creators::Reviewer.request_changes!(product, admin, input[:note])
      'Changes requested.'
    end
    r.action :reject, label: 'Reject', confirm: 'Reject this product?', destructive: true,
                      inputs: [creator_note.call(true)] do |product, admin, input|
      Creators::Reviewer.reject!(product, admin, input[:note])
      'Product rejected.'
    end
  end

  register.call 'creator_earnings' do |r|
    r.model 'Spree::CreatorEarning'
    r.label 'Creator earnings'
    r.group 'Community and creators'
    r.icon 'chart.line.uptrend.xyaxis'
    r.title ->(earning) { money.call(earning.amount, earning.currency) }
    r.subtitle :state
    r.list :amount, :currency, :state, :creator_account_id, :created_at
    r.filter :state, options.call('Spree::CreatorEarning::STATES')
    r.filter :creator_account_id
    r.filter :created_at, :date_range
    r.order :created_at, :desc
    # Pending earnings past their hold become payable when the list is read, as in the admin.
    r.scope { |rel| Spree::CreatorEarning.sweep!; rel }
    r.fields :auto
    r.field :creator_account_id, :reference, resource: 'creator_accounts', label: 'Creator'
    r.field :creator_payout_id, :reference, resource: 'creator_payouts', label: 'Payout'
    r.field :order_id, :reference, resource: 'spree_orders', label: 'Order'
    read_only.call(r)
    r.action :void, label: 'Void', confirm: 'Void this earning? It will not be paid.', destructive: true,
                    if: ->(e) { e.pending? || e.payable? } do |earning, _admin|
      raise "Earning #{earning.id} is #{earning.state} and cannot be voided." unless earning.void_by_admin!

      'Earning voided.'
    end
  end

  register.call 'creator_payouts' do |r|
    r.model 'Spree::CreatorPayout'
    r.label 'Creator payouts'
    r.group 'Community and creators'
    r.icon 'banknote'
    r.title :reference
    r.subtitle ->(payout) { money.call(payout.amount, payout.currency) }
    r.list :reference, :amount, :currency, :paid_at
    r.search :reference
    r.filter :creator_account_id
    r.filter :paid_at, :date_range
    r.order :paid_at, :desc
    r.fields :auto
    r.field :creator_account_id, :reference, resource: 'creator_accounts', label: 'Creator'
    # Recorded with Record payout on the creator (Creators::Payouts), which settles the payable earnings.
    read_only.call(r)
  end

  register.call 'content_reports' do |r|
    r.model 'Spree::ContentReport'
    r.label 'Reports'
    r.group 'Community and creators'
    r.icon 'flag'
    r.title :reason
    r.subtitle :status
    r.list :reason, :status, :reportable_type, :created_at
    r.filter :status, options.call('Spree::ContentReport::STATUSES')
    r.filter :reason, options.call('Spree::ContentReport::REASONS')
    r.filter :created_at, :date_range
    r.order :created_at, :desc
    r.fields :auto
    user_ref.call(r, :reporter_id, 'Reporter')
    user_ref.call(r, :resolved_by_id, 'Resolved by')
    r.field :reportable_id, :integer, label: 'Reported item id'
    read_only.call(r)

    # As in Spree::Admin::ContentReportsController: each action resolves the report, with the
    # admin's optional resolution note.
    open_report = ->(report) { report.status == 'open' }
    profile_report = ->(report) { open_report.call(report) && report.reportable.is_a?(Spree::UserProfile) }
    resolution = [note_input.call('Resolution note')]
    resolve = lambda do |report, admin, message, note|
      report.resolve!(status: 'actioned', by: admin, note: [message, note.to_s.strip.presence].compact.join(': '))
      "#{message}."
    end
    r.action :dismiss, label: 'Dismiss', if: open_report, inputs: resolution do |report, admin, input|
      report.resolve!(status: 'dismissed', by: admin, note: input[:note].to_s.strip.presence)
      'Report dismissed.'
    end
    r.action :hide_profile, label: 'Hide profile', confirm: 'Hide this profile from everyone?', destructive: true,
                            if: profile_report, inputs: resolution do |report, admin, input|
      Profiles::Moderation.hide(report.reportable, reason: "Report ##{report.id}: #{input[:note].to_s.strip}")
      resolve.call(report, admin, 'Profile hidden', input[:note])
    end
    r.action :remove_photo, label: 'Remove photo', confirm: 'Remove the profile photo?', destructive: true,
                            if: profile_report, inputs: resolution do |report, admin, input|
      Profiles::Moderation.remove_photo(report.reportable)
      resolve.call(report, admin, 'Photo removed', input[:note])
    end
    r.action :clear_bio, label: 'Clear bio', confirm: 'Clear the profile bio?', destructive: true,
                         if: profile_report, inputs: resolution do |report, admin, input|
      Profiles::Moderation.clear_bio(report.reportable)
      resolve.call(report, admin, 'Bio cleared', input[:note])
    end
    r.action :lock_account, label: 'Lock account', confirm: 'Lock this account? It is signed out everywhere.',
                            destructive: true, if: profile_report, inputs: resolution do |report, admin, input|
      Profiles::Moderation.lock(report.reportable.user)
      resolve.call(report, admin, 'Account locked', input[:note])
    end
  end

  register.call 'account_locks' do |r|
    r.model user_class
    r.label 'Account locks'
    r.singular 'Account'
    r.group 'Community and creators'
    r.icon 'lock'
    r.title :email
    r.list :email, :locked_at
    r.search :email
    r.filter :locked_at, :presence
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

  register.call 'user_profiles' do |r|
    r.model 'Spree::UserProfile'
    r.label 'Profiles'
    r.group 'Community and creators'
    r.icon 'person.crop.circle'
    r.title :handle
    r.subtitle :name
    r.list :handle, :name, :visibility, :hidden_at
    r.search :handle, :name
    r.filter :visibility, options.call('Spree::UserProfile::VISIBILITIES')
    r.filter :hidden_at, :presence
    r.order :created_at, :desc
    r.fields :auto
    # The admin only removes a photo (Remove photo on a report); it never uploads one.
    r.field :avatar, :image, label: 'Photo', readonly: true
    user_ref.call(r, :user_id, 'User')
    read_only.call(r)
    # Profiles::Moderation, as in Spree::Admin::UserProfilesController, with its optional reason.
    r.action :hide, label: 'Hide profile', confirm: 'Hide this profile from everyone?', destructive: true,
                    if: ->(p) { !p.hidden? },
                    inputs: [{ name: :reason, type: :string, label: 'Reason', default: 'Hidden by an admin' }] do |profile, _admin, input|
      Profiles::Moderation.hide(profile, reason: input[:reason].to_s.strip.presence || 'Hidden by an admin')
      'Profile hidden.'
    end
    r.action :unhide, label: 'Unhide profile', if: ->(p) { p.hidden? } do |profile, _admin|
      Profiles::Moderation.unhide(profile)
      'Profile visible again.'
    end
  end

  register.call 'app_feedback' do |r|
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
    r.filter :created_at, :date_range
    r.order :created_at, :desc
    r.field :kind, :enum, options: options.call('AppFeedback::KINDS'), readonly: true
    user_ref.call(r, :user_id, 'User', readonly: true)
    {
      rating: :integer, message: :text, email: :email, install_id: :string, moment: :string, platform: :string,
      os_version: :string, device_model: :string, app_version: :string, build_number: :string, channel: :string,
      locale: :string, diagnostics: :json, sentry_event_id: :string
    }.each { |name, type| r.field name, type, readonly: true }
    # Sent by the user with the feedback: shown, never replaced.
    r.field :screenshot, :image, readonly: true
    r.field :status, :enum, options: options.call('AppFeedback::STATUSES')
    r.field :admin_note, :text
    r.field :created_at
    r.field :updated_at
    # Triage only (status and note), as in Spree::Admin::AppFeedbacksController.
    r.actions create: false, destroy: false
  end

  # --- Commerce extras -----------------------------------------------------------------------

  register.call 'affiliate_accounts' do |r|
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
    user_ref.call(r, :user_id, 'User', readonly: true)
    r.field :commission_bps, :integer, label: 'Commission (basis points)', hint: 'Blank uses the default.'
    r.field :cookie_days, :integer
    r.field :payout_email, :email
    r.field :review_note, :text
    r.field :application, :json, readonly: true
    r.field :approved_at, :datetime, readonly: true
    user_ref.call(r, :reviewed_by_id, 'Reviewed by', readonly: true)
    r.field :created_at
    r.field :updated_at
    r.actions create: false, destroy: false
    # As in Spree::Admin::AffiliateAccountsController: each decision records the admin and, when
    # given, the review note (saved as review_note). The admin's approve form also overrides the
    # commission; here that is the editable commission field, set before approving (gem 0.5 refuses
    # an integer action input the app sends as a JSON number).
    review = lambda do |account, admin, input, attrs|
      attrs = attrs.merge(reviewed_by_id: admin&.id)
      attrs[:review_note] = input[:note].to_s.strip if input[:note].present?
      account.update!(attrs)
    end
    review_note = [note_input.call('Review note')]
    r.action :approve, label: 'Approve', confirm: 'Approve this affiliate?', if: ->(a) { a.pending? || a.rejected? },
                       inputs: review_note do |account, admin, input|
      review.call(account, admin, input, status: 'approved', approved_at: Time.current)
      'Affiliate approved.'
    end
    r.action :reject, label: 'Reject', confirm: 'Reject this application?', destructive: true,
                      if: ->(a) { a.pending? }, inputs: review_note do |account, admin, input|
      review.call(account, admin, input, status: 'rejected', approved_at: nil)
      'Application rejected.'
    end
    r.action :suspend, label: 'Suspend', confirm: 'Suspend this affiliate? They stop earning.', destructive: true,
                       if: ->(a) { a.approved? }, inputs: review_note do |account, admin, input|
      review.call(account, admin, input, status: 'suspended')
      'Affiliate suspended.'
    end
    r.action :reinstate, label: 'Reinstate', if: ->(a) { a.suspended? }, inputs: review_note do |account, admin, input|
      review.call(account, admin, input, status: 'approved', approved_at: account.approved_at || Time.current)
      'Affiliate reinstated.'
    end
    # Money moves outside the app; recording the payment's reference marks the account's approved
    # commissions in that currency paid (Affiliates::Payouts, as in Spree::Admin::AffiliatePayoutsController).
    approved_commissions = lambda do |account|
      AffiliateCommission.where(affiliate_account_id: account.id)
                         .where("state = 'approved' OR (state = 'pending' AND approvable_at <= ?)", Time.current)
    end
    r.action :record_payout, label: 'Record payout', confirm: 'Record this payout? Every approved commission in the currency is marked paid.',
                             if: ->(a) { approved_commissions.call(a).exists? },
                             inputs: [{ name: :reference, type: :string, required: true, label: 'Payment reference' },
                                      { name: :currency, type: :string, label: 'Currency',
                                        hint: 'Blank pays the first currency with an approved balance.' },
                                      note_input.call] do |account, _admin, input|
      AffiliateCommission.sweep!
      currency = input[:currency].to_s.strip.upcase.presence || Affiliates::Payouts.payable(account).keys.first || account.currency
      payout = Affiliates::Payouts.create!(account: account, reference: input[:reference], note: input[:note], currency: currency)
      "Payout of #{money.call(payout.amount, payout.currency)} recorded."
    end
  end

  register.call 'affiliate_commissions' do |r|
    r.model 'AffiliateCommission'
    r.label 'Affiliate commissions'
    r.group 'Commerce extras'
    r.icon 'percent'
    r.title ->(commission) { money.call(commission.amount, commission.currency) }
    r.subtitle :state
    r.list :amount, :currency, :state, :affiliate_account_id, :created_at
    r.filter :state, options.call('AffiliateCommission::STATES')
    r.filter :affiliate_account_id
    r.filter :created_at, :date_range
    r.order :created_at, :desc
    # Pending commissions past their hold are approved when the list is read, as in the admin.
    r.scope { |rel| AffiliateCommission.sweep!; rel }
    r.fields :auto
    r.field :affiliate_account_id, :reference, resource: 'affiliate_accounts', label: 'Affiliate'
    r.field :affiliate_payout_id, :reference, resource: 'affiliate_payouts', label: 'Payout'
    r.field :order_id, :reference, resource: 'spree_orders', label: 'Order'
    read_only.call(r)
    r.action :void, label: 'Void', confirm: 'Void this commission? It will not be paid.', destructive: true,
                    if: ->(c) { c.pending? || c.approved? } do |commission, _admin|
      commission.update!(state: 'void', void_reason: 'admin')
      'Commission voided.'
    end
  end

  register.call 'affiliate_payouts' do |r|
    r.model 'AffiliatePayout'
    r.label 'Affiliate payouts'
    r.group 'Commerce extras'
    r.icon 'banknote'
    r.title :reference
    r.subtitle ->(payout) { money.call(payout.amount, payout.currency) }
    r.list :reference, :amount, :currency, :paid_at
    r.search :reference
    r.filter :affiliate_account_id
    r.filter :paid_at, :date_range
    r.order :created_at, :desc
    r.fields :auto
    r.field :affiliate_account_id, :reference, resource: 'affiliate_accounts', label: 'Affiliate'
    # Recorded with Record payout on the affiliate (Affiliates::Payouts), which settles the approved commissions.
    read_only.call(r)
  end

  register.call 'digital_assets' do |r|
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
    r.field :variant_id, :reference, resource: 'spree_variants', label: 'Variant'
    r.filter :variant_id
    # Drafts and their files are edited on the product's Digital asset tab in the admin, which
    # checks each file and writes the manifest.
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

  register.call 'digital_ownerships' do |r|
    r.model 'Spree::DigitalOwnership'
    r.label 'Digital ownerships'
    r.group 'Commerce extras'
    r.icon 'person.crop.circle.badge.checkmark'
    r.title :source
    r.list :user_id, :variant_id, :source, :granted_at, :revoked_at
    r.filter :source, options.call('Spree::DigitalOwnership::SOURCES')
    r.filter :user_id
    r.filter :revoked_at, :presence
    r.order :granted_at, :desc
    r.fields :auto
    user_ref.call(r, :user_id, 'User')
    r.field :variant_id, :reference, resource: 'spree_variants', label: 'Variant'
    # Granting (DigitalOwnership.grant!) stays on the admin's user page: the app has no collection actions.
    read_only.call(r)
    # As in Spree::Admin::DigitalOwnershipsController, with its optional reason.
    r.action :revoke, label: 'Revoke', confirm: 'Revoke this ownership?', destructive: true, if: ->(o) { o.active? },
                      inputs: [{ name: :reason, type: :string, label: 'Reason', hint: 'Blank records admin_revoked.' }] do |ownership, _admin, input|
      ownership.revoke!(input[:reason].to_s.strip.presence || 'admin_revoked')
      'Ownership revoked.'
    end
  end

  register.call 'content_assets' do |r|
    r.model 'ContentAsset'
    r.label 'Content images'
    r.group 'Commerce extras'
    r.icon 'photo.on.rectangle'
    r.title :original_filename
    r.subtitle :tag
    r.list :original_filename, :tag, :alt_text, :created_at
    r.search :original_filename, :alt_text, :tag
    r.order :created_at, :desc
    # Uploaded as it is, as in Spree::Admin::ContentAssetsController; ContentAsset checks the type
    # and size and copies the file name, type and size once the save commits.
    r.field :file, :image, required: true
    r.field :alt_text, :string
    r.field :tag, :string
    r.field :original_filename, :string, readonly: true
    r.field :content_type, :string, readonly: true
    r.field :byte_size, :integer, readonly: true
    r.field :created_at
    r.field :updated_at
  end

  register.call 'entitlements' do |r|
    r.model 'Spree::Entitlement'
    r.label 'Entitlements'
    r.group 'Commerce extras'
    r.icon 'key'
    r.title :key
    r.list :key, :user_id, :active, :expires_at
    r.search :key
    r.filter :active
    r.filter :user_id
    r.order :updated_at, :desc
    r.fields :auto
    user_ref.call(r, :user_id, 'User')
    r.field :iap_transaction_id, :reference, resource: 'iap_transactions', label: 'Purchase'
    # Derived from store transactions (EntitlementResolver), never written directly.
    read_only.call(r)
    # As in Spree::Admin::EntitlementsController: revokes every purchase that grants it now, each
    # with the admin's note in the audit log (Iap::AdminRevocation).
    r.action :revoke, label: 'Revoke', confirm: 'Revoke this entitlement and the purchases that grant it?', destructive: true,
                      if: ->(e) { e.current? },
                      inputs: [note_input.call('Reason', required: true, hint: 'Kept in the audit log.')] do |entitlement, admin, input|
      granting = Spree::IapTransaction.where(user_id: entitlement.user_id).includes(:iap_product)
                                      .select { |t| t.entitlement_key == entitlement.key && t.grants_access? }
      raise 'No purchase currently grants this entitlement.' if granting.empty?

      granting.each { |t| Iap::AdminRevocation.new(t, admin: admin, note: input[:note]).call }
      "Entitlement #{entitlement.key} revoked."
    end
  end

  register.call 'iap_products' do |r|
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

  register.call 'iap_transactions' do |r|
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
    r.filter :user_id
    r.filter :purchased_at, :date_range
    r.order :created_at, :desc
    # The signed store payload is left out; the decoded payload is what the admin shows.
    r.fields :auto, except: %i[signed_payload]
    user_ref.call(r, :user_id, 'User')
    r.field :iap_product_id, :reference, resource: 'iap_products', label: 'Product'
    # Verified store records: never written from the app.
    read_only.call(r)
    # As in Spree::Admin::IapTransactionsController: once, with the admin's note in the audit log.
    r.action :revoke, label: 'Revoke purchase', confirm: 'Revoke this purchase and its entitlement?', destructive: true,
                      if: ->(t) { t.admin_revoked_at.nil? },
                      inputs: [note_input.call('Reason', required: true, hint: 'Kept in the audit log.')] do |transaction, admin, input|
      Iap::AdminRevocation.new(transaction, admin: admin, note: input[:note]).call
      'Purchase revoked.'
    end
  end

  register.call 'product_videos' do |r|
    r.model 'Spree::ProductVideo'
    r.label 'Product videos'
    r.group 'Commerce extras'
    r.icon 'film'
    r.title :alt
    r.list :alt, :product_id, :position
    r.search :alt
    r.filter :product_id
    r.order :created_at, :desc
    # A new poster is uploaded as it is, as in the admin (ProductVideo checks type and size). The
    # video itself stays in the admin.
    r.field :poster, :image
    r.field :video_url, :url, readonly: true, label: 'Video'
    r.field :product_id, :reference, resource: 'spree_products', label: 'Product', readonly: true
    r.field :alt, :string, label: 'Alt text'
    r.field :position, :integer
    r.field :video_content_type, :readonly, label: 'Video type'
    r.field :video_byte_size, :readonly, label: 'Video size (bytes)'
    r.field :created_at
    r.field :updated_at
    # A new video needs the video upload, which stays in the admin.
    r.actions create: false
  end
end
