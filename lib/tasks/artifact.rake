namespace :artifacts do
  desc "Purge artifacts deleted more than 7 days ago, with their versions and files"
  task purge_archived: :environment do
    count = Artifact.purge_archived!
    puts "Purged #{count} artifact#{'s' unless count == 1}."
  end
end

namespace :users do
  desc "Set a new random password for EMAIL and print it once"
  task reset_password: :environment do
    email = ENV["EMAIL"].to_s.strip.downcase
    abort "Usage: bin/rails users:reset_password EMAIL=person@example.com" if email.empty?
    user = User.find_by(email: email) or abort "No account for #{email}."
    password = SecureRandom.base58(20)
    user.update!(password: password, password_confirmation: password)
    Doorkeeper::AccessToken.where(resource_owner_id: user.id, revoked_at: nil).find_each(&:revoke)
    puts "New password for #{email}: #{password}"
    puts "Share it privately. OAuth connections for this account were revoked."
  end
end
