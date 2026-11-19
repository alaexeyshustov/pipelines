namespace :users do
  desc "Create or update the single login user from ADMIN_EMAIL and ADMIN_PASSWORD"
  task upsert: :environment do
    email_address, password = %w[ADMIN_EMAIL ADMIN_PASSWORD].map { |name| ENV[name].presence || abort("#{name} is required") }
    puts "Upserted user #{User.upsert_login!(email_address:, password:).email_address}"
  end
end
