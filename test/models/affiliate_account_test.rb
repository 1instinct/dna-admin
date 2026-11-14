require 'test_helper'

class AffiliateAccountTest < ActiveSupport::TestCase
  teardown { Affiliates.reset_config! }

  test 'code is stripped and lowercased' do
    account = create(:affiliate_account, code: '  My-Code9 ')
    assert_equal 'my-code9', account.code
  end

  test 'code must be 4 to 24 of a-z, 0-9 and -' do
    %w[abc a_bcd ab.cd abcd! co\ de].each do |code|
      refute build(:affiliate_account, code: code).valid?, "#{code.inspect} should be invalid"
    end
    refute build(:affiliate_account, code: 'a' * 25).valid?
    assert build(:affiliate_account, code: 'abcd').valid?
    assert build(:affiliate_account, code: 'a' * 24).valid?
    assert build(:affiliate_account, code: 'dj-shadow-99').valid?
  end

  test 'code is unique case-insensitively' do
    create(:affiliate_account, code: 'taken-code')
    other = build(:affiliate_account, code: 'TAKEN-CODE')
    refute other.valid?
    assert other.errors[:code].any?
  end

  test 'find_by_code is case-insensitive and ignores surrounding space' do
    account = create(:affiliate_account, code: 'find-me')
    assert_equal account, AffiliateAccount.find_by_code(' FIND-ME ')
    assert_nil AffiliateAccount.find_by_code('nope')
    assert_nil AffiliateAccount.find_by_code(nil)
  end

  test 'one account per user' do
    account = create(:affiliate_account)
    refute build(:affiliate_account, user: account.user, code: 'second-code').valid?
  end

  test 'status must be pending, approved, rejected or suspended' do
    %w[pending approved rejected suspended].each do |status|
      assert build(:affiliate_account, status: status).valid?, status
    end
    refute build(:affiliate_account, status: 'active').valid?
  end

  test 'effective_commission_bps falls back to config' do
    account = build(:affiliate_account, commission_bps: nil)
    assert_equal 1000, account.effective_commission_bps

    Affiliates.config.default_commission_bps = 1500
    assert_equal 1500, account.effective_commission_bps

    account.commission_bps = 2000
    assert_equal 2000, account.effective_commission_bps
  end

  test 'cookie_days defaults to 30' do
    assert_equal 30, AffiliateAccount.new.cookie_days
  end

  test 'link adds the ref code to the configured base url' do
    Affiliates.config.link_base_url = 'https://shop.example.com/'
    account = build(:affiliate_account, code: 'my-code')
    assert_equal 'https://shop.example.com/?ref=my-code', account.link
    assert_equal 'https://shop.example.com/products/x?ref=my-code', account.link('/products/x')
    assert_equal 'https://shop.example.com/browse?mode=a&ref=my-code', account.link('/browse?mode=a')
  end

  test 'default code comes from the profile handle' do
    profile = create(:user_profile, handle: 'beat_maker')
    account = AffiliateAccount.new(user: profile.user, payout_email: 'x@example.com')
    account.valid?
    assert_equal 'beat-maker', account.code
  end

  test 'code_available? is false for taken codes, reserved handles and other users handles' do
    with_moderation_lists(reserved: %w[admin support], blocked: %w[badword]) do
      user = create(:user)
      create(:affiliate_account, code: 'taken-one')
      create(:user_profile, handle: 'someone_else')
      own = create(:user_profile, user: user, handle: 'my_handle')

      refute AffiliateAccount.code_available?('taken-one', user: user)
      refute AffiliateAccount.code_available?('TAKEN-ONE', user: user)
      refute AffiliateAccount.code_available?('admin', user: user)
      refute AffiliateAccount.code_available?('support', user: user)
      refute AffiliateAccount.code_available?('someone-else', user: user)
      refute AffiliateAccount.code_available?('my-badword-code', user: user)
      refute AffiliateAccount.code_available?('bad', user: user), 'too short'
      assert AffiliateAccount.code_available?('my-handle', user: own.user)
      assert AffiliateAccount.code_available?('fresh-code', user: user)
    end
  end

  test 'a reserved code is invalid on the record' do
    with_moderation_lists(reserved: %w[admin], blocked: []) do
      account = build(:affiliate_account, code: 'admin')
      refute account.valid?
      assert account.errors[:code].any?
    end
  end

  test 'totals count clicks, orders and commission amounts by state' do
    account = approved_affiliate
    3.times { create(:affiliate_click, affiliate_account: account) }
    create(:affiliate_commission, affiliate_account: account, amount: 5, state: 'pending')
    create(:affiliate_commission, affiliate_account: account, amount: 7, state: 'approved')
    create(:affiliate_commission, affiliate_account: account, amount: 11, state: 'paid')
    create(:affiliate_commission, affiliate_account: account, amount: 13, state: 'void')

    totals = account.totals
    assert_equal 3, totals[:clicks]
    assert_equal 3, totals[:orders]
    assert_in_delta 1.0, totals[:conversion]
    assert_equal 5.0, totals[:pending]
    assert_equal 7.0, totals[:approved]
    assert_equal 11.0, totals[:paid]
    assert_equal 'USD', totals[:currency]
  end

  test 'totals limited to a range and zero conversion without clicks' do
    account = approved_affiliate
    old = create(:affiliate_click, affiliate_account: account)
    old.update_column(:created_at, 40.days.ago)
    totals = account.totals(10.days.ago..Time.current)
    assert_equal 0, totals[:clicks]
    assert_equal 0.0, totals[:conversion]
  end
end
