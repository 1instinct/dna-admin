FactoryBot.define do
  factory :content_asset do
    alt_text { "Test image" }
    tag { "test" }
    original_filename { "test-image.png" }
    content_type { "image/png" }
    byte_size { 1024 }

    after(:build) do |asset|
      asset.file.attach(
        io: StringIO.new("fake-image-data"),
        filename: "test-image.png",
        content_type: "image/png"
      )
    end
  end
end
