unless Rails.env.test?
  required = %w[ADMIN_USERNAME ADMIN_PASSWORD]
  missing  = required.reject { |key| ENV[key].present? }
  raise "Missing required environment variables: #{missing.join(', ')}" if missing.any?
end
