# Google Product Review Feed, schema v2.4:
# https://www.google.com/shopping/reviews/schema/product/2.4/product_reviews.xsd
# Element order follows the schema's xs:sequence. Rows come from Reviews::GoogleFeed.
xml.instruct! :xml, version: '1.0', encoding: 'UTF-8'
xml.feed 'xmlns:xsi' => 'http://www.w3.org/2001/XMLSchema-instance',
         'xsi:noNamespaceSchemaLocation' => 'http://www.google.com/shopping/reviews/schema/product/2.4/product_reviews.xsd' do
  xml.version '2.4'
  xml.publisher do
    xml.name @feed.publisher_name
  end

  # The schema has no empty <reviews>: leave it out when there's nothing to list.
  if @feed.any?
    xml.reviews do
      @feed.each_review do |review, product|
        xml.review do
          xml.review_id review.id.to_s
          xml.reviewer do
            if @feed.anonymous?(review)
              xml.name review.display_name, is_anonymous: 'true'
            else
              xml.name review.display_name
            end
          end
          xml.review_timestamp @feed.timestamp(review)
          xml.title review.title.strip if review.title.present?
          xml.content review.body.strip
          xml.review_url @feed.review_url(review, product), type: 'singleton'
          xml.ratings do
            xml.overall review.rating, min: 1, max: 5
          end
          xml.products do
            xml.product do
              skus = @feed.skus(product)
              xml.product_ids do
                if skus.any?
                  xml.skus do
                    skus.each { |sku| xml.sku sku }
                  end
                end
                xml.brands do
                  xml.brand @feed.brand(product)
                end
              end
              xml.product_name product.name
              xml.product_url @feed.product_url(product)
            end
          end
          xml.is_verified_purchase 'true'
          xml.is_incentivized_review review.incentivized ? 'true' : 'false'
          xml.collection_method @feed.collection_method(review)
        end
      end
    end
  end
end
