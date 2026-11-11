module Tags
  class SubtagForm < ::BaseForm
    attr_reader :subtag

    attribute :name, :string

    def initialize(tag:, name: nil)
      super(name:)
      @tag = tag
    end

    def save
      @subtag = @tag.subtags.build(name:)
      return true if @subtag.save

      @subtag.errors.each { |error| errors.add(error.attribute, error.message) }
      false
    end
  end
end
