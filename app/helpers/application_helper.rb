module ApplicationHelper
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
