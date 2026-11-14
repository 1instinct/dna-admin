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
    child = Spree::Taxon.create!(name: 'Packs', taxonomy: taxonomy, parent: root)
    [root.reload, child]
  end

  # A creator's draft product (unavailable) with a draft asset holding the files.
  def creator_product(user, taxons: [], kind: 'pack', manifest: { 'format' => 1 },
                      files: { 'kick.wav' => DigitalAssetsTestHelper::WAV_BYTES,
                               'snare.wav' => DigitalAssetsTestHelper::WAV_BYTES }, price: 10)
    product = Spree::Product.new(name: "Creator Pack #{SecureRandom.hex(3)}", price: price, available_on: nil,
                                 shipping_category: Spree::ShippingCategory.first_or_create!(name: 'Default'),
                                 creator_id: user.id, review_state: 'draft')
    product.stores << digital_store if product.respond_to?(:stores)
    product.taxons = taxons
    product.save!
    asset = Spree::DigitalAsset.create!(variant: product.master, kind: kind, manifest: manifest)
    asset.attach_files!(files.map { |name, bytes| digital_blob(bytes, name) }) if files.any?
    product
  end

  def admin_user
    user = create(:user)
    user.spree_roles << Spree::Role.find_or_create_by!(name: 'admin')
    user
  end

  # Runs the block with a temporary boolean column on spree_users. Postgres DDL is transactional,
  # and the column is dropped again before the test's transaction rolls back.
  def with_user_column(name)
    connection = ActiveRecord::Base.connection
    connection.add_column :spree_users, name, :boolean, default: false, null: false
    connection.clear_cache!
    Spree::User.reset_column_information
    yield
  ensure
    connection.remove_column :spree_users, name if connection.column_exists?(:spree_users, name)
    connection.clear_cache!
    Spree::User.reset_column_information
  end
end

ActiveSupport::TestCase.include(CreatorsTestHelper)
