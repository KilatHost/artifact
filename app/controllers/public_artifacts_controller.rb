# The link to an artifact, /p/<public_id>, in the pattern of Claude's artifact pages and KilatHost/web's
# viewer: a thin Kilat bar above a sandboxed iframe. The snapshot itself is served by #frame with a sandbox
# CSP (no scripts, no network), so it never runs with this origin's rights.
# Visitors see only the published version. The signed-in owner also sees a private artifact (its current
# version) and gets the Public/Private switch; everyone else gets 404 while it is private.
class PublicArtifactsController < ActionController::Base
  include ActiveStorage::Streaming

  layout "viewer"
  before_action :set_version
  rate_limit to: 10, within: 1.minute, only: :download, with: -> { render plain: "Too many downloads. Try again in a minute.", status: :too_many_requests }

  def show
    response.headers["X-Robots-Tag"] = "noindex, nofollow"
  end

  def frame
    raise ActiveRecord::RecordNotFound if @version.kind == "file"
    response.headers["Content-Security-Policy"] = ArtifactRendering.content_security_policy
    render html: ArtifactRendering.html(@version).html_safe, layout: false
  end

  def file
    raise ActiveRecord::RecordNotFound unless @version.kind == "file" && @version.file.attached?
    send_blob_stream @version.file.blob, disposition: "attachment"
  end

  def download
    raise ActiveRecord::RecordNotFound if @version.kind == "file"
    name = "#{@version.title.parameterize.presence || 'artifact'}-v#{@version.number}"
    case params[:export_format]
    when "pdf"
      pdf = ArtifactExports.pdf(@version)
      return render plain: "Another PDF is being made. Try again in a few seconds.", status: :service_unavailable unless pdf
      send_data pdf, filename: "#{name}.pdf", type: "application/pdf"
    when "html"
      send_data ArtifactRendering.html(@version), filename: "#{name}.html", type: "text/html", disposition: "attachment"
    else
      head :bad_request
    end
  end

  private

  def set_version
    @artifact = Artifact.active.find_by!(public_id: params[:public_id])
    user = User.find_by(id: session[:user_id])
    @owner = user.present? && user.workspace&.id == @artifact.workspace_id
    @version = @artifact.published_version || (@artifact.current_version if @owner)
    if @version.nil? && user.nil? && action_name == "show"
      session[:return_to] = request.fullpath
      return redirect_to(new_session_path, alert: "Sign in to open this artifact.")
    end
    raise ActiveRecord::RecordNotFound unless @version
    response.headers["Cache-Control"] = "private, no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Referrer-Policy"] = "no-referrer"
  end
end
