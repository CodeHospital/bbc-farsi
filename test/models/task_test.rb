require "test_helper"

class TaskTest < ActiveSupport::TestCase
  include ActionCable::TestHelper
  setup do
    @article = create_article
    @server  = OllamaServer.create!(
      name: "Local", url: "http://localhost:11434",
      rewrite_models: "qwen3:14b", translate_models: "aya-expanse:32b", refine_models: "qwen3:14b"
    )
  end

  test "enqueue_rewrite creates a pending Rewrite and a pending rewrite Task with requests" do
    task = Task.enqueue_rewrite(@article, server: @server, model: "qwen3:14b")

    assert_equal "rewrite", task.kind
    assert_equal "pending", task.status
    assert_equal "qwen3:14b", task.model
    assert_equal @server, task.ollama_server
    assert_instance_of Rewrite, task.target
    assert_equal "pending", task.target.status
    assert_equal "body", task.requests.first["key"]
    assert_equal "title", task.requests.second["key"]
  end

  test "claim_next! claims the oldest task and moves target + article to running" do
    task = Task.enqueue_rewrite(@article, server: @server, model: "qwen3:14b")

    claimed = Task.claim_next!(models: [ "qwen3:14b" ])
    assert_equal task, claimed
    assert_equal "claimed", claimed.status
    assert_equal 1, claimed.attempts
    assert_not_nil claimed.claimed_at
    assert_equal "running", claimed.target.reload.status
    assert_equal "rewriting", @article.reload.status
  end

  test "claim_next! accepts a supported model prefix when exact match is unavailable" do
    task = Task.enqueue_rewrite(@article, server: @server, model: "qwen3:14b")

    claimed = Task.claim_next!(models: [ "qwen3", "gemma" ])
    assert_equal task, claimed
    assert_equal "claimed", claimed.status
    assert_equal 1, claimed.attempts
    assert_not_nil claimed.claimed_at
    assert_equal "running", claimed.target.reload.status
    assert_equal "rewriting", @article.reload.status
  end

  test "claim_next! returns nil when the queue is empty" do
    assert_nil Task.claim_next!
  end

  test "claim_next! prefers higher priority over insertion order" do
    Task.enqueue_rewrite(@article, server: @server, model: "qwen3:14b")
    newer_but_urgent = Task.enqueue_rewrite(create_article, server: @server, model: "qwen3:14b")
    newer_but_urgent.reprioritize!("up") # priority 1 beats the older priority-0 task

    assert_equal newer_but_urgent, Task.claim_next!
  end

  test "reclaim_stale! returns timed-out claimed tasks to pending" do
    task = Task.enqueue_rewrite(@article, server: @server, model: "qwen3:14b")
    Task.claim_next!
    assert_equal "claimed", task.reload.status

    # Fresh claim is not stale yet.
    assert_equal 0, Task.reclaim_stale!
    assert_equal "claimed", task.reload.status

    # Age the claim past the threshold.
    task.update_column(:claimed_at, (Task::STALE_AFTER + 1.minute).ago)
    assert_equal 1, Task.reclaim_stale!

    assert_equal "pending", task.reload.status
    assert_nil task.claimed_at
    assert_equal "pending", task.target.reload.status
  end

  test "claim_next! reclaims a stale task and can re-claim it" do
    task = Task.enqueue_rewrite(@article, server: @server, model: "qwen3:14b")
    Task.claim_next!
    task.update_column(:claimed_at, (Task::STALE_AFTER + 1.minute).ago)

    reclaimed = Task.claim_next! # reclaims, then re-claims the same task
    assert_equal task, reclaimed
    assert_equal "claimed", reclaimed.status
    assert_equal 2, reclaimed.attempts
  end

  test "reprioritize! steps priority up/down and ignores unknown directions" do
    task = Task.enqueue_rewrite(@article, server: @server, model: "qwen3:14b")
    assert_equal 0, task.priority

    task.reprioritize!("up")
    assert_equal 1, task.reload.priority

    task.reprioritize!("down")
    task.reprioritize!("down")
    assert_equal(-1, task.reload.priority)

    task.reprioritize!("sideways")
    assert_equal(-1, task.reload.priority)
  end

  test "reprioritize! mirrors the delta onto llmarkt when the task has an external job id" do
    task = Task.enqueue_rewrite(@article, server: @server, model: "qwen3:14b")
    task.update_column(:external_job_id, "job-1")
    captured = nil

    stub_llmarkt_config
    LlmarktClient.stub(:update_job_priority, ->(job_id, delta) { captured = [ job_id, delta ]; { "priority" => 1 } }) do
      task.reprioritize!("up")
    end
    assert_equal [ "job-1", 1 ], captured
  ensure
    restore_llmarkt_config
  end

  test "retry! requeues the same job on llmarkt in place when it was submitted there" do
    task = Task.enqueue_rewrite(@article, server: @server, model: "qwen3:14b")
    Task.claim_next!
    task.update_column(:external_job_id, "job-1")
    task.fail!("worker timeout")

    stub_llmarkt_config
    LlmarktClient.stub(:retry_job, ->(job_id) { { "status" => "pending" } }) do
      task.retry!
    end
    restore_llmarkt_config

    task.reload
    assert_equal "claimed", task.status
    assert_equal "job-1", task.external_job_id # unchanged — same llmarkt job
    assert_nil task.error_message
    assert_equal "running", task.target.reload.status
  end

  test "retry! falls back to a plain local requeue when llmarkt retry fails" do
    task = Task.enqueue_rewrite(@article, server: @server, model: "qwen3:14b")
    Task.claim_next!
    task.update_column(:external_job_id, "job-1")
    task.fail!("worker timeout")

    stub_llmarkt_config
    LlmarktClient.stub(:retry_job, ->(job_id) { raise LlmarktClient::Error, "not failed" }) do
      task.retry!
    end
    restore_llmarkt_config

    task.reload
    assert_equal "pending", task.status
    assert_nil task.error_message
    assert_equal "pending", task.target.reload.status
  end

  test "retry! is a plain local requeue when the task was never submitted to llmarkt" do
    task = Task.enqueue_rewrite(@article, server: @server, model: "qwen3:14b")
    Task.claim_next!
    task.fail!("worker timeout")

    task.retry!

    assert_equal "pending", task.reload.status
  end

  test "completing a rewrite task stores content, activates it, and chains a translate task" do
    task = Task.enqueue_rewrite(@article, server: @server, model: "qwen3:14b")
    Task.claim_next!

    assert_difference("Task.count", 1) do # the chained translate task
      task.complete!("title" => "<think>noise</think>Floods Worsen Across UK", "body" => "<think>noise</think>The rewritten body.")
    end

    rewrite = task.target.reload
    assert_equal "completed", rewrite.status
    assert_equal "Floods Worsen Across UK", rewrite.rewritten_title
    assert_equal "The rewritten body.", rewrite.content
    assert rewrite.active?
    assert_equal "rewritten", @article.reload.status
    assert_equal "completed", task.reload.status

    chained = Task.where(kind: "translate").last
    assert_instance_of Translation, chained.target
    assert_equal rewrite, chained.target.rewrite
  end

  test "completing a translate task stores both fields and marks the article translated" do
    rewrite = create_rewrite(article: @article)
    task = Task.enqueue_translate(rewrite, server: @server, model: "aya-expanse:32b", chain_refine: false)
    Task.claim_next!

    task.complete!("title" => "عنوان", "body" => "متن")

    translation = task.target.reload
    assert_equal "completed", translation.status
    assert_equal "عنوان", translation.translated_title
    assert_equal "متن", translation.translated_body
    assert translation.active?
    assert_equal "translated", @article.reload.status
  end

  test "completing a translate task chains a refine task when chain_refine is set" do
    rewrite = create_rewrite(article: @article)
    task = Task.enqueue_translate(rewrite, server: @server, model: "aya-expanse:32b") # chain_refine defaults true
    Task.claim_next!

    assert_difference("Task.where(kind: 'refine').count", 1) do
      task.complete!("title" => "عنوان", "body" => "متن")
    end

    refine_task = Task.where(kind: "refine").last
    assert_instance_of Translation, refine_task.target
    assert_equal "refine", refine_task.target.prompt_name
    assert_equal rewrite, refine_task.target.rewrite
  end

  test "fail! marks the target and article as errored" do
    task = Task.enqueue_rewrite(@article, server: @server, model: "qwen3:14b")
    Task.claim_next!

    task.fail!("Ollama timed out")

    assert_equal "failed", task.reload.status
    assert_equal "Ollama timed out", task.error_message
    assert_equal "error", task.target.reload.status
    assert_equal "error", @article.reload.status
  end

  test "requeue! puts a failed task back to pending and clears its target error" do
    task = Task.enqueue_rewrite(@article, server: @server, model: "qwen3:14b")
    Task.claim_next!
    task.fail!("boom")

    Task.find(task.id).requeue! # admin loads the task fresh before retrying

    assert_equal "pending", task.reload.status
    assert_nil task.claimed_at
    assert_nil task.error_message
    assert_equal "pending", task.target.reload.status
    assert_equal task, Task.claim_next!
  end

  test "claim_next! with models list only claims a matching task" do
    task_a = Task.enqueue_rewrite(@article, server: @server, model: "qwen3:14b")
    task_b = Task.enqueue_rewrite(create_article, server: @server, model: "aya-expanse:32b")

    claimed = Task.claim_next!(models: [ "qwen3:14b" ])

    assert_equal task_a, claimed
    assert_equal "claimed", task_a.reload.status
    assert_equal "pending", task_b.reload.status
  end

  test "claim_next! with models list returns nil when no matching task exists" do
    Task.enqueue_rewrite(@article, server: @server, model: "qwen3:14b")

    claimed = Task.claim_next!(models: [ "some-other-model:7b" ])

    assert_nil claimed
  end

  test "claim_next! with empty models list claims any task" do
    task = Task.enqueue_rewrite(@article, server: @server, model: "qwen3:14b")

    claimed = Task.claim_next!(models: [])

    assert_equal task, claimed
  end

  test "model is required" do
    rewrite = create_rewrite(article: @article)
    invalid = Task.new(kind: "rewrite", target: rewrite, status: "pending")
    assert_not invalid.valid?
    assert_includes invalid.errors[:model], "can't be blank"
  end

  # ── Action Cable broadcast tests ────────────────────────────────────────────
  #
  # broadcast_refresh_to uses Turbo's internal stream_name_from which returns
  # the raw streamable string, NOT the "turbo:streams:…" prefixed form that
  # broadcasting_for returns. So we assert on the raw stream name directly.

  test "mark_claimed! broadcasts a Turbo refresh for the article" do
    Task.enqueue_rewrite(@article, server: @server, model: "qwen3:14b")
    article_stream = "article_#{@article.id}_tasks"

    assert_broadcasts(article_stream, 1) { Task.claim_next! }
  end

  test "complete! broadcasts a Turbo refresh for the article" do
    task = Task.enqueue_rewrite(@article, server: @server, model: "qwen3:14b")
    Task.claim_next!
    article_stream = "article_#{@article.id}_tasks"

    assert_broadcasts(article_stream, 1) { task.complete!("content" => "Rewritten body.") }
  end

  test "fail! broadcasts a Turbo refresh for the article" do
    task = Task.enqueue_rewrite(@article, server: @server, model: "qwen3:14b")
    Task.claim_next!
    article_stream = "article_#{@article.id}_tasks"

    assert_broadcasts(article_stream, 1) { task.fail!("Worker timeout") }
  end

  test "translate task complete! broadcasts a refresh for the correct article" do
    rewrite = create_rewrite(article: @article)
    task = Task.enqueue_translate(rewrite, server: @server, model: "aya-expanse:32b", chain_refine: false)
    Task.claim_next!
    article_stream = "article_#{@article.id}_tasks"

    assert_broadcasts(article_stream, 1) { task.complete!("title" => "عنوان", "body" => "متن") }
  end

  test "broadcast goes to the article's stream, not a different article's stream" do
    other_article = create_article
    Task.enqueue_rewrite(@article, server: @server, model: "qwen3:14b")
    other_stream = "article_#{other_article.id}_tasks"

    assert_no_broadcasts(other_stream) { Task.claim_next! }
  end

  # ── feature kind (targetless homepage selection) ──────────────────────────

  test "enqueue_feature creates a pending feature task anchored on a candidate" do
    translation = create_translation(attrs: { translated_title: "عنوان مهم" })
    task = Task.enqueue_feature([ translation ], server: @server, model: "qwen3:14b")

    assert_equal "feature", task.kind
    assert_equal "pending", task.status
    assert_equal translation, task.target # anchor only, never mutated
    assert_equal "featured", task.requests.first["key"]
  end

  test "claiming a feature task does not mutate its anchor target" do
    translation = create_translation(attrs: { translated_title: "عنوان", status: "completed" })
    Task.enqueue_feature([ translation ], server: @server, model: "qwen3:14b")

    Task.claim_next!

    assert_equal "completed", translation.reload.status
  end

  test "feature task complete! caches the chosen article ids" do
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    translation = create_translation(attrs: { translated_title: "عنوان" })
    task = Task.enqueue_feature([ translation ], server: @server, model: "qwen3:14b")

    assert_equal task, Task.claim_next!
    task.complete!("featured" => translation.article_id.to_s)

    assert_equal "completed", task.reload.status
    assert_equal [ translation.article_id ], FeaturedSelector.featured_ids
  ensure
    Rails.cache = original
  end

  # ── tag kind (AI tags cached per article) ─────────────────────────────────

  test "enqueue_tag targets the translation and claiming leaves it untouched" do
    translation = create_translation(attrs: { translated_title: "عنوان", status: "completed" })
    task = Task.enqueue_tag(translation, server: @server, model: "qwen3:14b")

    assert_equal "tag", task.kind
    assert_equal translation, task.target
    Task.claim_next!
    assert_equal "completed", translation.reload.status # not flipped to "running"
  end

  test "tag task complete! caches the generated tags for the article" do
    original = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    translation = create_translation(attrs: { translated_title: "عنوان" })
    task = Task.enqueue_tag(translation, server: @server, model: "qwen3:14b")

    Task.claim_next!
    task.complete!("tags" => "ایران, اقتصاد")

    assert_equal "completed", task.reload.status
    assert_equal %w[ایران اقتصاد], TagGenerator.tags_for(translation.article)
  ensure
    Rails.cache = original
  end
end
