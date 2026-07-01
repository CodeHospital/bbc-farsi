class AddCountryNameAndCityNameToArticleViews < ActiveRecord::Migration[8.0]
  def change
    add_column :article_views, :country_name, :string
    add_column :article_views, :city_name,    :string
  end
end
