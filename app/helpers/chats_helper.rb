module ChatsHelper
  def message_role_styles(role)
    case role
    when "user"      then "bg-blue-50 border-blue-200"
    when "assistant" then "bg-white border-gray-200"
    when "tool"      then "bg-amber-50 border-amber-200"
    else                  "bg-gray-50 border-gray-200"
    end
  end

  def message_role_badge(role)
    case role
    when "user"      then "bg-blue-100 text-blue-700"
    when "assistant" then "bg-gray-100 text-gray-700"
    when "tool"      then "bg-amber-100 text-amber-700"
    else                  "bg-gray-100 text-gray-600"
    end
  end
end
