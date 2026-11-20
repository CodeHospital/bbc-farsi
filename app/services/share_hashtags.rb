# Hashtags appended to the first line (the title) of every shared post:
# the source feed's publisher and the country it publishes from, e.g.
#
#   #BBC_News #بریتانیا                (Persian, the default for channel posts)
#   #BBC_News #United_Kingdom          (English edition share buttons)
#
# Blank when the article has no feed (nothing to tag).
module ShareHashtags
  module_function

  def for(article, lang: "fa")
    feed = article&.feed
    return "" unless feed

    country_code = feed.country_code
    country_name = country_code && (lang.to_s == "en" ? Country.name_for(country_code) : Country.name_fa_for(country_code))

    [ feed.publisher_name, country_name ].filter_map { |label| hashtag(label) }.uniq.join(" ")
  end

  # "<title> #Publisher #Country" — or the bare title when there are no hashtags.
  def append_to(title, article, lang: "fa")
    hashtags = self.for(article, lang:)
    hashtags.empty? ? title.to_s : "#{title} #{hashtags}"
  end

  # A label as one hashtag: anything that isn't a letter, digit, mark or ZWNJ
  # becomes "_" (hashtags end at spaces/punctuation), runs collapse, edges trim.
  def hashtag(label)
    word = label.to_s.gsub(/[^\p{L}\p{N}\p{M}\u200C]+/, "_").gsub(/\A_+|_+\z/, "")
    word.empty? ? nil : "##{word}"
  end
end
