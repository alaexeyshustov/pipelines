# Tags an Email or Document with the fixed tags using the native RubyLLM::Judge (decisions API, see ADR 0012).
#
# - One multi-label call: a probability question per tag; every tag at or above +threshold+ is kept.
# - One choice call per kept tag over its existing subtags (skipped when it has none). Nothing is ever created.
# - Writes +source: llm+ taggings (confidence = tag probability). Re-tagging replaces the item's previous llm
#   taggings; +source: manual+ taggings are never changed, and a tag that has one is not judged at all.
# - Provider errors (RubyLLM::Error) propagate before anything is written, so earlier taggings survive.
class Tags::Classifier
  Result = Data.define(:taggings)

  DEFAULT_THRESHOLD = 0.35
  MAX_CHARS = 4_000

  def self.call(item)
    new(item).call
  end

  def self.threshold
    Float(Setting.fetch("tagging_threshold") || ENV.fetch("TAGGING_THRESHOLD", DEFAULT_THRESHOLD))
  end

  def initialize(item)
    @item = item
  end

  def call
    tags = candidate_tags
    return Result.new(taggings: replace_llm_taggings([])) if tags.empty?

    assignments = kept(tags).map { |tag, probability| [ tag, probability, subtag_for(tag) ] } # : Array[[Tag, Float, Subtag?]]
    Result.new(taggings: replace_llm_taggings(assignments))
  end

  private

  def candidate_tags
    manual_tag_ids = @item.taggings.where(source: "manual").pluck(:tag_id)
    Tag.includes(:subtags).where.not(id: manual_tag_ids).order(:id).to_a
  end

  def kept(tags)
    threshold = self.class.threshold
    questions = tags.to_h { |tag| [ tag.name.to_s, tag_question(tag) ] }
    judgment = judge(questions)
    tags.filter_map do |tag|
      answer = judgment.fetch(tag.name.to_s)
      [ tag, answer.probability ] if answer.is_a?(RubyLLM::Probability) && answer.probability >= threshold
    end
  end

  def tag_question(tag)
    { type: :probability, instructions: "Does this item belong to the category '#{tag.name.to_s.humanize}'?" }
  end

  def subtag_for(tag)
    subtags = tag.subtags.to_a
    return if subtags.empty?

    answer = judge({ "subtag" => subtag_question(tag, subtags) }).fetch("subtag")
    subtags.find { |subtag| subtag.name == answer.choice.to_s } if answer.is_a?(RubyLLM::Choice)
  end

  def subtag_question(tag, subtags)
    options = subtags.sort_by { |subtag| subtag.name.to_s }.to_h { |subtag| [ subtag.name.to_s, subtag.name.to_s.humanize ] }
    { type: :choice, instructions: "Which kind of '#{tag.name.to_s.humanize}' item is this?", options: options }
  end

  def judge(questions)
    RubyLLM::Judge.new.judge(
      input,
      questions: questions,
      model: LlmModels.judge,
      owner: @item,
      metadata: { item_id: @item.id }
    )
  end

  def input
    item = @item
    payload =
      if item.is_a?(Email)
        { subject: item.subject, from: item.from_address, body: item.body.to_s.truncate(MAX_CHARS) }
      else
        { title: item.title, text: item.text.to_s.truncate(MAX_CHARS) }
      end
    JSON.parse(payload.to_json) # : json_object
  end

  def replace_llm_taggings(assignments)
    Tagging.transaction do
      @item.taggings.where(source: "llm").destroy_all
      assignments.map do |tag, probability, subtag|
        @item.taggings.create!(tag:, subtag:, source: "llm", confidence: probability)
      end
    end
  end
end
