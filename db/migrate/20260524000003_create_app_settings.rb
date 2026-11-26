class CreateAppSettings < ActiveRecord::Migration[6.1]
  def change
    create_table :app_settings do |t|
      t.string :name
      t.string :platform, default: 'ios-android'
      t.string :version, null: false, default: '0.0.0'
      t.string :build
      t.timestamps
    end
  end
end
