module Records
  class ModelNotFound < ArgumentError; end

  module ModelResolver
    def resolve_model(table)
      case table.to_s
      when "application_mails" then ApplicationMail
      when "interviews"        then Interview
      else raise ModelNotFound, "Unknown table '#{table}'. Use: application_mails, interviews."
      end
    end
  end
end
