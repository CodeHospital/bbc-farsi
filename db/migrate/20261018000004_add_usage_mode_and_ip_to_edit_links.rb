class AddUsageModeAndIpToEditLinks < ActiveRecord::Migration[8.0]
  # Edit links are either multi-use (any number of people may each propose an
  # edit until it expires or is revoked — the default, matching earlier
  # behaviour) or single-use (consumed by the first submission, `used_at`).
  # Guest pending edits also record the submitter's IP and the country/city it
  # resolved to (via the cached IpGeolocation lookup) for the reviewer.
  def change
    add_column :edit_links, :single_use, :boolean, default: false, null: false
    add_column :edit_links, :used_at, :datetime

    add_column :pending_edits, :guest_ip, :string
    add_column :pending_edits, :guest_country_name, :string
    add_column :pending_edits, :guest_city_name, :string
  end
end
