# frozen_string_literal: true

module RakeTaskHelpers
  def load_rake_task(task_name)
    Rails.application.load_tasks if Rake::Task.tasks.empty?
    Rake::Task[task_name].reenable
  end
end
