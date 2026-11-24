# Records Sentry breadcrumbs with the object form sentry-ruby requires.
#
# sentry-ruby's Sentry.add_breadcrumb takes a Sentry::Breadcrumb instance and
# does not accept `extra:` or other keyword options, so call sites must go
# through record instead of passing a message plus keywords.
#
# Like every other Sentry call, this is a safe no-op until Sentry.init runs
# (see config/initializers/sentry.rb and SentryConfig).
module SentryBreadcrumb
  module_function

  DEFAULT_CATEGORY = "app".freeze
  DEFAULT_LEVEL    = "info".freeze

  # @param message [String] short description of the step, e.g. "ArticleAnalyzer.process"
  # @param category [String] grouping label shown in Sentry, e.g. "article_analyzer"
  # @param data [Hash] extra context attached to the breadcrumb
  # @param level [String] Sentry level: "debug", "info", "warning", "error", ...
  def record(message, category: DEFAULT_CATEGORY, data: {}, level: DEFAULT_LEVEL)
    Sentry.add_breadcrumb(
      Sentry::Breadcrumb.new(category: category, message: message, data: data, level: level)
    )
  end
end
