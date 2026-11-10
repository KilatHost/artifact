class ArtifactVersion < ApplicationRecord
  MAX_FILE_SIZE = 20.megabytes
  belongs_to :artifact
  has_one_attached :file
  validates :title, :author, presence: true, length: { maximum: 200 }
  validates :kind, inclusion: { in: %w[document html file] }
  validates :number, numericality: { only_integer: true, greater_than: 0 }
  validates :content, length: { maximum: 1_000_000 }
  validate :valid_file
  before_update { raise ActiveRecord::ReadOnlyRecord, "Artifact versions are immutable" }
  before_destroy { raise ActiveRecord::ReadOnlyRecord, "Artifact versions are immutable" }

  private

  def valid_file
    errors.add(:file, "is required") if kind == "file" && !file.attached?
    errors.add(:file, "must be 20 MB or smaller") if file.attached? && file.blob.byte_size > MAX_FILE_SIZE
  end
end
