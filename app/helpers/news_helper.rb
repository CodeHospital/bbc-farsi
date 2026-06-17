module NewsHelper
  CATEGORY_NAMES_FA = {
    "top"        => "خبر فوری",
    "world"      => "جهان",
    "uk"         => "بریتانیا",
    "business"   => "اقتصاد",
    "technology" => "فناوری",
    "science"    => "علم و محیط زیست",
    "health"     => "سلامت"
  }.freeze

  def category_name_fa(category)
    CATEGORY_NAMES_FA[category.to_s] || category.to_s
  end

  # Short Persian "x ago" style timestamp for a story.
  def story_timestamp(time)
    return "" unless time

    seconds = (Time.current - time).to_i
    minutes = seconds / 60
    hours   = minutes / 60
    days    = hours / 24

    if minutes < 1   then "لحظاتی پیش"
    elsif minutes < 60 then "#{minutes} دقیقه پیش"
    elsif hours < 24   then "#{hours} ساعت پیش"
    elsif days < 7     then "#{days} روز پیش"
    else l(time.to_date, format: :long) rescue time.strftime("%Y/%m/%d")
    end
  end
end
