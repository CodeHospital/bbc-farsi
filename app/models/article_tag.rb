# Join row: one tag on one article.
class ArticleTag < ApplicationRecord
  has_paper_trail

  belongs_to :article, touch: true
  belongs_to :tag

  validates :tag_id, uniqueness: { scope: :article_id }
end
