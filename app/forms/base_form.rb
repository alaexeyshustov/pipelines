
class BaseForm
  include ActiveModel::Model
  include ActiveModel::Attributes
  include ActiveModel::Validations
  include JsonParamsParsing
end
