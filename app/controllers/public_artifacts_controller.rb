# The public link to a published snapshot, /p/<public_id>, in the KilatHost/web viewer pattern:
# a thin Kilat bar above a sandboxed iframe. The snapshot itself is served by #frame with a
# sandbox CSP (no scripts, no network), so it never runs with this origin's rights.
class PublicArtifactsController < ActionController::Base
  include ActiveStorage::Streaming

  layout "viewer"
  before_action :set_version

  def show
    response.headers["X-Robots-Tag"] = "noindex, nofollow"
  end

  def frame
    raise ActiveRecord::RecordNotFound if @version.kind == "file"
    response.headers["Content-Security-Policy"] = "sandbox; default-src 'none'; style-src 'unsafe-inline'; img-src data:; base-uri 'none'; form-action 'none'; frame-ancestors 'self'"
    render html: ArtifactRendering.html(@version).html_safe, layout: false
  end

  def file
    raise ActiveRecord::RecordNotFound unless @version.kind == "file" && @version.file.attached?
    send_blob_stream @version.file.blob, disposition: "attachment"
  end

  private

  def set_version
    @artifact = Artifact.active.find_by!(public_id: params[:public_id])
    @version = @artifact.published_version or raise ActiveRecord::RecordNotFound
    response.headers["Cache-Control"] = "no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Referrer-Policy"] = "no-referrer"
  end
end
