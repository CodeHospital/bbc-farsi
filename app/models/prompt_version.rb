# One immutable snapshot of a Prompt's content. `number` is sequential per
# prompt (1, 2, 3, ...); the highest number a Prompt has ever pointed
# `current_prompt_version` at is not necessarily the highest number that
# exists — reverting creates a brand new version with the old content rather
# than rewinding, so history stays a simple, append-only timeline.
class PromptVersion < ApplicationRecord
  belongs_to :prompt
  belongs_to :user, optional: true
  has_many :prompt_version_usages, dependent: :destroy
  has_many :tasks, through: :prompt_version_usages

  validates :content, presence: true
  validates :number, presence: true, uniqueness: { scope: :prompt_id }

  def current? = prompt.current_prompt_version_id == id
end
