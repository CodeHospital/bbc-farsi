class RefineTranslationJob < ApplicationJob
  queue_as :default

  retry_on Ollama::Errors::RequestError, wait: :polynomially_longer, attempts: 3

  def perform(translation_id, server_id:, model:)
    raise ArgumentError, "model must be specified" if model.blank?

    source = Translation.find(translation_id)
    server = server_id ? OllamaServer.find_by(id: server_id) : nil

    new_translation = source.article.translations.create!(
      rewrite:          source.rewrite,
      llm_model:        model,
      ollama_server_id: server&.id,
      prompt_name:      "refine",
      status:           "running"
    )

    result = TranslationRefiner.new(server:).refine(source, model:)
    new_translation.update!(
      translated_title: result[:translated_title],
      translated_body:  result[:translated_body],
      status:           "completed"
    )
    new_translation.activate!
  rescue Ollama::Errors::RequestError => e
    new_translation&.update!(status: "error", error_message: "Ollama error: #{e.message}")
    raise
  rescue StandardError => e
    new_translation&.update!(status: "error", error_message: e.message)
    raise
  end
end
