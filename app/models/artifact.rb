class Artifact < ApplicationRecord
  class Conflict < StandardError
    attr_reader :current_version

    def initialize(message, current_version: nil)
      @current_version = current_version
      super(message)
    end
  end
  RETENTION = 7.days
  KINDS = %w[markdown html document file].freeze

  belongs_to :workspace
  belongs_to :design_kit, optional: true
  belongs_to :current_version, class_name: "ArtifactVersion", optional: true
  belongs_to :published_version, class_name: "ArtifactVersion", optional: true
  has_many :versions, class_name: "ArtifactVersion", dependent: :restrict_with_error
  has_secure_token :public_id
  validates :title, presence: true, length: { maximum: 200 }
  validates :kind, inclusion: { in: KINDS }
  validate :owned_design_kit

  scope :active, -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }

  def self.create_draft!(title:, kind:, content:, author:, file: nil, design_kit_id: nil, actor: nil)
    transaction do
      artifact = create!(title: title, kind: kind, design_kit_id: design_kit_id)
      artifact.send(:append_version!, title: title, kind: kind, content: content, author: author, file: file, actor: actor)
      artifact
    end
  end

  # Removes artifacts archived longer than RETENTION, with every version and file.
  def self.purge_archived!(now: Time.current)
    archived.where(archived_at: ..(now - RETENTION)).find_each.sum { |artifact| artifact.purge!(now: now) ? 1 : 0 }
  end

  def archived?
    archived_at.present?
  end

  def purge_at
    archived_at && archived_at + RETENTION
  end

  def revise!(expected_version:, title:, content:, author:, file: nil, kind: nil, design_tokens: nil, actor: nil)
    with_lock do
      raise Conflict, "Archived artifacts can't be edited. Restore it first." if archived?
      raise Conflict.new("This artifact changed since you opened it.", current_version: current_version.number) unless current_version.number == Integer(expected_version, exception: false)
      append_version!(title: title, kind: kind || self.kind, content: content, author: author, file: file, design_tokens: design_tokens, actor: actor)
    end
  end

  def publish!
    with_lock do
      raise Conflict, "Archived artifacts can't be published. Restore it first." if archived?
      pin = public_version_number.present? || ENV.fetch("KILAT_PUBLIC_LINKS", "latest") == "pinned"
      update!(published_version: current_version, public_version_number: (current_version.number if pin))
    end
  end

  def unpublish!
    with_lock { update!(published_version: nil, public_version_number: nil) }
  end

  def public_version
    return unless published_version_id
    public_version_number ? versions.find_by!(number: public_version_number) : published_version
  end

  def update_public_link!
    with_lock do
      raise Conflict, "This artifact has no pinned public link." unless published_version_id && public_version_number
      update!(public_version_number: current_version.number, published_version: current_version)
    end
  end

  # Delete for the owner: public access ends now, data stays for RETENTION.
  def archive!
    with_lock { update!(archived_at: Time.current, published_version: nil, public_version_number: nil) unless archived? }
  end

  def unarchive!
    with_lock { update!(archived_at: nil) }
  end

  def restore!(version_id:, expected_version:, author:, actor: nil)
    version = versions.find(version_id)
    revise!(expected_version: expected_version, title: version.title, kind: version.kind, content: version.content, author: author, actor: actor, file: version.file.attached? ? version.file.blob : nil, design_tokens: version.design_tokens)
  end

  def purge!(now: Time.current)
    blob_ids = []
    purged = transaction do
      lock!
      next false unless archived? && archived_at <= now - RETENTION
      update_columns(current_version_id: nil, published_version_id: nil)
      version_ids = ArtifactVersion.where(artifact_id: id).select(:id)
      attachments = ActiveStorage::Attachment.where(record_type: "ArtifactVersion", record_id: version_ids)
      blob_ids = attachments.distinct.pluck(:blob_id)
      attachments.delete_all
      ArtifactVersion.where(artifact_id: id).delete_all
      delete
      true
    end
    ActiveStorage::Blob.where(id: blob_ids).where.missing(:attachments).find_each(&:purge) if purged
    purged
  end

  private

  def owned_design_kit
    errors.add(:design_kit, "must belong to this workspace") if design_kit && design_kit.workspace_id != workspace_id
  end

  def append_version!(title:, kind:, content:, author:, file:, design_tokens: nil, actor: nil)
    tokens = design_tokens || DesignKit.snapshot_tokens(design_kit)
    version = versions.build(number: (current_version&.number || 0) + 1, title: title, kind: kind, content: content.to_s, author: author, design_tokens: tokens)
    version.assign_actor(actor || Current.user)
    version.file.attach(file || current_version.file.blob) if file || (kind == "file" && current_version&.file&.attached?)
    version.save!
    update!(title: title, kind: kind, current_version: version, published_version: (public_version_number ? published_version : version if published_version_id))
    version
  end
end
