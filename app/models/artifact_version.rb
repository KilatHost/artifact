class ArtifactVersion < ApplicationRecord
  MAX_FILE_SIZE = 20.megabytes
  belongs_to :artifact
  has_one_attached :file
  validates :title, :author, presence: true, length: { maximum: 200 }
  validates :kind, inclusion: { in: Artifact::KINDS }
  validates :number, numericality: { only_integer: true, greater_than: 0 }
  validates :content, length: { maximum: 1_000_000 }, unless: -> { ArtifactTypes::KINDS.include?(kind) }
  validate :valid_file
  validate :valid_typed_content
  before_validation(on: :create) { self.content = ArtifactRendering.sanitize_document(content) if kind == "document" }
  before_update { raise ActiveRecord::ReadOnlyRecord, "Artifact versions are immutable" }
  before_destroy { raise ActiveRecord::ReadOnlyRecord, "Artifact versions are immutable" }

  def assign_actor(actor)
    self.actor_type = case actor
    when User then "user"
    when ApiToken then "api_token"
    when Doorkeeper::Application then "oauth_application"
    end
    self.actor_id = actor.id if actor_type
  end

  def connection
    { type: actor_type, id: actor_id, name: author } if actor_type && actor_id
  end

  private

  def valid_typed_content
    return unless ArtifactTypes::KINDS.include?(kind)
    self.content = ArtifactTypes.validate!(kind, content).last
  rescue ArtifactTypes::Invalid => error
    errors.add(:content, error.message)
  end

  def valid_file
    errors.add(:file, "is required") if kind == "file" && !file.attached?
    errors.add(:file, "must be 20 MB or smaller") if file.attached? && file.blob.byte_size > MAX_FILE_SIZE
  end
end
