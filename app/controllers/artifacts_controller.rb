class ArtifactsController < ApplicationController
  before_action :set_artifact, except: %i[index new create]
  rescue_from Artifact::Conflict, with: :conflict
  rescue_from ActiveRecord::RecordInvalid, with: :invalid

  def index
    @artifacts = Current.workspace.artifacts.includes(:current_version).order(updated_at: :desc)
    @artifacts = @artifacts.where("title ILIKE ?", "%#{Artifact.sanitize_sql_like(params[:q].to_s.first(120))}%") if params[:q].present?
  end

  def new
    @artifact = Current.workspace.artifacts.new(kind: "document")
  end

  def create
    @artifact = Current.workspace.artifacts.create_draft!(**artifact_params.to_h.symbolize_keys.except(:expected_version), author: Current.user.email)
    redirect_to @artifact, notice: "Artifact created. Private until you publish."
  end

  def show
    @version = params[:version_id].present? ? @artifact.versions.find(params[:version_id]) : @artifact.current_version
    @versions = @artifact.versions.order(number: :desc)
  end

  def update
    data = artifact_params.to_h.symbolize_keys
    if data[:design_kit_id].present?
      kit = Current.workspace.design_kits.find(data.delete(:design_kit_id))
    else
      data.delete(:design_kit_id)
    end
    @artifact.transaction do
      @artifact.update!(design_kit: kit) if kit
      @artifact.revise!(**data, author: Current.user.email)
    end
    redirect_to @artifact, notice: "Version saved. Published version unchanged."
  end

  def upload
    @artifact.revise!(expected_version: params[:expected_version], title: @artifact.title, content: @artifact.current_version.content, file: params.dig(:artifact, :file) || params[:file], author: Current.user.email)
    redirect_to @artifact, notice: "File version saved."
  end

  def publish
    @artifact.publish!(version_id: params.require(:version_id))
    redirect_to @artifact, notice: "Selected version is public. Anyone with its URL can read it."
  end

  def unpublish
    @artifact.unpublish!
    redirect_to @artifact, notice: "Public access removed. Previously downloaded copies cannot be recalled."
  end

  def restore
    @artifact.restore!(version_id: params.require(:version_id), expected_version: params.require(:expected_version), author: Current.user.email)
    redirect_to @artifact, notice: "Previous content restored as new version."
  end

  def preview
    version = selected_version
    response.headers["Content-Security-Policy"] = "sandbox; default-src 'none'; style-src 'unsafe-inline'; img-src data:; base-uri 'none'; form-action 'none'"
    render html: ArtifactRendering.html(version).html_safe, layout: false
  end

  def export
    version = selected_version
    name = version.title.parameterize.presence || "artifact"
    case params[:export_format]
    when "pdf"
      send_data ArtifactExports.pdf(version), filename: "#{name}-v#{version.number}.pdf", type: "application/pdf"
    when "zip", "web"
      send_data ArtifactExports.zip(version), filename: "#{name}-v#{version.number}.zip", type: "application/zip"
    when "html"
      send_data ArtifactRendering.html(version), filename: "#{name}.html", type: "text/html", disposition: "attachment"
    when "source"
      send_data version.content, filename: "#{name}.#{version.kind == 'html' ? 'html' : 'txt'}", type: "text/plain", disposition: "attachment"
    when "file"
      raise ActiveRecord::RecordNotFound unless version.file.attached?
      send_data version.file.download, filename: version.file.filename.to_s, type: "application/octet-stream", disposition: "attachment"
    else
      head :bad_request
    end
  end

  private

  def set_artifact
    @artifact = Current.workspace.artifacts.find(params[:id])
    response.headers["Cache-Control"] = "private, no-store"
  end

  def selected_version
    params[:version_id].present? ? @artifact.versions.find(params[:version_id]) : @artifact.current_version
  end

  def artifact_params
    params.require(:artifact).permit(:title, :kind, :content, :expected_version, :design_kit_id, :file).tap { |data| data[:content] ||= "" }
  end

  def conflict(error)
    render plain: error.message, status: :conflict
  end

  def invalid(error)
    render plain: error.record.errors.full_messages.join(". "), status: :unprocessable_entity
  end
end
