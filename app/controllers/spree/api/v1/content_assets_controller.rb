class Spree::Api::V1::ContentAssetsController < Spree::Api::BaseController
  include Response

  before_action :authenticate_user, except: [:index, :show]
  before_action :set_content_asset, only: [:show, :update, :destroy]

  def index
    assets = ContentAsset.with_attached_file
                         .tagged(params[:tag])
                         .ordered
    assets = assets.merge(ContentAsset.search(params[:search])) if params[:search].present?

    total_count = assets.count
    limit  = params[:limit].present? ? params[:limit].to_i : 0
    offset = params[:offset].present? ? params[:offset].to_i : 0
    assets = assets.offset(offset).limit(limit) unless limit.zero?

    asset_list = assets.map { |a| asset_summary(a) }

    response_data = {
      total_records: total_count,
      offset: offset,
      content_assets: asset_list
    }
    singular_success_model(200, Spree.t('content_asset.success.index'), response_data)
  end

  def show
    singular_success_model(200, Spree.t('content_asset.success.show'), asset_detail(@content_asset))
  end

  def create
    asset = ContentAsset.new(content_asset_params)
    asset.file.attach(params[:file]) if params[:file]

    if asset.save
      singular_success_model(200, Spree.t('content_asset.success.create'), asset_detail(asset))
    else
      error_model(400, asset.errors.full_messages.join(', '))
    end
  end

  def update
    @content_asset.assign_attributes(content_asset_params)
    @content_asset.file.attach(params[:file]) if params[:file]

    if @content_asset.save
      singular_success_model(200, Spree.t('content_asset.success.update'), asset_detail(@content_asset))
    else
      error_model(400, @content_asset.errors.full_messages.join(', '))
    end
  end

  def destroy
    @content_asset.file.purge if @content_asset.file.attached?
    @content_asset.destroy
    success_model(200, Spree.t('content_asset.success.delete'))
  end

  private

  def set_content_asset
    @content_asset = ContentAsset.find_by(id: params[:id])
    unless @content_asset
      error_model(400, Spree.t('content_asset.error.not_found'))
    end
  end

  def content_asset_params
    params.permit(:alt_text, :tag)
  end

  # Summary for list (only thumbnail URLs to avoid N+1)
  def asset_summary(asset)
    {
      id: asset.id,
      alt_text: asset.alt_text,
      tag: asset.tag,
      original_filename: asset.original_filename,
      content_type: asset.content_type,
      byte_size: asset.byte_size,
      urls: asset.thumbnail_urls,
      created_at: asset.created_at,
      updated_at: asset.updated_at
    }
  end

  # Full detail for show (all variant URLs)
  def asset_detail(asset)
    {
      id: asset.id,
      alt_text: asset.alt_text,
      tag: asset.tag,
      original_filename: asset.original_filename,
      content_type: asset.content_type,
      byte_size: asset.byte_size,
      urls: asset.all_urls,
      created_at: asset.created_at,
      updated_at: asset.updated_at
    }
  end
end
