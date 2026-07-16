
require "rubocop"
require "rubocop/rspec/support"
require "rubocop-on-rbs"

# inspect_source raises on invalid Ruby (valid_syntax? check). RBS files are
# not valid Ruby, so we bypass that check and call _investigate directly.
module RBSCopHelper
  def inspect_rbs_source(source, file: "example.rbs")
    processed_source = RuboCop::ProcessedSource.new(source, ruby_version, file, parser_engine: parser_engine)
    processed_source.config = configuration
    processed_source.registry = registry
    _investigate(cop, processed_source)
  end
end

RSpec.configure do |config|
  config.include RuboCop::RSpec::ExpectOffense
  config.include RBSCopHelper
end
