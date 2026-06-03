class RewriteArticleJob < ApplicationJob
  queue_as :default

  retry_on Ollama::Errors::RequestError, wait: :polynomially_longer, attempts: 3

  def perform(article_id, server_id:, model:, chain_translate: true)
    raise ArgumentError, "model must be specified" if model.blank?

    article = Article.find(article_id)
    server  = server_id ? OllamaServer.find_by(id: server_id) : nil

    rewrite = article.rewrites.create!(
      llm_model:        model,
      ollama_server_id: server&.id,
      status:           "running"
    )
    article.update!(status: "rewriting")

    content = ArticleRewriter.new(server:).rewrite(article, model:)
    rewrite.update!(content:, status: "completed")
    rewrite.activate!
    article.update!(status: "rewritten")

    if chain_translate
      translate_server, translate_model = pick_translate_target(server)
      if translate_server && translate_model
        TranslateArticleJob.perform_later(rewrite.id,
          server_id: translate_server.id,
          model:     translate_model)
      end
    end
  rescue Ollama::Errors::RequestError => e
    rewrite&.update!(status: "error", error_message: "Ollama error: #{e.message}")
    article&.update!(status: "error")
    raise
  rescue StandardError => e
    rewrite&.update!(status: "error", error_message: e.message)
    article&.update!(status: "error")
    raise
  end

  private

  def pick_translate_target(preferred_server)
    if preferred_server&.translate_model_list&.any?
      [preferred_server, preferred_server.translate_model_list.first]
    else
      OllamaServer.pick(:translate)
    end
  end
end
