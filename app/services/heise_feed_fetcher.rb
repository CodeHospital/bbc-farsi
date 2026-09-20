# heise online and its sister titles. Telepolis is a heise-medien publication
# on its own host, so it shares this fetcher rather than getting its own source.
class HeiseFeedFetcher < FeedFetcher
  private

  def allowed_hosts = %w[www.heise.de www.telepolis.de]
  def source_label  = "heise"
end
