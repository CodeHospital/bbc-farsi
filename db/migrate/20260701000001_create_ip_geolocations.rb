class CreateIpGeolocations < ActiveRecord::Migration[8.0]
  def change
    create_table :ip_geolocations do |t|
      t.string   :ip,           null: false
      t.string   :country_name
      t.string   :city_name
      t.integer  :lookups_count, null: false, default: 0
      t.datetime :last_used_at
      t.timestamps
    end

    add_index :ip_geolocations, :ip, unique: true
    add_index :ip_geolocations, :country_name
  end
end
