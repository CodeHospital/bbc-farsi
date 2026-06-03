class OllamaServer < ApplicationRecord
  has_many :rewrites,     foreign_key: :ollama_server_id, dependent: :nullify
  has_many :translations, foreign_key: :ollama_server_id, dependent: :nullify

  validates :name, presence: true
  validates :url,  presence: true

  scope :enabled, -> { where(enabled: true) }

  # Returns [server, model] for the first enabled server that has models of the given type
  # (:rewrite, :translate, or :refine). Returns [nil, nil] if none configured.
  def self.pick(type)
    server = enabled.order(:name).find { |s| s.send(:"#{type}_model_list").any? }
    return [nil, nil] unless server
    [server, server.send(:"#{type}_model_list").first]
  end

  def rewrite_model_list   = parse_models(rewrite_models)
  def translate_model_list = parse_models(translate_models)
  def refine_model_list    = parse_models(refine_models)

  def toggle! = update!(enabled: !enabled)

  private

  def parse_models(text)
    text.to_s.split(/[\n,]/).map(&:strip).reject(&:empty?)
  end
end
