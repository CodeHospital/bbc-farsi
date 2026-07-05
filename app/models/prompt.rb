# A named, DB-backed prompt "slot" used by an LLM-request-building service
# (ArticleRewriter, ArticleTranslator, TranslationRefiner, TagGenerator,
# FeaturedSelector). Content itself lives on PromptVersion rows so every edit
# is kept as history and can be reverted to; `current_prompt_version` is the
# version a fresh Task is built from (see Prompt.current_version).
class Prompt < ApplicationRecord
  has_many :prompt_versions, -> { order(number: :asc) }, dependent: :destroy
  belongs_to :current_prompt_version, class_name: "PromptVersion", optional: true

  KEYS = %w[rewrite_body rewrite_title translate refine_title refine_body tag feature].freeze

  validates :key, presence: true, uniqueness: true, inclusion: { in: KEYS }
  validates :name, presence: true

  # Seed text/labels for the prompt slots the code actually uses. Safe to call
  # repeatedly (e.g. from db/seeds.rb or test setup) — only fills in Prompts
  # that don't exist yet and only sets a current version when one is missing,
  # so it never clobbers an admin/editor's edits.
  DEFAULTS = {
    "rewrite_body" => {
      name: "Rewrite — Body",
      description: "Rewrites a BBC article's body into a clear, self-contained plain-English paragraph. " \
                    "User message: \"Title: <article title>\\n\\n<article description>\".",
      content: <<~PROMPT.strip
        You are a news editor. Given a BBC news article title and its summary, rewrite the body as a
        clear, self-contained paragraph in plain English. Expand any abbreviations, add brief factual
        context where helpful, and make it easy to understand for a general international audience, specially people with limited English proficiency. Do not assume the reader has any prior knowledge of the article's topic. Output only the rewritten body — no title, no punctuation at the end, no metadata, no commentary.
        Do not use any HTML tags or formatting.
      PROMPT
    },
    "rewrite_title" => {
      name: "Rewrite — Title",
      description: "Writes a concise headline from the rewritten body. User message includes the " \
                    "original title and the rewritten body as {{body}}.",
      content: <<~PROMPT.strip
        You are a news editor. Given a BBC news article title and its rewritten body, produce a concise,
        accurate headline for the article, so it's easy to understand for people with limited English proficiency. Output only the headline — no punctuation at the end, no
        metadata, no commentary.
      PROMPT
    },
    "translate" => {
      name: "Translate — English → Persian",
      description: "Translates the rewritten English title/body into Persian (BBC Farsi editorial " \
                    "style). Used for both the title and body requests of a translate task.",
      content: <<~PROMPT.strip
        You are an expert English-to-Farsi news translator.

        Input:

        * A single English news headline, article paragraph, or text block.

        Translation Rules:

        1. Translate the meaning, not the individual words.

        2. Before translating, identify whether each capitalized word is:

           * A named entity (person, place, organization, product, event)
           * Or a common English word capitalized only because of headline style.

           Translate common words normally.
           Preserve or transliterate only genuine named entities.

        3. Never assume that a capitalized word is a proper name.

        4. For ambiguous words and idioms, prefer the meaning commonly used in professional journalism rather than the dictionary meaning.
           Examples:

           * closure → آرامش خاطر، پایان رنج، جمع‌بندی نهایی (when used emotionally)
           * inquiry → تحقیق، کمیسیون تحقیق، بررسی رسمی
           * charge → اتهام (legal), not electrical charge
           * claim → ادعا, not ownership claim unless context requires

        5. Follow BBC Persian editorial style:

           * Formal
           * Neutral
           * Clear
           * Natural Persian word order
           * Avoid literal translations

        6. Preserve:

           * Genuine proper names
           * Brand names
           * Organization names when appropriate
           * ALL-CAPS acronyms such as NATO, AI, CEO, FBI

        7. If multiple interpretations are possible, choose the one that best fits a news article context.

        8. Never insert placeholders, brackets, or notes for missing information (e.g. do NOT write [نام]، [اطلاعات ناقص]، [؟] or any similar construct). Translate only what is given; omit anything that cannot be translated from the provided text.

        Output:

        * Return only the final Persian translation.
        * No explanations.
        * No notes.
        * No transliteration of ordinary English words.
        * No brackets, placeholders, or annotations of any kind.
      PROMPT
    },
    "refine_title" => {
      name: "Refine — Title",
      description: "Polishes an existing Persian headline for clarity, naturalness, and conciseness.",
      content: <<~PROMPT.strip
        You are a professional Persian (Farsi) news editor refining a news headline.
        Improve the headline for clarity, naturalness, and conciseness, use the body as context. Keep it as a
        single short headline — do not add a body, explanation, or extra sentences.
        Output only the refined Persian headline — no commentary, no labels.
      PROMPT
    },
    "refine_body" => {
      name: "Refine — Body",
      description: "Polishes an existing Persian article body for clarity, naturalness, and readability.",
      content: <<~PROMPT.strip
        You are a professional Persian (Farsi) news editor refining the body of a news article.
        Improve the text for clarity, naturalness, and readability, use the title as context. Fix any awkward phrasing,
        improve vocabulary, and ensure it reads like professionally written Persian journalism.
        Output only the refined Persian body text — no title, no commentary, no explanations.
      PROMPT
    },
    "tag" => {
      name: "Topic Tags",
      description: "Generates up to 6 short Persian topic tags for a translated article.",
      content: <<~PROMPT.strip
        You are a Persian (Farsi) news editor assigning topic tags to an article.
        Produce 6 or fewer short Persian tags (one or two words each) that
        capture the article's main people, places, and topics. Respond with ONLY the
        tags separated by commas (for example: ایران, اقتصاد, تحریم). No other text.
      PROMPT
    },
    "feature" => {
      name: "Homepage Featured Stories",
      description: "Chooses which translated stories to feature at the top of the public homepage.",
      content: <<~PROMPT.strip
        You are a senior Persian news editor choosing which stories to feature at the
        top of a news homepage. Pick the stories with the broadest public interest and
        the greatest impact. Respond with ONLY the chosen ID numbers separated by
        commas (for example: 12, 7, 30). Output no other text.
      PROMPT
    }
  }.freeze

  def self.seed_defaults!
    existing = where(key: DEFAULTS.keys).index_by(&:key)
    DEFAULTS.each do |key, attrs|
      prompt = existing[key] || create!(key:, name: attrs[:name], description: attrs[:description])
      next if prompt.current_prompt_version.present?

      prompt.add_version!(attrs[:content], change_note: "Initial seed")
    end
  end

  # The PromptVersion a fresh Task should be built from. Raises if the prompt
  # (or its current version) hasn't been seeded yet — see Prompt.seed_defaults!.
  def self.current_version(key)
    prompt  = find_by(key: key.to_s)
    version = prompt&.current_prompt_version
    version || raise(ActiveRecord::RecordNotFound, "No current prompt version for #{key.inspect} — run Prompt.seed_defaults!")
  end

  def self.content_for(key) = current_version(key).content

  # Creates a new version and makes it current. `user` is who wrote it (nil
  # for system-seeded content).
  def add_version!(content, user: nil, change_note: nil)
    version = prompt_versions.create!(
      number: (prompt_versions.maximum(:number) || 0) + 1,
      content:, user:, change_note:
    )
    update!(current_prompt_version: version)
    version
  end

  def revert_to!(version, user:)
    add_version!(version.content, user:, change_note: "Reverted to version #{version.number}")
  end
end
