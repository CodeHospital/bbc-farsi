class Admin::IpGeolocationsController < Admin::BaseController
  before_action :require_admin!
  include Pagy::Method

  SORT_COLUMNS = {
    "ip"      => "ip",
    "country" => "country_name",
    "city"    => "city_name",
    "lookups" => "lookups_count",
    "used"    => "last_used_at",
    "created" => "created_at"
  }.freeze

  def index
    unless IpGeolocation.table_exists?
      @missing_migration = true
      return
    end

    column    = SORT_COLUMNS[params[:sort]] || SORT_COLUMNS["used"]
    direction = params[:dir] == "asc" ? "asc" : "desc"

    scope = IpGeolocation.all
    if params[:q].present?
      term  = "%#{params[:q].strip}%"
      scope = scope.where("ip LIKE ? OR country_name LIKE ?", term, term)
    end

    @cached_total    = IpGeolocation.count
    @resolved_total  = IpGeolocation.where.not(country_name: nil).count
    @lookups_total   = IpGeolocation.sum(:lookups_count)

    @pagy, @geolocations = pagy(scope.order(Arel.sql("#{column} #{direction} NULLS LAST")))
  end

  def destroy
    IpGeolocation.find(params[:id]).destroy
    redirect_to admin_ip_geolocations_path, notice: "IP geolocation entry deleted."
  end
end
