module Tags
  class TagCardComponent < ViewComponent::Base
    def initialize(tag:, subtags:, form_url:, errors: nil)
      @tag_record = tag
      @subtags = subtags
      @form_url = form_url
      @errors = errors
    end

    private

    attr_reader :tag_record, :subtags, :form_url, :errors
  end
end
