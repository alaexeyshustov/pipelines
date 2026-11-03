# Upserts the Interview a job_application-tagged Email belongs to (ADR 0013, GH #228); nothing per email is stored
# except +emails.interview_id+.
#
# - One structured-output LLM call (company, job title, action) with the email subject, sender, date and body.
# - Matched to an existing Interview by company + job title, case-insensitive (the legacy reconciler's rule), else
#   created as +pending_reply+.
# - The action moves the status forward only (an old "apply" confirmation never undoes a rejection) and fills dates
#   from the email date: applied_at (earliest), rejected_at, the next free interview slot.
# - Idempotent: an email already linked to an Interview is not sent to the LLM again, and an interview date that is
#   already recorded is not added twice.
# - Emails without the job_application tag, or where the LLM finds no company/job title, are left alone.
# - Provider errors (RubyLLM::Error) propagate before anything is written.
class Interviews::EmailExtractor
  Result = Data.define(:interview)

  TAG = "job_application"
  MAX_CHARS = 8_000
  INTERVIEW_SLOTS = %i[first_interview_at second_interview_at third_interview_at fourth_interview_at].freeze
  # Order in which a status may replace another; a later action never moves the status to a lower rank.
  STATUS_RANK = { "pending_reply" => 0, "having_interviews" => 1, "offer_received" => 2, "rejected" => 3 }.freeze
  ACTION_STATUS = {
    "interview" => "having_interviews", "offer" => "offer_received", "rejection" => "rejected"
  }.freeze

  INSTRUCTIONS = <<~TEXT.freeze
    You track a job search. The input is one email (subject, sender, date, body) that was classified as a job
    application email. Extract the company, the job title and the stage of the application the email represents.
    Base the action strictly on the email body text, not just the subject line.
  TEXT

  def self.call(email)
    new(email).call
  end

  def initialize(email)
    @email = email
  end

  def call
    return Result.new(interview: nil) if @email.tags.find_by(name: TAG).nil?
    return Result.new(interview: @email.interview) if @email.interview_id

    Result.new(interview: extract_and_upsert)
  end

  private

  def extract_and_upsert
    extraction = extract
    company, job_title = %w[company job_title].map { |key| extraction[key].to_s.squish }
    return if company.empty? || job_title.empty?

    upsert(company, job_title, extraction["action"].to_s)
  end

  def extract
    message = RubyLLM.chat(model: LlmModels.emails_agent)
                     .with_instructions(INSTRUCTIONS)
                     .with_schema(InterviewExtractionSchema)
                     .ask(prompt)
    Evaluation::StructuredOutput.from(message)
  end

  def prompt
    JSON.generate(
      subject: @email.subject, from: @email.from_address, date: @email.date.iso8601,
      body: @email.body.to_s.truncate(MAX_CHARS)
    )
  end

  def upsert(company, job_title, action)
    Interview.transaction do
      record = find_or_create(company, job_title)
      apply(record, action)
      record.save!
      @email.update!(interview: record)
      record
    end
  rescue ActiveRecord::RecordNotUnique
    retry
  end

  def find_or_create(company, job_title)
    Interview.find_by("lower(company) = ? AND lower(job_title) = ?", company.downcase, job_title.downcase) ||
      Interview.new(company:, job_title:, status: Interview::STATUSES.first)
  end

  def apply(interview, action)
    date = @email.date.to_date
    interview.applied_at = [ interview.applied_at, date ].compact.min if action == "apply"
    interview.applied_at ||= date
    interview.status = advance(interview.status, ACTION_STATUS[action])
    record_date(interview, action, date)
  end

  def advance(current, target)
    return current if target.nil?
    return target if current.nil?

    STATUS_RANK.fetch(target) > STATUS_RANK.fetch(current, 0) ? target : current
  end

  def record_date(interview, action, date)
    case action
    when "rejection" then interview.rejected_at ||= date
    when "interview" then add_interview_date(interview, date)
    end
  end

  def add_interview_date(interview, date)
    dates = INTERVIEW_SLOTS.map { |slot| interview.public_send(slot) }
    return if dates.include?(date)

    slot = INTERVIEW_SLOTS.zip(dates).find { |_, value| value.nil? }&.first
    interview.public_send(:"#{slot}=", date) if slot
  end
end
