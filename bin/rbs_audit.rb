#!/usr/bin/env ruby
# frozen_string_literal: true

require "rbs"
require "set"

ROOT = File.expand_path("../..", __FILE__)

RUBY_DIRS = %w[app lib].map { File.join(ROOT, _1) }
SIG_DIR = File.join(ROOT, "sig")

SKIP_DIRS = %w[
  app/assets
  app/views
  app/javascript
  app/mailers
  config
  db
  spec
  test
].map { File.join(ROOT, _1) }

SKIP_FILES = %w[
  app/helpers/application_helper.rb
].map { File.join(ROOT, _1) }

def ruby_files
  RUBY_DIRS.flat_map do |dir|
    Dir.glob(File.join(dir, "**/*.rb"))
  end.reject do |f|
    SKIP_DIRS.any? { f.start_with?(_1) } ||
      SKIP_FILES.include?(f) ||
      File.basename(f) == "application_helper.rb"
  end.sort
end

def sig_for(ruby_file)
  relative = ruby_file.sub("#{ROOT}/", "")
  sig_path = File.join(SIG_DIR, relative.sub(/\.rb$/, ".rbs"))
  sig_path if File.exist?(sig_path)
end

# Parse prototype RBS text (output of `rbs prototype rb`) to extract API elements
def parse_prototype(text)
  result = {
    classes: Set.new,
    public_methods: Set.new,
    private_methods: Set.new,
    instance_vars: Set.new,
    constants: Set.new,
    attrs: Set.new,
  }

  current_class = nil
  in_private = false

  text.each_line do |line|
    stripped = line.strip

    # Track class/module context
    if stripped =~ /^(?:class|module)\s+([\w:]+)/
      current_class = $1
      in_private = false
      result[:classes] << current_class
    end

    # private section marker
    if stripped == "private"
      in_private = true
    end

    # end resets private scope (simplified - assumes one level)
    if stripped == "end"
      in_private = false
    end

    # Instance variables: @var: type
    if stripped =~ /^@(\w+):\s/
      result[:instance_vars] << "@#{$1}"
    end

    # Constants: CONST: type
    if stripped =~ /^([A-Z][A-Z0-9_]+):\s/
      result[:constants] << $1
    end

    # Methods: def name: or def self.name:
    if stripped =~ /^def (?:self\.)?(\w+[?!]?):/
      method_name = $1
      if in_private
        result[:private_methods] << method_name
      else
        result[:public_methods] << method_name
      end
    end

    # attr_reader/writer/accessor
    if stripped =~ /^attr_(?:reader|writer|accessor)\s+(\w+)/
      result[:attrs] << $1
    end
  end

  result
end

# Parse actual RBS file to extract what's defined
def parse_rbs(rbs_file)
  result = {
    public_methods: Set.new,
    private_methods: Set.new,
    instance_vars: Set.new,
    constants: Set.new,
    attrs: Set.new,
  }

  in_private = false
  text = File.read(rbs_file)

  text.each_line do |line|
    stripped = line.strip

    # Skip comments
    next if stripped.start_with?("#")

    # private section marker
    if stripped == "private"
      in_private = true
      next
    end

    # class/module/end context tracking
    if stripped =~ /^(?:class|module)\s/ || stripped == "end"
      # Don't reset private here, it's section-scoped per RBS convention
    end

    # Instance variable declarations: @var: Type
    if stripped =~ /^@(\w+):\s/
      result[:instance_vars] << "@#{$1}"
    end

    # Constants: CONST: Type
    if stripped =~ /^([A-Z][A-Z0-9_]+):\s/
      result[:constants] << $1
    end

    # Method definitions: def name: or def self.name:
    if stripped =~ /^def (?:self\.)?(\w+[?!]?):/
      method_name = $1
      if in_private
        result[:private_methods] << method_name
      else
        result[:public_methods] << method_name
      end
    end

    # attr_reader/writer/accessor
    if stripped =~ /^attr_(?:reader|writer|accessor)\s+(\w+)/
      result[:attrs] << $1
    end
  end

  result
end

gaps = {}
missing_sig_files = []

ruby_files.each do |ruby_file|
  relative = ruby_file.sub("#{ROOT}/", "")

  # Skip empty files
  next if File.size(ruby_file) == 0

  # Generate prototype
  prototype_output = `cd "#{ROOT}" && bundle exec rbs prototype rb "#{relative}" 2>/dev/null`
  next if prototype_output.strip.empty?

  prototype = parse_prototype(prototype_output)

  # Skip if no meaningful API surface (pure module with no methods)
  next if prototype[:public_methods].empty? &&
          prototype[:private_methods].empty? &&
          prototype[:instance_vars].empty? &&
          prototype[:constants].empty?

  sig_file = sig_for(ruby_file)

  unless sig_file
    missing_sig_files << relative
    next
  end

  actual = parse_rbs(sig_file)

  file_gaps = {}

  # Check public methods
  missing_pub = prototype[:public_methods] - actual[:public_methods] - actual[:attrs]
  file_gaps[:missing_public_methods] = missing_pub.to_a.sort unless missing_pub.empty?

  # Check private methods
  missing_priv = prototype[:private_methods] - actual[:private_methods] - actual[:attrs]
  file_gaps[:missing_private_methods] = missing_priv.to_a.sort unless missing_priv.empty?

  # Check instance variables
  missing_ivars = prototype[:instance_vars] - actual[:instance_vars]
  # Also skip ivars that correspond to attr_readers in RBS
  missing_ivars = missing_ivars.reject do |ivar|
    attr_name = ivar.sub("@", "")
    actual[:attrs].include?(attr_name) || actual[:public_methods].include?(attr_name) || actual[:private_methods].include?(attr_name)
  end
  file_gaps[:missing_instance_vars] = missing_ivars.to_a.sort unless missing_ivars.empty?

  # Check constants
  missing_consts = prototype[:constants] - actual[:constants]
  file_gaps[:missing_constants] = missing_consts.to_a.sort unless missing_consts.empty?

  gaps[relative] = file_gaps unless file_gaps.empty?
end

puts "=" * 70
puts "RBS SIGNATURE COVERAGE AUDIT"
puts "=" * 70
puts

if missing_sig_files.any?
  puts "## MISSING SIGNATURE FILES (#{missing_sig_files.size})"
  puts
  missing_sig_files.sort.each { puts "  - #{_1}" }
  puts
end

if gaps.empty?
  puts "No gaps found in existing signature files."
else
  puts "## SIGNATURE GAPS IN EXISTING FILES (#{gaps.size} files)"
  puts

  gaps.sort_by { |f, _| f }.each do |file, file_gaps|
    puts "### #{file}"

    if (missing = file_gaps[:missing_public_methods]) && !missing.empty?
      puts "  Public methods without signature:"
      missing.each { puts "    - def #{_1}" }
    end

    if (missing = file_gaps[:missing_private_methods]) && !missing.empty?
      puts "  Private methods without signature:"
      missing.each { puts "    - def #{_1}" }
    end

    if (missing = file_gaps[:missing_instance_vars]) && !missing.empty?
      puts "  Instance variables without signature:"
      missing.each { puts "    - #{_1}" }
    end

    if (missing = file_gaps[:missing_constants]) && !missing.empty?
      puts "  Constants without signature:"
      missing.each { puts "    - #{_1}" }
    end

    puts
  end
end

puts "=" * 70
total_gaps = gaps.values.sum { |v| v.values.sum(&:size) }
puts "Summary: #{missing_sig_files.size} missing sig files, #{total_gaps} gaps in #{gaps.size} files"
