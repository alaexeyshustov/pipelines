module TagPages
  # One subclass per fixed top-level tag (Tag::NAMES); a subclass only names its tag (and may opt into extra
  # columns). The tag row is looked up by name, so a not-yet-seeded tag renders an empty page.
  class BaseController < ApplicationController
    class_attribute :tag_name, instance_writer: false

    helper_method :interview_columns?

    def show
      @tag = Tag.find_by(name: tag_name)
      @filter = FilterForm.new(params.permit(:q, :subtag, :type, :from, :to))
      @subtags = @tag ? @tag.subtags.order(:name) : []
      @rows = Search.call(tag: @tag, filter: @filter)
    end

    private

    def interview_columns?
      false
    end
  end
end
