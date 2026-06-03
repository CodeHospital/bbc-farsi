class AddActiveToTranslations < ActiveRecord::Migration[8.0]
  def change
    add_column :translations, :active, :boolean, default: false, null: false
  end
end
