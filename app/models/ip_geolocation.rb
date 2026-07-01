# Local cache of IP → country lookups so repeat visitors from the same IP never
# trigger a second HTTP call to the geolocation service. Populated (and read) by
# ArticleView.geolocate_ip; listed in the admin under "IP Geolocations".
class IpGeolocation < ApplicationRecord
  validates :ip, presence: true, uniqueness: true

  # Bump the usage counter without loading validations/callbacks — this runs on
  # every cache hit inside the (error-swallowed) page-view tracking path.
  def record_hit!
    self.class.where(id: id).update_all(
      "lookups_count = lookups_count + 1, last_used_at = CURRENT_TIMESTAMP"
    )
  end
end
