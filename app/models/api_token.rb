require "digest"

class ApiToken < ApplicationRecord
  SCOPES = %w[read write publish].freeze
  belongs_to :workspace
  validates :name, presence: true, length: { maximum: 100 }
  validates :token_digest, presence: true, uniqueness: true
  validate do
    errors.add(:scopes, "must contain supported permissions") if scopes.to_s.split.empty? || (scopes.to_s.split - SCOPES).any?
  end

  def self.issue!(workspace:, name:, scopes:)
    secret = "kilat_#{SecureRandom.urlsafe_base64(32)}"
    record = workspace.api_tokens.create!(name: name, scopes: Array(scopes).uniq.join(" "), token_digest: Digest::SHA256.hexdigest(secret))
    [ record, secret ]
  end

  def self.authenticate(secret)
    return unless secret.is_a?(String) && secret.start_with?("kilat_") && secret.bytesize < 200
    find_by(token_digest: Digest::SHA256.hexdigest(secret))
  end
end
