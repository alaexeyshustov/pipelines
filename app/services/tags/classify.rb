# Classifies one Email or Document with Tags::Classifier and records the outcome in its +classification_status+.
#
# Only a pending or failed record is classified; a tagged or untagged one is skipped (no LLM call) unless +force:+ is
# set, which classifies it again (Tags::Classifier then replaces only its llm taggings). After a successful run the
# status is "tagged" when the record has any tagging, manual ones included, otherwise "untagged".
#
# A RubyLLM::Error marks the record "failed" and is returned in the Result. Transport errors
# (ApplicationJob::TRANSPORT_ERRORS) mark it "failed" too but are re-raised, so a job's retry_on still applies.
class Tags::Classify
  Result = Data.define(:status, :error)

  def self.call(item, force: false)
    new(item, force:).call
  end

  def initialize(item, force:)
    @item = item
    @force = force
  end

  def call
    return Result.new(status: "skipped", error: nil) unless due?

    Tags::Classifier.call(@item)
    Result.new(status: mark(@item.taggings.exists? ? "tagged" : "untagged"), error: nil)
  rescue *ApplicationJob::TRANSPORT_ERRORS
    mark("failed")
    raise
  rescue RubyLLM::Error => error
    Result.new(status: mark("failed"), error: error.message)
  end

  private

  def mark(status)
    @item.update!(classification_status: status)
    status
  end

  def due?
    @force || @item.pending? || @item.failed?
  end
end
