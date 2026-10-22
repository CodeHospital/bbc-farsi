module ApplicationHelper
  # Convert a country into a flag emoji. Accepts either a 2-letter ISO code
  # (e.g. "US" → 🇺🇸) or a full country name (e.g. "United States" → 🇺🇸),
  # falling back to 🌐 when the country can't be resolved.
  def country_flag(country)
    code = country.to_s.strip
    code = code_for_country_name(code) if code.length != 2

    if code.to_s.length == 2
      code.upcase.chars.map { |c| (c.ord - 65 + 0x1F1E6).chr(Encoding::UTF_8) }.join
    else
      "🌐"
    end
  end

  # Reverse lookup: full country name → 2-letter ISO code (case-insensitive),
  # or nil when unknown.
  def code_for_country_name(name) = Country.code_for_name(name)

  # Human-readable country name for a 2-letter ISO code, or the code itself.
  def country_name(code) = Country.name_for(code)

  # Admin pages linking into the public portal: a plain path normally, an
  # absolute public-host URL once the admin UI lives on its own domain (see
  # AppHosts). portal_route(:news, id: "a1") → news_path / news_url.
  def portal_route(route_name, *route_args, **route_params)
    cross_host_route(AppHosts.public_url_options, route_name, *route_args, **route_params)
  end

  # Same for links into the admin UI from another host (worker status page).
  # admin_route(:admin_task, task) → admin_task_path / admin_task_url.
  def admin_route(route_name, *route_args, **route_params)
    cross_host_route(AppHosts.admin_url_options, route_name, *route_args, **route_params)
  end

  def cross_host_route(target_url_options, route_name, *route_args, **route_params)
    if target_url_options.empty?
      public_send("#{route_name}_path", *route_args, **route_params)
    else
      public_send("#{route_name}_url", *route_args, **route_params, **target_url_options)
    end
  end

  # Number of translations currently flagged for manual editor review, used to
  # badge the "Needs Edit" sidebar menu item. Memoized per request so rendering
  # the (globally-shown) admin sidebar costs at most one COUNT per page load.
  def manual_edit_review_count
    @manual_edit_review_count ||= Translation.needs_manual_edit.count
  end

  # Generic sortable column header link.
  # Preserves all current query params, toggles direction for the active column,
  # and resets pagination. Uses ▲/▼ to indicate the active sort direction.
  def sort_link(column, label)
    current_sort = params[:sort].to_s
    current_dir  = params[:dir] == "asc" ? "asc" : "desc"
    active       = current_sort == column
    next_dir     = active && current_dir == "asc" ? "desc" : "asc"
    indicator    = active ? (current_dir == "asc" ? " ▲" : " ▼") : ""
    target       = url_for(request.query_parameters.merge("sort" => column, "dir" => next_dir).except("page"))
    link_to "#{label}#{indicator}", target, class: "text-reset text-decoration-none"
  end
end
