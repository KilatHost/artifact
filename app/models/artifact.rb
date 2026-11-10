class Artifact < ApplicationRecord
  class Conflict < StandardError; end
  belongs_to :workspace
  belongs_to :design_kit, optional: true
  belongs_to :current_version, class_name: "ArtifactVersion", optional: true
  belongs_to :published_version, class_name: "ArtifactVersion", optional: true
  has_many :versions, class_name: "ArtifactVersion", dependent: :restrict_with_error
  has_secure_token :public_id
  validates :title, presence: true, length: { maximum: 200 }
  validates :kind, inclusion: { in: %w[document html file] }
  validate :owned_design_kit

  def self.create_draft!(title:, kind:, content:, author:, file: nil, design_kit_id: nil)
    transaction do
      artifact = create!(title: title, kind: kind, design_kit_id: design_kit_id)
      artifact.send(:append_version!, title: title, kind: kind, content: content, author: author, file: file)
      artifact
    end
  end

  def revise!(expected_version:, title:, content:, author:, file: nil, kind: nil, design_tokens: nil)
    with_lock do
      raise Conflict, "Artifact changed. Reload latest version before saving." unless current_version.number == Integer(expected_version, exception: false)
      append_version!(title: title, kind: kind || self.kind, content: content, author: author, file: file, design_tokens: design_tokens)
    end
  end

  def publish!(version_id:)
    with_lock { update!(published_version: versions.find(version_id)) }
  end

  def unpublish!
    with_lock { update!(published_version: nil) }
  end

  def restore!(version_id:, expected_version:, author:)
    version = versions.find(version_id)
    revise!(expected_version: expected_version, title: version.title, kind: version.kind, content: version.content, author: author, file: version.file.attached? ? version.file.blob : nil, design_tokens: version.design_tokens)
  end

  private

  def owned_design_kit
    errors.add(:design_kit, "must belong to this workspace") if design_kit && design_kit.workspace_id != workspace_id
  end

  def append_version!(title:, kind:, content:, author:, file:, design_tokens: nil)
    tokens = design_tokens || (design_kit&.tokens || DesignKit::DEFAULT_TOKENS).merge("kit_version" => design_kit&.version, "kit_name" => design_kit&.name)
    version = versions.build(number: (current_version&.number || 0) + 1, title: title, kind: kind, content: content.to_s, author: author, design_tokens: tokens)
    version.file.attach(file || current_version.file.blob) if file || (kind == "file" && current_version&.file&.attached?)
    version.save!
    update!(title: title, kind: kind, current_version: version)
    version
  end
end
