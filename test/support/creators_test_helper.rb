# Shared helpers for the creators module tests.
module CreatorsTestHelper
  # A user with the creator role and an active creator account.
  def creator_user(handle: nil, name: nil)
    user = create(:user)
    Creators::Approver.approve!(create(:creator_application, user: user), create(:user))
    if handle || name
      profile = user.profile || user.create_profile!
      profile.update!(handle: handle, name: name)
    end
    user.reload
  end

  # The marketplace taxon (Creators.config.marketplace_taxon_permalink) and one category under it.
  def marketplace_taxons
    taxonomy = Spree::Taxonomy.create!(name: 'Marketplace')
    root = taxonomy.root
    root.update!(permalink: Creators.config.marketplace_taxon_permalink)
    child = Spree::Taxon.create!(name: 'Bundles', taxonomy: taxonomy, parent: root)
    [root.reload, child]
  end

  # A creator's draft product (unavailable) with a draft asset holding the files.
  def creator_product(user, taxons: [], kind: 'bundle', manifest: { 'format' => 1 },
                      files: { 'intro.wav' => DigitalAssetsTestHelper::WAV_BYTES,
                               'outro.wav' => DigitalAssetsTestHelper::WAV_BYTES }, price: 10)
    product = Spree::Product.new(name: "Creator Bundle #{SecureRandom.hex(3)}", price: price, available_on: nil,
                                 shipping_category: Spree::ShippingCategory.first_or_create!(name: 'Default'),
                                 creator_id: user.id, review_state: 'draft')
    product.stores << digital_store if product.respond_to?(:stores)
    product.taxons = taxons
    product.save!
    asset = Spree::DigitalAsset.create!(variant: product.master, kind: kind, manifest: manifest)
    asset.attach_files!(files.map { |name, bytes| digital_blob(bytes, name) }) if files.any?
    product
  end

  # A creator product taken through submit and approval: on sale with a published asset.
  def approved_creator_product(user, price: 10)
    product = creator_product(user, price: price)
    product.update!(review_state: 'submitted', submitted_at: Time.current)
    Creators::Reviewer.approve!(product, nil)
    product.reload
  end

  # An order in the cart state for the user holding [product, quantity] pairs. Named apart from
  # AffiliatesTestHelper#cart_order(user:, email:, products:), which is included into the same
  # test case.
  def creator_cart_order(user, *items)
    order = Spree::Order.create!(user: user, email: user.email, store: digital_store, currency: 'USD')
    items.each { |product, quantity| Spree::Cart::AddItem.call(order: order, variant: product.master, quantity: quantity) }
    order.update_with_updater!
    order.reload
  end

  # Takes the order to `complete` through the state machine, paid by check.
  def complete_order!(order)
    order.update_with_updater!
    order.update_columns(state: 'confirm')
    method = Spree::PaymentMethod::Check.first || begin
      check = Spree::PaymentMethod::Check.new(name: 'Check', active: true)
      check.stores << digital_store if check.respond_to?(:stores)
      check.save!
      check
    end
    order.payments.create!(amount: order.total, payment_method: method, state: 'checkout')
    order.reload.next!
    raise "order #{order.number} is #{order.state}, not complete" unless order.reload.complete?

    order
  end

  def admin_user
    user = create(:user)
    user.spree_roles << Spree::Role.find_or_create_by!(name: 'admin')
    user
  end

  # Runs the block with a temporary boolean column on spree_users. Postgres DDL is transactional,
  # and the column is dropped again before the test's transaction rolls back.
  # An app whose users already have the column (spree_users.is_creator) runs the block
  # as is and keeps the column.
  def with_user_column(name)
    connection = ActiveRecord::Base.connection
    existed = connection.column_exists?(:spree_users, name)
    unless existed
      connection.add_column :spree_users, name, :boolean, default: false, null: false
      connection.clear_cache!
      Spree::User.reset_column_information
    end
    yield
  ensure
    unless existed
      connection.remove_column :spree_users, name if connection.column_exists?(:spree_users, name)
      connection.clear_cache!
      Spree::User.reset_column_information
    end
  end

  # Runs the block with the boolean column absent from spree_users, for an app that has it. The
  # column is put back before the test's transaction rolls back (which restores the original
  # column and its index).
  def without_user_column(name)
    connection = ActiveRecord::Base.connection
    existed = connection.column_exists?(:spree_users, name)
    if existed
      connection.remove_column :spree_users, name
      connection.clear_cache!
      Spree::User.reset_column_information
    end
    yield
  ensure
    if existed
      connection.add_column :spree_users, name, :boolean, default: false, null: false unless connection.column_exists?(:spree_users, name)
      connection.clear_cache!
      Spree::User.reset_column_information
    end
  end
end

ActiveSupport::TestCase.include(CreatorsTestHelper)
