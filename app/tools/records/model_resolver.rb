module Records
  class ModelNotFound < ArgumentError; end

  module ModelResolver
    def resolve_model(table)
      case table.to_s
      when "interviews" then Interview
      else raise ModelNotFound, "Unknown table '#{table}'. Use: interviews."
      end
    end
  end
end
