require 'test_helper'

# Reviews > Review questions (Spree::ReviewAttribute): list, create, edit, reorder, deactivate and
# guarded delete. Admins only.
class Spree::Admin::ReviewAttributesControllerTest < ActionDispatch::IntegrationTest
  include Warden::Test::Helpers

  setup do
    @admin = media_admin
    @base = '/admin/review_questions'
    @taxonomy = Spree::Taxonomy.create!(name: "Categories #{SecureRandom.hex(2)}")
    @tops = @taxonomy.root.children.create!(name: 'Tops', taxonomy: @taxonomy)
  end

  teardown { Warden.test_reset! }

  def answer(attribute_ratings)
    reviews_enable!(photos_require_approval: false)
    product = media_product
    user = create(:user)
    reviews_order(product, user: user)
    reviews_submit(product, user: user, rating: 3, attribute_ratings: attribute_ratings).review
  end

  test 'admin only' do
    quality = create(:review_attribute, label: 'Quality')
    get @base
    refute_includes response.body, 'listing_review_attributes', 'anonymous gets the login page'

    login_as(create(:user), scope: :spree_user)
    get @base
    assert_response :redirect
    post @base, params: { review_attribute: { key: 'sneaky', label: 'Sneaky', kind: 'scale', applies_to: 'product' } }
    patch "#{@base}/#{quality.id}", params: { review_attribute: { label: 'Changed' } }
    delete "#{@base}/#{quality.id}"
    refute Spree::ReviewAttribute.exists?(key: 'sneaky')
    assert_equal 'Quality', quality.reload.label
  end

  test 'index: ordered, with answer counts, delete only for unanswered questions' do
    fit = create(:review_attribute, :fit, position: 2)
    quality = create(:review_attribute, key: 'quality', label: 'Quality', position: 1)
    answer('fit' => 2)
    fit.taxons << @tops

    login_as(@admin, scope: :spree_user)
    get @base
    assert_response :success
    rows = response.body.scan(/id="spree_review_attribute_(\d+)"/).flatten.map(&:to_i)
    assert_equal [quality.id, fit.id], rows
    assert_select "#spree_review_attribute_#{fit.id}", /Runs small to Runs large/
    assert_select "#spree_review_attribute_#{fit.id}", /Tops/
    assert_select "#spree_review_attribute_#{quality.id}", /Every product/
    assert_select "#spree_review_attribute_#{fit.id} td.text-right", '1'
    assert_select "#spree_review_attribute_#{fit.id} .delete-resource", count: 0
    assert_select "#spree_review_attribute_#{quality.id} .delete-resource", count: 1
    assert_select '#listing_review_attributes[data-sortable-link="/admin/review_questions/update_positions"]'
  end

  test 'new and create, with taxons; the key is normalized' do
    login_as(@admin, scope: :spree_user)
    get "#{@base}/new"
    assert_response :success
    assert_includes response.body, 'No taxons = every product'
    assert_includes response.body, "can't be changed later"
    assert_select "#review_attribute_taxon_ids option[value='#{@tops.id}']", "#{@taxonomy.root.name} -> Tops"

    assert_difference -> { Spree::ReviewAttribute.count }, 1 do
      post @base, params: { review_attribute: { key: ' Width ', label: 'Width', kind: 'bipolar', low_label: 'Narrow',
                                                high_label: 'Wide', applies_to: 'product', active: '1',
                                                taxon_ids: ['', @tops.id.to_s] } }
    end
    assert_redirected_to "http://www.example.com#{@base}"
    width = Spree::ReviewAttribute.find_by!(key: 'width')
    assert_equal [@tops], width.taxons.to_a
    assert_equal %w[Narrow Wide], [width.low_label, width.high_label]
  end

  test 'create with errors re-renders the form' do
    login_as(@admin, scope: :spree_user)
    assert_no_difference -> { Spree::ReviewAttribute.count } do
      post @base, params: { review_attribute: { key: 'Bad Key!', label: '', kind: 'bipolar', applies_to: 'product' } }
    end
    assert_response :success
    assert_select '#errorExplanation', /Label can't be blank/
    assert_select '#errorExplanation', /Low label can't be blank/
    assert_select '#errorExplanation', /Key is invalid/
  end

  test 'edit and update: the key never changes; switching to a 1-5 scale clears the end labels' do
    fit = create(:review_attribute, :fit, taxons: [@tops])
    login_as(@admin, scope: :spree_user)
    get "#{@base}/#{fit.id}/edit"
    assert_response :success
    assert_select 'input[name="review_attribute[key]"][disabled]'

    patch "#{@base}/#{fit.id}", params: { review_attribute: { key: 'sizing', label: 'Sizing', kind: 'scale', taxon_ids: [''] } }
    assert_redirected_to "http://www.example.com#{@base}"
    fit.reload
    assert_equal %w[fit Sizing scale], [fit.key, fit.label, fit.kind]
    assert_nil fit.low_label
    assert_empty fit.taxons

    refute fit.update(key: 'sizing'), 'the model refuses a key change too'
    assert_includes fit.errors[:key].first, "can't be changed"
  end

  test 'update with errors re-renders the form' do
    quality = create(:review_attribute, label: 'Quality')
    login_as(@admin, scope: :spree_user)
    patch "#{@base}/#{quality.id}", params: { review_attribute: { label: '' } }
    assert_response :success
    assert_select '#errorExplanation', /Label can't be blank/
    assert_equal 'Quality', quality.reload.label
  end

  test 'a question with answers is deactivated, not deleted' do
    fit = create(:review_attribute, :fit)
    answer('fit' => 4)
    login_as(@admin, scope: :spree_user)

    assert_no_difference -> { Spree::ReviewAttribute.count } do
      delete "#{@base}/#{fit.id}"
    end
    assert_redirected_to "http://www.example.com#{@base}"
    assert_match(/can only be deactivated/, flash[:error])

    patch "#{@base}/#{fit.id}", params: { review_attribute: { active: 'false' } }
    refute fit.reload.active
    get @base
    assert_select "#toggle_review_attribute_#{fit.id}[value=Activate]"
  end

  test 'a question nobody answered can be deleted' do
    quality = create(:review_attribute, label: 'Quality', taxons: [@tops])
    answer({})
    login_as(@admin, scope: :spree_user)
    assert_difference -> { Spree::ReviewAttribute.count }, -1 do
      delete "#{@base}/#{quality.id}"
    end
    assert_redirected_to "http://www.example.com#{@base}"
  end

  test 'drag to reorder' do
    first = create(:review_attribute, label: 'First')
    second = create(:review_attribute, label: 'Second')
    login_as(@admin, scope: :spree_user)
    post "#{@base}/update_positions", params: { positions: { second.id => 1, first.id => 2 } }, xhr: true
    assert_response :ok
    assert_equal [second.id, first.id], Spree::ReviewAttribute.ordered.pluck(:id)
  end
end
