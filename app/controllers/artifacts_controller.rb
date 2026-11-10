class ArtifactsController < ApplicationController
  include ActiveStorage::Streaming

  before_action :set_artifact, except: %i[index new create]
  before_action :require_active, except: %i[index new create unarchive]

  def index
    @artifacts = Current.workspace.artifacts.active.includes(:current_version).order(updated_at: :desc)
    @artifacts = @artifacts.where("title ILIKE ?", "%#{Artifact.sanitize_sql_like(params[:q].to_s.first(120))}%") if params[:q].present?
    @archived = Current.workspace.artifacts.archived.order(archived_at: :desc)
  end

  def new
    @artifact = Current.workspace.artifacts.new(kind: "document")
  end

  def create
    data = artifact_params.to_h.symbolize_keys.except(:expected_version)
    data[:design_kit_id] = data[:design_kit_id].presence
    @artifact = Current.workspace.artifacts.create_draft!(**data, author: Current.user.email)
    redirect_to @artifact, notice: "Draft created. It stays private until you publish it."
  rescue ActiveRecord::RecordInvalid => error
    @artifact = Current.workspace.artifacts.new(kind: data[:kind], title: data[:title], design_kit_id: data[:design_kit_id])
    @draft = ArtifactVersion.new(title: data[:title], kind: data[:kind], content: data[:content])
    flash.now[:alert] = "Couldn't create the draft. #{messages(error)}"
    render :new, status: :unprocessable_entity
  end

  def show
    @version = params[:version_id].present? ? @artifact.versions.find(params[:version_id]) : @artifact.current_version
    @versions = @artifact.versions.order(number: :desc)
  end

  def update
    data = artifact_params.to_h.symbolize_keys
    kit_given = data.key?(:design_kit_id)
    kit_id = data.delete(:design_kit_id).presence
    kit = Current.workspace.design_kits.find(kit_id) if kit_id
    @artifact.transaction do
      @artifact.update!(design_kit: kit) if kit_given
      @artifact.revise!(**data, author: Current.user.email)
    end
    redirect_to @artifact, notice: live_notice("Version saved.")
  rescue Artifact::Conflict, ActiveRecord::RecordInvalid => error
    @artifact.reload
    @version = @artifact.current_version
    @versions = @artifact.versions.order(number: :desc)
    @draft = ArtifactVersion.new(title: data[:title], kind: data[:kind] || @artifact.kind, content: data[:content])
    flash.now[:alert] = if error.is_a?(Artifact::Conflict)
      "#{error.message} Your text is still below. Saving now makes it version #{@version.number + 1}."
    else
      "Couldn't save. #{messages(error)}"
    end
    render :show, status: error.is_a?(Artifact::Conflict) ? :conflict : :unprocessable_entity
  end

  def upload
    @artifact.revise!(expected_version: params[:expected_version], title: @artifact.title, content: @artifact.current_version.content, file: params.dig(:artifact, :file) || params[:file], author: Current.user.email)
    redirect_to @artifact, notice: live_notice("File version saved.")
  rescue Artifact::Conflict, ActiveRecord::RecordInvalid => error
    redirect_to @artifact, alert: "Couldn't save the file. #{messages(error)}"
  end

  def publish
    @artifact.publish!(version_id: params.require(:version_id))
    return redirect_to public_artifact_path(@artifact.public_id) if params[:return_to] == "viewer"
    redirect_to @artifact, notice: "Public. Anyone with the link sees the latest version."
  end

  def unpublish
    @artifact.unpublish!
    return redirect_to public_artifact_path(@artifact.public_id) if params[:return_to] == "viewer"
    redirect_to @artifact, notice: "Public link turned off. Copies people already downloaded stay with them."
  end

  def restore
    @artifact.restore!(version_id: params.require(:version_id), expected_version: params.require(:expected_version), author: Current.user.email)
    redirect_to @artifact, notice: live_notice("Old version restored as a new version.")
  rescue Artifact::Conflict, ActiveRecord::RecordInvalid => error
    redirect_to @artifact, alert: "Couldn't restore. #{messages(error)}"
  end

  def archive
    @artifact.archive!
    redirect_to artifacts_path, notice: "Deleted. You can restore it for #{Artifact::RETENTION.inspect}."
  end

  def unarchive
    @artifact.unarchive!
    redirect_to @artifact, notice: "Restored as a private draft. Publish again to share it."
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
      pdf = ArtifactExports.pdf(version)
      return render plain: "Another PDF is being made. Try again in a few seconds.", status: :service_unavailable unless pdf
      send_data pdf, filename: "#{name}-v#{version.number}.pdf", type: "application/pdf"
    when "zip", "web"
      send_data ArtifactExports.zip(version), filename: "#{name}-v#{version.number}.zip", type: "application/zip"
    when "html"
      send_data ArtifactRendering.html(version), filename: "#{name}.html", type: "text/html", disposition: "attachment"
    when "source"
      send_data version.content, filename: "#{name}.#{version.kind == 'html' ? 'html' : 'txt'}", type: "text/plain", disposition: "attachment"
    when "file"
      raise ActiveRecord::RecordNotFound unless version.file.attached?
      send_blob_stream version.file.blob, disposition: "attachment"
    else
      head :bad_request
    end
  end

  private

  def set_artifact
    @artifact = Current.workspace.artifacts.find(params[:id])
    response.headers["Cache-Control"] = "private, no-store"
  end

  def require_active
    redirect_to artifacts_path, alert: "That artifact is deleted. Restore it first." if @artifact.archived?
  end

  def selected_version
    params[:version_id].present? ? @artifact.versions.find(params[:version_id]) : @artifact.current_version
  end

  def artifact_params
    params.require(:artifact).permit(:title, :kind, :content, :expected_version, :design_kit_id, :file).tap { |data| data[:content] ||= "" }
  end

  def live_notice(message)
    @artifact.published_version_id ? "#{message} It's live on the public link." : message
  end

  def messages(error)
    error.is_a?(ActiveRecord::RecordInvalid) ? "#{error.record.errors.full_messages.to_sentence}." : error.message
  end
end
