require "test_helper"

class TaskTest < ActiveSupport::TestCase
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
    assert_equal "content", task.requests.first["key"]
  end

  test "claim_next! claims the oldest task and moves target + article to running" do
    task = Task.enqueue_rewrite(@article, server: @server, model: "qwen3:14b")

    claimed = Task.claim_next!
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

  test "completing a rewrite task stores content, activates it, and chains a translate task" do
    task = Task.enqueue_rewrite(@article, server: @server, model: "qwen3:14b")
    Task.claim_next!

    assert_difference("Task.count", 1) do # the chained translate task
      task.complete!("content" => "<think>noise</think>The rewritten body.")
    end

    rewrite = task.target.reload
    assert_equal "completed", rewrite.status
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
    task = Task.enqueue_translate(rewrite, server: @server, model: "aya-expanse:32b", chain_autopost: false)
    Task.claim_next!

    task.complete!("title" => "عنوان", "body" => "متن")

    translation = task.target.reload
    assert_equal "completed", translation.status
    assert_equal "عنوان", translation.translated_title
    assert_equal "متن", translation.translated_body
    assert translation.active?
    assert_equal "translated", @article.reload.status
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
end
