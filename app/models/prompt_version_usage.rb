# Records that a Task's request (identified by its `requests` "key", e.g.
# "body"/"title"/"tags"/"featured") was built from a specific PromptVersion —
# so a Task and the target it produced (via task.target) can always show
# exactly which prompt version created them, even after the Prompt is edited
# again later.
class PromptVersionUsage < ApplicationRecord
  belongs_to :prompt_version
  belongs_to :task

  validates :request_key, presence: true
end
