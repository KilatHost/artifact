module ApplicationHelper
  def artifact_export_formats(version)
    version.kind == "file" ? %w[file html pdf zip source] : %w[html pdf zip source]
  end
end
