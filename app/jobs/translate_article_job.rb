class TranslateArticleJob < ApplicationJob
  queue_as :default

  retry_on Ollama::Errors::RequestError, wait: :polynomially_longer, attempts: 3

  def perform(rewrite_id, server_id:, model:, chain_autopost: true)
    raise ArgumentError, "model must be specified" if model.blank?

    rewrite = Rewrite.find(rewrite_id)
    article = rewrite.article
    server  = server_id ? OllamaServer.find_by(id: server_id) : nil

    translation = article.translations.create!(
      rewrite:,
      llm_model:        model,
      ollama_server_id: server&.id,
      prompt_name:      "prompt",
      status:           "running"
    )
    article.update!(status: "translating")

    result = ArticleTranslator.new(server:).translate(rewrite, model:)
    translation.update!(
      translated_title: result[:translated_title],
      translated_body:  result[:translated_body],
      status:           "completed"
    )
    translation.activate!
    article.update!(status: "translated")

    AutopostJob.perform_later(translation.id) if chain_autopost
  rescue Ollama::Errors::RequestError => e
    translation&.update!(status: "error", error_message: "Ollama error: #{e.message}")
    article&.update!(status: "error")
    raise
  rescue StandardError => e
    translation&.update!(status: "error", error_message: e.message)
    article&.update!(status: "error")
    raise
  end
end
