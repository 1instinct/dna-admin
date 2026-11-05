class Spree::Admin::ContentAssetsController < Spree::Admin::BaseController
  before_action :set_content_asset, only: [:edit, :update, :destroy]

  def index
    @search = ContentAsset.ordered.ransack(params[:q])
    @content_assets = @search.result
                             .tagged(params[:tag])
                             .with_attached_file
                             .includes(file_attachment: :blob)
                             .page(params[:page])
                             .per(24)
    @tags = ContentAsset.where.not(tag: [nil, '']).distinct.pluck(:tag).sort
  end

  def new
    @content_asset = ContentAsset.new
  end

  def create
    @content_asset = ContentAsset.new(content_asset_params)
    @content_asset.file.attach(params[:content_asset][:file]) if params[:content_asset][:file]

    if @content_asset.save
      flash[:success] = Spree.t('content_asset.success.create')
      redirect_to admin_content_assets_path
    else
      flash.now[:error] = @content_asset.errors.full_messages.join(', ')
      render :new
    end
  end

  def edit; end

  def update
    @content_asset.assign_attributes(content_asset_params)
    @content_asset.file.attach(params[:content_asset][:file]) if params[:content_asset][:file]

    if @content_asset.save
      flash[:success] = Spree.t('content_asset.success.update')
      redirect_to admin_content_assets_path
    else
      flash.now[:error] = @content_asset.errors.full_messages.join(', ')
      render :edit
    end
  end

  def destroy
    @content_asset.file.purge if @content_asset.file.attached?
    @content_asset.destroy
    flash[:success] = Spree.t('content_asset.success.delete')
    redirect_to admin_content_assets_path
  end

  private

  def set_content_asset
    @content_asset = ContentAsset.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    flash[:error] = Spree.t('content_asset.error.not_found')
    redirect_to admin_content_assets_path
  end

  def content_asset_params
    params.require(:content_asset).permit(:alt_text, :tag)
  end
end
