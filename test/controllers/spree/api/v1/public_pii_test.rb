require "test_helper"

# Endpoints that show one user's data to someone else (nobody signed in, or another
# user) must not carry email, real or billing names, phone, address, ip, api keys or
# stream keys. Contacts, messages and threads hold other people's data and are
# admin-only, except contact and message create.
class Spree::Api::V1::PublicPiiTest < ActionDispatch::IntegrationTest
  PII_KEYS = %w[email first_name last_name firstname lastname phone address address1 ip
                spree_api_key api_key token stream_key].freeze

  setup do
    @hex = SecureRandom.hex(4)
    @owner = Spree::User.create!(email: "pii-owner-#{@hex}@example.com", password: "password123")
    @owner.generate_spree_api_key!
    @address = Spree::Address.create!(user: @owner, firstname: "Zelda#{@hex}", lastname: "Quixote#{@hex}",
                                      address1: "9 Secret Lane #{@hex}", city: "Hidden", zipcode: "54321",
                                      phone: "555-01#{@hex}", country: country)
    @owner.update!(bill_address: @address)
    @viewer = Spree::User.create!(email: "pii-viewer-#{@hex}@example.com", password: "password123")
    @viewer.generate_spree_api_key!
    @admin = Spree::User.create!(email: "pii-admin-#{@hex}@example.com", password: "password123")
    @admin.generate_spree_api_key!
    @admin.spree_roles << Spree::Role.find_or_create_by!(name: "admin")
  end

  # --- profiles -----------------------------------------------------------------

  test "profile by id leaks no PII to an anonymous caller" do
    get "/api/v1/users/#{@owner.id}/profile.json"
    assert_response :success
    assert_profile_clean
  end

  test "profile by id leaks no PII to another signed-in user" do
    get "/api/v1/users/#{@owner.id}/profile.json", headers: as(@viewer)
    assert_response :success
    assert_profile_clean
  end

  test "profile still carries the public fields" do
    get "/api/v1/users/#{@owner.id}/profile.json"
    data = JSON.parse(response.body)["response_data"]
    assert_equal @owner.id, data["id"]
    assert data.key?("followers_count")
    # Keys stay, empty, so older web clients that read them keep working.
    assert_equal "", data["email"]
    assert_equal "", data["first_name"]
    assert_equal "", data["last_name"]
  end

  # --- live streams -------------------------------------------------------------

  test "live stream list leaks no actor PII, stream key or watcher ids to another user" do
    stream = create_stream
    get "/api/v1/live_stream.json", headers: as(@viewer)
    assert_response :success
    listed = JSON.parse(response.body)["response_data"].find { |s| s["id"] == stream.id }
    assert listed, "the stream is listed"
    assert_stream_clean(listed)
  end

  test "live stream show leaks no actor PII, stream key or watcher ids to another user" do
    stream = create_stream
    get "/api/v1/live_stream/#{stream.id}.json", headers: as(@viewer)
    assert_response :success
    assert_stream_clean(JSON.parse(response.body)["response_data"])
  end

  test "live stream never returns the stream key, even to admins (public web proxy uses a server key)" do
    stream = create_stream
    get "/api/v1/live_stream/#{stream.id}.json", headers: as(@admin)
    assert_response :success
    assert_stream_clean(JSON.parse(response.body)["response_data"])
  end

  test "live stream actor keeps its id" do
    stream = create_stream
    get "/api/v1/live_stream/#{stream.id}.json", headers: as(@viewer)
    actor = JSON.parse(response.body)["response_data"]["actor"]
    assert_equal @owner.id, actor["id"]
  end

  # --- contacts -----------------------------------------------------------------

  test "contacts index, show, update and destroy refuse anonymous callers" do
    contact = create_contact
    get "/api/v1/contacts.json"
    assert_refused
    get "/api/v1/contacts/#{contact.id}.json"
    assert_refused
    patch "/api/v1/contacts/#{contact.id}.json", params: { contact: { full_name: "Hijacked" } }
    assert_refused
    delete "/api/v1/contacts/#{contact.id}.json"
    assert_refused
    contact.reload
    assert_equal "Ada Contact#{@hex}", contact.full_name
  end

  test "contacts index and show refuse non-admin users" do
    contact = create_contact
    get "/api/v1/contacts.json", headers: as(@viewer)
    assert_refused
    get "/api/v1/contacts/#{contact.id}.json", headers: as(@viewer)
    assert_refused
    delete "/api/v1/contacts/#{contact.id}.json", headers: as(@viewer)
    assert_refused
    assert Contact.exists?(contact.id)
  end

  test "admins can still list contacts" do
    contact = create_contact
    get "/api/v1/contacts.json", headers: as(@admin)
    assert_response :success
    ids = JSON.parse(response.body)["response_data"]["contact_listing"].map { |c| c["id"] }
    assert_includes ids, contact.id
  end

  test "anyone can still create a contact" do
    post "/api/v1/contacts.json", params: { contact: { full_name: "New #{@hex}", email: "new-#{@hex}@example.com" } }
    assert_response :success
    assert_equal 200, JSON.parse(response.body)["response_code"]
  end

  # --- messages and threads -----------------------------------------------------

  test "messages index, show, update and destroy refuse anonymous and non-admin callers" do
    message = create_message
    [{}, as(@viewer)].each do |headers|
      get "/api/v1/messages.json", headers: headers
      assert_refused
      get "/api/v1/messages/#{message.id}.json", headers: headers
      assert_refused
      patch "/api/v1/messages/#{message.id}.json", params: { message: { message: "edited" } }, headers: headers
      assert_refused
      delete "/api/v1/messages/#{message.id}.json", headers: headers
      assert_refused
    end
    assert_equal "private words #{@hex}", message.reload.message
  end

  test "admins can still list messages" do
    message = create_message
    get "/api/v1/messages.json", headers: as(@admin)
    assert_response :success
    ids = JSON.parse(response.body)["response_data"]["message_listing"].map { |m| m["id"] }
    assert_includes ids, message.id
  end

  test "threads index, show and destroy refuse anonymous and non-admin callers" do
    thread = ThreadTable.create!(stale: true, archived: true)
    [{}, as(@viewer)].each do |headers|
      get "/api/v1/threads.json", headers: headers
      assert_refused
      get "/api/v1/threads/#{thread.id}.json", headers: headers
      assert_refused
      delete "/api/v1/threads/#{thread.id}.json", headers: headers
      assert_refused
    end
    assert ThreadTable.exists?(thread.id)
  end

  private

  def as(user)
    { "X-Spree-Token" => user.spree_api_key }
  end

  def secrets
    [@owner.email, @address.firstname, @address.lastname, @address.address1, @address.phone, @owner.spree_api_key]
  end

  def assert_no_secrets_in_body
    secrets.each { |s| refute_includes response.body, s }
  end

  def assert_no_pii_values(hash)
    PII_KEYS.each do |key|
      next unless hash.key?(key)
      assert hash[key].blank?, "#{key} must be blank, got #{hash[key].inspect}"
    end
  end

  def assert_profile_clean
    data = JSON.parse(response.body)["response_data"]
    assert data.is_a?(Hash), "profile body: #{response.body}"
    assert_no_pii_values(data)
    assert_no_secrets_in_body
  end

  def assert_stream_clean(stream)
    assert_no_pii_values(stream)
    assert_no_pii_values(stream["actor"])
    assert_equal [], stream["contact_ids"]
    assert_no_secrets_in_body
    refute_includes response.body, "sk-live-#{@hex}"
  end

  def assert_refused
    assert_response :unauthorized
    refute_includes response.body, "contact-#{@hex}@example.com"
    refute_includes response.body, "private words #{@hex}"
  end

  def create_stream
    stream = LiveStream.create!(title: "Stream #{@hex}", stream_key: "sk-live-#{@hex}", actor: @owner)
    contact = create_contact
    LiveStreamContact.create!(live_stream_id: stream.id, contact_id: contact.id)
    stream
  end

  def create_contact
    Contact.create!(actor: @owner, full_name: "Ada Contact#{@hex}", email: "contact-#{@hex}@example.com",
                    phone: "555-77#{@hex}", ip: "203.0.113.9")
  end

  def create_message
    sender = create_contact
    receiver = create_contact
    Message.create!(sender: sender, receiver: receiver, message: "private words #{@hex}")
  end

  def country
    @country ||= Spree::Country.find_by(iso: "ZZ") ||
                 Spree::Country.create!(name: "Testland", iso: "ZZ", iso3: "ZZZ", iso_name: "TESTLAND",
                                        states_required: false, zipcode_required: false)
  end
end
