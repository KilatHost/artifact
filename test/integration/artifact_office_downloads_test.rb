require "test_helper"
require_relative "../test_helpers/artifact_office_examples"

class ArtifactOfficeDownloadsTest < ActionDispatch::IntegrationTest
  include ArtifactOfficeExamples

  setup do
    @user = User.create!(email: "office-#{SecureRandom.hex(6)}@example.test", password: "long-test-password-123")
    @workspace = @user.create_workspace!(name: "Office")
    @artifacts = [ office_doc, office_sheet, office_slides ].map do |source|
      @workspace.artifacts.create_draft!(title: "Export #{source['kind']}", kind: source["kind"], content: source.to_json, author: "Test")
    end
  end

  test "owner downloads matching Office formats and sees primary export links" do
    post session_path, params: { email: @user.email, password: "long-test-password-123" }
    @artifacts.each do |artifact|
      format = ArtifactTypes.primary_format(artifact.kind)
      get artifact_path(artifact)
      assert_response :success
      assert_select "a[href*='export_format=#{format}']", text: format.upcase
      get export_artifact_path(artifact, export_format: format)
      assert_download(artifact, format)
      get export_artifact_path(artifact, export_format: format == "docx" ? "xlsx" : "docx")
      assert_response :not_found
    end
  end

  test "public downloads require publication and offer Office PDF and HTML without ZIP" do
    @artifacts.each do |artifact|
      format = ArtifactTypes.primary_format(artifact.kind)
      get public_artifact_download_path(artifact.public_id, export_format: format)
      assert_response :not_found
      artifact.publish!
      get public_artifact_path(artifact.public_id)
      assert_response :success
      [ format, "pdf", "html" ].each { |f| assert_select "a[href*='export_format=#{f}']", text: f.upcase }
      assert_select "a[href*='export_format=zip']", count: 0
      get public_artifact_download_path(artifact.public_id, export_format: format)
      assert_download(artifact, format)
      get public_artifact_download_path(artifact.public_id, export_format: format == "docx" ? "xlsx" : "docx")
      assert_response :not_found
    end
  end

  test "public ZIP cannot expose hidden Markdown source while owner ZIP remains available" do
    artifact = @workspace.artifacts.create_draft!(title: "Notes", kind: "markdown", content: "Public text\n<!-- private source note -->", author: "Test")
    artifact.publish!
    get public_artifact_download_path(artifact.public_id, export_format: "zip")
    assert_response :bad_request
    refute_includes response.body, "private source note"
    post session_path, params: { email: @user.email, password: "long-test-password-123" }
    get export_artifact_path(artifact, export_format: "zip")
    assert_response :success
    Zip::File.open_buffer(response.body) { |zip| assert_includes zip.read("source.md"), "private source note" }
  end

  private

  def assert_download(artifact, format)
    assert_response :success
    assert_equal ArtifactTypes::CONTENT_TYPES.fetch(format), response.media_type
    assert_includes response.headers["Content-Disposition"], "export-#{artifact.kind}-v1.#{format}"
    assert response.body.start_with?("PK")
  end
end
