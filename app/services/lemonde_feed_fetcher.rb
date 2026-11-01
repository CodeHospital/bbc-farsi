# Le Monde (English edition). Single publisher, so the allowlist is its feed
# host (Feed::LEMONDE_FEEDS).
class LemondeFeedFetcher < FeedFetcher
  private

  def allowed_hosts = %w[www.lemonde.fr]
  def source_label  = "Le Monde"
end
