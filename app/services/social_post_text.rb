# Plain-text body for the social platforms (WhatsApp, Instagram, TikTok):
#
#   📢 <title>
#
#   <body, truncated so the whole text fits max_length>
#
#   <source link without tracking params>
#
# None of them render HTML, and their own markup (WhatsApp's *bold*) would
# misfire on LLM-written Persian text, so it stays plain.
module SocialPostText
  module_function

  def build(translation, max_length:)
    header = "📢 #{translation.translated_title.to_s.strip}\n\n"
    footer = "\n\n#{article_link(translation)}"
    body_budget = [ max_length - header.length - footer.length, 0 ].max

    "#{header}#{translation.translated_body.to_s.strip.truncate(body_budget)}#{footer}"
  end

  def article_link(translation) = translation.article.url.to_s.split("?").first
end
