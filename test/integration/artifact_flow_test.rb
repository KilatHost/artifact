require "test_helper"

class ArtifactFlowTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "owner-#{SecureRandom.hex(6)}@example.test", password: "long-test-password-123")
    @workspace = @user.workspace || @user.create_workspace!(name: "Owner")
    @other = User.create!(email: "other-#{SecureRandom.hex(6)}@example.test", password: "long-test-password-123")
    @other_workspace = @other.workspace || @other.create_workspace!(name: "Other")
  end

  test "versions reject stale writes, and a public link follows the latest version" do
    kit = @workspace.design_kits.create!(name: "Brand", tokens: DesignKit::DEFAULT_TOKENS)
    artifact = @workspace.artifacts.create_draft!(title: "Report", kind: "document", content: "<h1>Published report</h1>", author: @user.email, design_kit_id: kit.id)
    original = artifact.current_version
    artifact.publish!
    get public_artifact_path(artifact.public_id)
    assert_response :success
    assert_includes response.body, %(src="#{public_artifact_frame_path(artifact.public_id)}")
    get public_artifact_frame_path(artifact.public_id)
    assert_response :success
    assert_includes response.headers["Content-Security-Policy"], "sandbox"
    assert_includes response.body, "Published report"
    kit.update!(tokens: kit.tokens.merge("accent" => "#ff0000"))
    artifact.revise!(expected_version: 1, title: "Private revision", content: "<h1>Secret draft</h1>", author: @user.email)
    assert_equal "#171717", original.reload.design_tokens["accent"]
    assert_equal "#ff0000", artifact.current_version.design_tokens["accent"]
    assert_raises(Artifact::Conflict) { artifact.revise!(expected_version: 1, title: "Overwrite", content: "lost", author: "Agent") }
    assert_equal artifact.current_version_id, artifact.reload.published_version_id
    get public_artifact_frame_path(artifact.public_id)
    assert_includes response.body, "Secret draft"
    refute_includes response.body, "Published report"
    artifact.restore!(version_id: original.id, expected_version: 2, author: @user.email)
    assert_equal 3, artifact.current_version.number
    assert_equal original.content, artifact.current_version.content
    get public_artifact_frame_path(artifact.public_id)
    assert_includes response.body, "Published report", "a restore is live too"
    artifact.unpublish!
    get public_artifact_path(artifact.public_id)
    assert_redirected_to new_session_path
    get public_artifact_frame_path(artifact.public_id)
    assert_response :not_found
  end

  test "cross workspace kits and artifacts are rejected" do
    kit = @other_workspace.design_kits.create!(name: "Other", tokens: DesignKit::DEFAULT_TOKENS)
    assert_raises(ActiveRecord::RecordInvalid) do
      @workspace.artifacts.create_draft!(title: "Theft", kind: "document", content: "x", author: "Agent", design_kit_id: kit.id)
    end
    foreign = @other_workspace.artifacts.create_draft!(title: "Foreign", kind: "document", content: "private", author: "Agent")
    assert_raises(ActiveRecord::RecordNotFound) { @workspace.artifacts.find(foreign.id) }
  end

  test "unsafe design tokens rejected and document scripts stripped" do
    kit = @workspace.design_kits.new(name: "Unsafe", tokens: { "font" => "</style><script>alert(1)</script>" })
    refute kit.valid?
    artifact = @workspace.artifacts.create_draft!(title: "Safe", kind: "document", content: '<script>alert(1)</script><p onclick="steal()">Allowed text</p>', author: "Agent")
    html = ArtifactRendering.html(artifact.current_version)
    refute_includes html, "<script>"
    refute_includes html, "onclick="
    assert_includes html, "Allowed text"
  end
end
