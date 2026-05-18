# frozen_string_literal: true

class BaseForm
  include ActiveModel::Model
  include ActiveModel::Attributes
  include ActiveModel::Validations::Callbacks
  include JsonParamsParsing
end
