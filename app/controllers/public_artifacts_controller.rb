class PublicArtifactsController < ActionController::Base
  include ActiveStorage::Streaming

  def show
    artifact = Artifact.active.find_by!(public_id: params[:public_id])
    raise ActiveRecord::RecordNotFound unless artifact.published_version
    response.headers["Cache-Control"] = "no-store"
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["Referrer-Policy"] = "no-referrer"
    response.headers["Content-Security-Policy"] = "sandbox; default-src 'none'; style-src 'unsafe-inline'; img-src data:; base-uri 'none'; form-action 'none'"
    version = artifact.published_version
    if version.kind == "file"
      raise ActiveRecord::RecordNotFound unless version.file.attached?
      return send_blob_stream version.file.blob, disposition: "attachment"
    end
    render html: ArtifactRendering.html(artifact.published_version).html_safe, layout: false
  end
end
