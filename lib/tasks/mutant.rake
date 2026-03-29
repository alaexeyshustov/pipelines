namespace :mutant do
  desc "Run mutation testing on the full codebase to establish a baseline score"
  task :baseline do
    sh "bundle exec mutant run --jobs 2"
  end
end
