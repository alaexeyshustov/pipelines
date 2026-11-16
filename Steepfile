target :app do
  signature "sig"

  check "app/jobs"
  check "app/models"
  check "app/services"
  check "app/tools"
  check "lib"
  ignore "lib/view_primitives"

  # Known gaps: this list may only shrink (GH #286).
  # Steep can't type `included do` / `class_methods do` blocks, whose self is the including model.
  ignore "app/models/concerns"
  # Reads untyped JSON Schema hashes; needs narrowing of json_object_value before it can be checked.
  ignore "app/models/orchestration/schema_builder/parser.rb"

  library "pathname"
  library "json"
  library "csv"
  library "date"
  library "time"
  library "uri"
  library "monitor"
  library "singleton"
  library "socket"
  library "fileutils"
end
