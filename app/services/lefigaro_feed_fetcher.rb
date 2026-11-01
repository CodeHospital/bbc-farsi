# Le Figaro (French). Single publisher, so the allowlist is its feed host
# (Feed::LEFIGARO_FEEDS).
class LefigaroFeedFetcher < FeedFetcher
  private

  def allowed_hosts = %w[www.lefigaro.fr]
  def source_label  = "Le Figaro"
end
