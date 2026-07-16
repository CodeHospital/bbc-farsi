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
  has_many :prompt_version_usages, dependent: :destroy
  has_many :prompt_versions, through: :prompt_version_usages

  KINDS    = %w[rewrite translate refine feature tag].freeze
  STATUSES = %w[pending claimed completed failed].freeze

  # Kinds that read their target but never change its status. `feature` anchors
  # on a candidate only to satisfy the NOT NULL target; `tag` annotates an
  # already-completed translation. Their results live in Rails.cache.
  CACHE_RESULT_KINDS = %w[feature tag].freeze

  # The timeout llmarkt is told to enforce on a job it's running for us (see
  # LlmarktSubmitter#submit_request). STALE_AFTER (below) must stay
  # comfortably above this: a claimed task that's still a legitimately
  # in-flight llmarkt job must never be reclaimed and handed to the Ollama
  # worker too, since that means two backends execute the same work and the
  # eventual late webhook races the worker's own completion (plan2.md C-4).
  LLMARKT_JOB_TIMEOUT = 20.minutes

  # A claimed task whose worker hasn't reported back within this window is
  # presumed dead; the task is returned to the queue (see `reclaim_stale!`).
  # Kept above LLMARKT_JOB_TIMEOUT plus slack for webhook delivery/network
  # latency (see the comment on that constant).
  STALE_AFTER = LLMARKT_JOB_TIMEOUT + 10.minutes

  validates :kind,     inclusion: { in: KINDS }
  validates :status,   inclusion: { in: STATUSES }
  validates :model,    presence: true
  validates :priority, numericality: { only_integer: true }

  # Each request built by the *Rewriter/*Translator/*Refiner/*Generator/*Selector
  # services carries a `prompt_version_id` for the Prompt it was built from
  # (see Prompt.current_version). Record that link so the Task — and the
  # target it produces — can always show which prompt version created it.
  after_create :record_prompt_version_usages

  # llmarkt is the primary backend: as soon as a task is enqueued, submit it to
  # the llmarkt grid (which calls back via webhook). If llmarkt is disabled or
  # submission fails, the task stays `pending` and the Ollama worker fallback
  # claims it. Runs after commit so the target and requests are persisted.
  after_create_commit :submit_to_llmarkt

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
      priority: 0,
      kind: "rewrite", target: rewrite, ollama_server: server, model:,
      requests: ArticleRewriter.requests(article), chain_translate:
    )
  end

  def self.enqueue_translate(rewrite, server:, model:, chain_refine: true)
    translation = rewrite.article.translations.create!(
      rewrite:, llm_model: model, ollama_server_id: server&.id,
      prompt_name: "prompt", status: "pending"
    )
    create!(
      priority: 1,
      kind: "translate", target: translation, ollama_server: server, model:,
      requests: ArticleTranslator.requests(rewrite), chain_refine:
    )
  end

  def self.enqueue_refine(source_translation, server:, model:, chain_autopost: true)
    new_translation = source_translation.article.translations.create!(
      rewrite: source_translation.rewrite, llm_model: model,
      ollama_server_id: server&.id, prompt_name: "refine", status: "pending"
    )
    create!(
      priority: 2,
      kind: "refine", target: new_translation, ollama_server: server, model:,
      requests: TranslationRefiner.requests(source_translation), chain_autopost:
    )
  end

  # Enqueue an AI homepage-feature selection over the given candidate
  # Translations. The result is a set of article IDs cached by FeaturedSelector
  # when the worker completes the task. The schema requires a target, so we
  # anchor on the newest candidate purely to satisfy it — feature tasks never
  # mutate their target (see #mark_claimed!, #complete!, #fail!).
  def self.enqueue_feature(candidates, server:, model:, limit: FeaturedSelector::DEFAULT_LIMIT)
    create!(
      kind: "feature", target: candidates.first, ollama_server: server, model:,
      requests: FeaturedSelector.requests(candidates, limit:)
    )
  end

  # Enqueue AI tag generation for a completed translation. The target is the
  # translation itself (read-only — its status is never changed); the resulting
  # tags are cached per article by TagGenerator when the worker completes.
  def self.enqueue_tag(translation, server:, model:)
    create!(
      kind: "tag", target: translation, ollama_server: server, model:,
      requests: TagGenerator.requests(translation)
    )
  end

  # ── Worker: claim the next pending task atomically ────────────────────────

  # Pass `models:` with a non-empty array to restrict to tasks whose model
  # is in the list (exact match). Omit or pass nil/[] to accept any model.
  def self.claim_next!(models: nil)
    # Outside the claim transaction (H-12): reclaiming N stale tasks touches
    # each one's target too, and there's no reason to hold the claim lock
    # while that runs — it's idempotent and safe to interleave with claims.
    reclaim_stale!

    transaction do
      # "FOR UPDATE SKIP LOCKED" lets concurrent worker polls claim different
      # rows instead of serializing on the head of the queue (PostgreSQL
      # only — Arel::Visitors::SQLite drops lock clauses entirely, so this is
      # a no-op on SQLite, which is fine since SQLite already serializes
      # writers at the connection level).
      scope = pending.by_priority
      scope = scope.where(model: models) if models.present?
      task  = scope.lock("FOR UPDATE SKIP LOCKED").first
      if task.nil? && models.present?
        patterns = models.map { |m| "#{m}%" }
        scope = pending.by_priority.where(Task.arel_table[:model].matches_any(patterns))
        task  = scope.lock("FOR UPDATE SKIP LOCKED").first
      end
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

  # Admin house-keeping: cancel every queued (pending) task. Non-destructive and
  # reversible — tasks are marked "failed" with an "Aborted by admin" note (so
  # they can be re-queued from the Tasks page) and their work-producing targets
  # (rewrite/translate/refine) are stopped. `feature`/`tag` anchors are left
  # untouched (their targets are unrelated, already-completed records). Returns
  # the number of tasks aborted.
  ABORT_MESSAGE = "Aborted by admin".freeze

  def self.abort_pending!
    pending_tasks = pending
    count = pending_tasks.count
    return 0 if count.zero?

    target_owning = pending_tasks.where.not(kind: CACHE_RESULT_KINDS)
    { "Rewrite" => Rewrite, "Translation" => Translation }.each do |type_name, klass|
      target_ids = target_owning.where(target_type: type_name).pluck(:target_id)
      klass.where(id: target_ids)
           .update_all(status: "error", error_message: ABORT_MESSAGE, updated_at: Time.current)
    end

    pending_tasks.update_all(status: "failed", error_message: ABORT_MESSAGE, updated_at: Time.current)
    count
  end

  def mark_claimed!
    update!(status: "claimed", claimed_at: Time.current, attempts: attempts + 1, error_message: nil)
    return if CACHE_RESULT_KINDS.include?(kind) # don't touch the (read-only) target

    target.update!(status: "running", error_message: nil)
    case kind
    when "rewrite"   then target.article.update!(status: "rewriting")
    when "translate" then target.article.update!(status: "translating")
    end
    broadcast_article_refresh
  end

  def completed? = status == "completed"

  # ── Worker: post results back ─────────────────────────────────────────────

  # Idempotent (H-5/C-4): a duplicate or out-of-order webhook/worker report
  # for an already-completed task is a no-op instead of re-running chains
  # (which would enqueue a second translate/refine task and a second Telegram
  # notification). All target/article/task state writes happen inside one
  # transaction, and the task is marked "completed" before any side-effect
  # chain runs, so a chain failure can never be mistaken for the primary
  # result failing (see the rescue in Api::TasksController#complete, which
  # would otherwise flip an already-completed target to "error").
  def complete!(responses)
    return if completed?

    self.responses = responses

    transaction do
      case kind
      when "rewrite"
        target.update!(ArticleRewriter.process(responses).merge(status: "completed"))
        target.activate!
        target.article.update!(status: "rewritten")
      when "translate"
        target.update!(ArticleTranslator.process(responses).merge(status: "completed"))
        target.activate!
        target.article.update!(status: "translated")
      when "refine"
        target.update!(TranslationRefiner.process(responses).merge(status: "completed"))
        target.activate!
      when "feature"
        FeaturedSelector.store(FeaturedSelector.process(responses))
      when "tag"
        TagGenerator.store(target.article_id, TagGenerator.process(responses))
      end

      update!(status: "completed", completed_at: Time.current)
    end

    case kind
    when "rewrite"  then chain_translate!
    when "translate" then chain_refine!
    when "refine"
      chain_autopost!
      notify_admin_bot!
    end

    broadcast_article_refresh
  end

  # A late failure (e.g. a llmarkt job timeout webhook that arrives after the
  # Ollama worker fallback already completed the same reclaimed task) must
  # never clobber a completed result (C-4).
  def fail!(message)
    return if completed?

    if CACHE_RESULT_KINDS.include?(kind)
      return update!(status: "failed", error_message: message.to_s)
    end

    target.update!(status: "error", error_message: message.to_s)
    target.article&.update!(status: "error")
    update!(status: "failed", error_message: message.to_s)
    broadcast_article_refresh
  end

  # Admin queue ordering. "up" is claimed sooner (higher number). Mirrored onto
  # llmarkt's own job priority (best-effort) when this task was submitted there.
  def reprioritize!(direction)
    step = { "up" => 1, "down" => -1 }.fetch(direction.to_s, 0)
    update!(priority: priority + step)
    LlmarktSubmitter.update_priority(self, step)
  end

  # Retry a failed task. Prefers requeuing the same job in place on llmarkt
  # (job_id unchanged, responses already recorded for earlier steps in the
  # chain are kept) when the task was submitted there; falls back to a plain
  # local requeue (picked up by the Ollama worker) otherwise.
  def retry!
    return requeue! unless LlmarktSubmitter.retry_task(self)

    mark_claimed!
  end

  # Put a failed/stuck task back on the queue for another worker to claim.
  # Clears external_job_id (C-4): once a task is handed back to the Ollama
  # worker fallback, any in-flight llmarkt job for it is no longer this
  # task's job — priority/retry mirroring must not target it, and a late
  # webhook for it must be recognized as stale (see
  # LlmarktSubmitter.handle_callback/handle_failure).
  def requeue!
    target.update!(status: "pending", error_message: nil)
    update!(status: "pending", claimed_at: nil, completed_at: nil,
            error_message: nil, responses: nil, external_job_id: nil)
  end

  private

  def record_prompt_version_usages
    Array(requests).each do |request|
      version_id = request["prompt_version_id"] || request[:prompt_version_id]
      next unless version_id

      key = request["key"] || request[:key]
      prompt_version_usages.create!(prompt_version_id: version_id, request_key: key)
    end
  end

  # Hand the freshly-created task to the llmarkt grid. No-op when llmarkt is not
  # configured (LlmarktSubmitter.submit_task returns false and the task is left
  # pending for the Ollama worker). Errors never bubble up into enqueue.
  def submit_to_llmarkt
    LlmarktSubmitter.submit_task(self)
  rescue StandardError => e
    Rails.logger.error("Task#submit_to_llmarkt task=#{id}: #{e.class}: #{e.message}")
  end

  # Runs after the primary result is already committed as "completed" (H-5),
  # so a failure here must never look like the rewrite/translate itself
  # failed — log and move on instead of raising.
  def chain_translate!
    return unless chain_translate

    server, model = pick_translate_target
    Task.enqueue_translate(target, server:, model:) if server && model
  rescue StandardError => e
    Rails.logger.error "Chain translate after task #{id} failed: #{e.message}"
  end

  def chain_refine!
    return unless chain_refine

    server, model = OllamaServer.pick(:refine)
    return unless server && model
    Task.enqueue_refine(target, server:, model:)
  rescue StandardError => e
    Rails.logger.error "Chain refine after task #{id} failed: #{e.message}"
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

  # DM an admin/editor via the Telegram admin bot with rewrite/retranslate/
  # refine/publish/manual-edit buttons. Only fired once a translation has been
  # through the "refine" (smart-edit) pass — a freshly machine-translated
  # draft is not yet worth interrupting an editor for. No-op when
  # TelegramAdminBot isn't configured (see TelegramAdminNotifier.notify).
  def notify_admin_bot!
    TelegramAdminNotifier.notify(target)
  rescue StandardError => e
    Rails.logger.error "Admin bot notify after task #{id} failed: #{e.message}"
  end

  def broadcast_article_refresh
    article = target&.article
    return unless article

    Turbo::StreamsChannel.broadcast_refresh_to("article_#{article.id}_tasks")
  rescue StandardError => e
    Rails.logger.error "ActionCable broadcast failed for task #{id}: #{e.message}"
  end
end
