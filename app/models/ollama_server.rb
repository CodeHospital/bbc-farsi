class OllamaServer < ApplicationRecord
  has_paper_trail

  has_many :rewrites,     foreign_key: :ollama_server_id, dependent: :nullify
  has_many :translations, foreign_key: :ollama_server_id, dependent: :nullify

  validates :name, presence: true
  validates :url,  presence: true

  scope :enabled, -> { where(enabled: true) }

  # Returns [server, model] for the first enabled server that has models of the given type
  # (:rewrite, :translate, :refine, or :analyze). Returns [nil, nil] if none configured.
  def self.pick(type)
    server = enabled.order(:name).find { |s| s.send(:"#{type}_model_list").any? }
    return [ nil, nil ] unless server
    [ server, server.send(:"#{type}_model_list").first ]
  end

  # [server, model] for the AI bias/fact analysis: the first enabled server
  # with an analysis model, else the rewrite model (behaviour before analysis
  # models were configurable). [nil, nil] if neither is configured.
  def self.pick_for_analysis
    server, model = pick(:analyze)
    server ? [ server, model ] : pick(:rewrite)
  end

  def rewrite_model_list   = parse_models(rewrite_models)
  def translate_model_list = parse_models(translate_models)
  def refine_model_list    = parse_models(refine_models)
  def analyze_model_list   = parse_models(analyze_models)

  def toggle! = update!(enabled: !enabled)

  private

  def parse_models(text)
    text.to_s.split(/[\n,]/).map(&:strip).reject(&:empty?)
  end
end
