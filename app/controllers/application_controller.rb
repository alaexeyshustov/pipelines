class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern
  include Pagy::Method

  private

  def flash_for(result)
    result.ok? ? { notice: result.message } : { alert: result.message }
  end
end
