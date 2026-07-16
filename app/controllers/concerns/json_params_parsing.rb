
module JsonParamsParsing
  extend ActiveSupport::Concern

  private

  def parse_json_field(permitted, key)
    raw = permitted[key]
    permitted[key] = JSON.parse(raw) if raw.present?
  end
end
