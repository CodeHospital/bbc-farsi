module Admin
  module TranslationsHelper
    # Clickable, toggle-direction column header for the translations table.
    # Preserves the other query params (filters, search) and resets pagination.
    def translation_sort_link(column, label)
      sort   = params[:sort].presence || "created"
      dir    = params[:dir] == "asc" ? "asc" : "desc"
      active = sort == column

      next_dir  = active && dir == "asc" ? "desc" : "asc"
      indicator = active ? (dir == "asc" ? " ▲" : " ▼") : ""
      target    = admin_translations_path(request.query_parameters.merge("sort" => column, "dir" => next_dir).except("page"))

      link_to "#{label}#{indicator}", target, class: "text-reset text-decoration-none"
    end
  end
end
