class AddRequiresConsultationToSpreeProducts < ActiveRecord::Migration[6.1]
  def change
    add_column :spree_products, :requires_consultation, :boolean, default: false, null: false
  end
end
