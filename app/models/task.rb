# A unit of LLM work persisted in a database-backed queue.
#
# Replaces the old Solid Queue background jobs. Instead of the Rails app calling
# Ollama itself, it creates a Task here; a separate worker client (which has
# access to Ollama) claims the task over the protected API, runs the LLM
# requests, and posts the result back. See `worker/worker.rb`.
#
# Each task drives an already-created target record (a Rewrite or a Translation)
# through the pending -> claimed -> completed/failed lifecycle.
class Task < ApplicationRecord
  belongs_to :target, polymorphic: true
  belongs_to :ollama_server, optional: true

  KINDS    = %w[rewrite translate refine].freeze
  STATUSES = %w[pending claimed completed failed].freeze

  # A claimed task whose worker hasn't reported back within this window is
  # presumed dead; the task is returned to the queue (see `reclaim_stale!`).
  STALE_AFTER = 1.hour

  validates :kind,     inclusion: { in: KINDS }
  validates :status,   inclusion: { in: STATUSES }
  validates :model,    presence: true
  validates :priority, numericality: { only_integer: true }

  scope :pending, -> { where(status: "pending") }

  # Highest priority first, then oldest first — the order the worker claims in.
  scope :by_priority, -> { order(priority: :desc, created_at: :asc) }

  # Claimed tasks that have been in flight longer than STALE_AFTER.
  scope :stale, -> { where(status: "claimed").where(claimed_at: ..STALE_AFTER.ago) }

  # ── Enqueue (called by admin controllers / FeedIngestor) ──────────────────

  def self.enqueue_rewrite(article, server:, model:, chain_translate: true)
    rewrite = article.rewrites.create!(
      llm_model: model, ollama_server_id: server&.id, status: "pending"
    )
    create!(
      kind: "rewrite", target: rewrite, ollama_server: server, model:,
      requests: ArticleRewriter.requests(article), chain_translate:
    )
  end

  def self.enqueue_translate(rewrite, server:, model:, chain_autopost: true)
    translation = rewrite.article.translations.create!(
      rewrite:, llm_model: model, ollama_server_id: server&.id,
      prompt_name: "prompt", status: "pending"
    )
    create!(
      kind: "translate", target: translation, ollama_server: server, model:,
      requests: ArticleTranslator.requests(rewrite), chain_autopost:
    )
  end

  def self.enqueue_refine(source_translation, server:, model:)
    new_translation = source_translation.article.translations.create!(
      rewrite: source_translation.rewrite, llm_model: model,
      ollama_server_id: server&.id, prompt_name: "refine", status: "pending"
    )
    create!(
      kind: "refine", target: new_translation, ollama_server: server, model:,
      requests: TranslationRefiner.requests(source_translation)
    )
  end

  # ── Worker: claim the next pending task atomically ────────────────────────

  # Pass `models:` with a non-empty array to restrict to tasks whose model
  # is in the list (exact match). Omit or pass nil/[] to accept any model.
  def self.claim_next!(models: nil)
    transaction do
      reclaim_stale!
      scope = pending.by_priority
      scope = scope.where(model: models) if models.present?
      task  = scope.lock.first
      task&.mark_claimed!
      task
    end
  end

  # Return timed-out claimed tasks to the queue so another worker can pick them
  # up. Folded into claim_next! (self-healing on every poll) and also exposed as
  # `bin/rails bbc:reclaim_stale` for when no worker is polling. Returns the
  # number of tasks reclaimed.
  def self.reclaim_stale!
    stale.to_a.each(&:requeue!).size
  end

  def mark_claimed!
    update!(status: "claimed", claimed_at: Time.current, attempts: attempts + 1)
    target.update!(status: "running")
    case kind
    when "rewrite"   then target.article.update!(status: "rewriting")
    when "translate" then target.article.update!(status: "translating")
    end
    broadcast_article_refresh
  end

  # ── Worker: post results back ─────────────────────────────────────────────

  def complete!(responses)
    self.responses = responses

    case kind
    when "rewrite"
      target.update!(content: ArticleRewriter.process(responses), status: "completed")
      target.activate!
      target.article.update!(status: "rewritten")
      chain_translate!
    when "translate"
      target.update!(ArticleTranslator.process(responses).merge(status: "completed"))
      target.activate!
      target.article.update!(status: "translated")
      chain_autopost!
    when "refine"
      target.update!(TranslationRefiner.process(responses).merge(status: "completed"))
      target.activate!
    end

    update!(status: "completed", completed_at: Time.current)
    broadcast_article_refresh
  end

  def fail!(message)
    target.update!(status: "error", error_message: message.to_s)
    target.article&.update!(status: "error")
    update!(status: "failed", error_message: message.to_s)
    broadcast_article_refresh
  end

  # Admin queue ordering. "up" is claimed sooner (higher number).
  def reprioritize!(direction)
    step = { "up" => 1, "down" => -1 }.fetch(direction.to_s, 0)
    update!(priority: priority + step)
  end

  # Put a failed/stuck task back on the queue for another worker to claim.
  def requeue!
    target.update!(status: "pending", error_message: nil)
    update!(status: "pending", claimed_at: nil, completed_at: nil,
            error_message: nil, responses: nil)
  end

  private

  def chain_translate!
    return unless chain_translate

    server, model = pick_translate_target
    Task.enqueue_translate(target, server:, model:) if server && model
  end

  def pick_translate_target
    if ollama_server&.translate_model_list&.any?
      [ ollama_server, ollama_server.translate_model_list.first ]
    else
      OllamaServer.pick(:translate)
    end
  end

  def chain_autopost!
    return unless chain_autopost

    Autoposter.post_translation(target)
  rescue StandardError => e
    Rails.logger.error "Autopost after task #{id} failed: #{e.message}"
  end

  def broadcast_article_refresh
    article = target.article
    Turbo::StreamsChannel.broadcast_refresh_to("article_#{article.id}_tasks")
  rescue StandardError => e
    Rails.logger.error "ActionCable broadcast failed for task #{id}: #{e.message}"
  end
end
