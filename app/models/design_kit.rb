class DesignKit < ApplicationRecord
  DEFAULT_TOKENS = { "font" => "system-ui", "background" => "#ffffff", "foreground" => "#171717", "accent" => "#171717" }.freeze
  belongs_to :workspace
  has_many :artifacts, dependent: :restrict_with_error
  validates :name, presence: true, length: { maximum: 120 }
  validate :safe_tokens
  before_validation { self.tokens = DEFAULT_TOKENS.merge(tokens || {}) }
  before_update { self.version += 1 if will_save_change_to_tokens? }

  private

  def safe_tokens
    errors.add(:tokens, "contain unknown fields") unless (tokens.keys - DEFAULT_TOKENS.keys).empty?
    %w[background foreground accent].each do |key|
      errors.add(:tokens, "#{key} must be a six-digit hex color") unless tokens[key].to_s.match?(/\A#[0-9a-fA-F]{6}\z/)
    end
    errors.add(:tokens, "font is unsupported") unless %w[system-ui serif monospace].include?(tokens["font"])
  end
end
