module InterviewsHelper
  STATUS_BADGE_CLASSES = {
    "pending_reply"     => "bg-yellow-50 text-yellow-700",
    "having_interviews" => "bg-blue-50 text-blue-700",
    "rejected"          => "bg-red-50 text-red-700",
    "offer_received"    => "bg-green-50 text-green-700"
  }.freeze

  def interview_status_badge_class(status)
    STATUS_BADGE_CLASSES.fetch(status.to_s, "bg-gray-50 text-gray-700")
  end
end
