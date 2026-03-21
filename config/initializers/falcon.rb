# Falcon's railtie uses `Rails::Railtie` without the :: prefix, which breaks
# Ruby 4.0 constant lookup inside `module Falcon`. We apply its only effect manually.
Rails.application.config.active_support.isolation_level = :fiber
