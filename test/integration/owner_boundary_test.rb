require "test_helper"

class OwnerBoundaryTest < ActionDispatch::IntegrationTest
  PASSWORD = "long-test-password-123".freeze

  setup do
    @owner = User.create!(email: "owner-#{SecureRandom.hex(4)}@example.test", password: PASSWORD)
    @workspace = @owner.create_workspace!(name: "Owner")
    @artifact = @workspace.artifacts.create_draft!(title: "Plan", kind: "document", content: "<p>Owner only</p>", author: @owner.email)
    @intruder = User.create!(email: "intruder-#{SecureRandom.hex(4)}@example.test", password: PASSWORD)
    @intruder.create_workspace!(name: "Intruder")
  end

  test "another workspace gets 404 on every artifact route" do
    sign_in @intruder
    version = @artifact.current_version
    requests = [
      [ :get, artifact_path(@artifact) ],
      [ :get, preview_artifact_path(@artifact) ],
      [ :get, export_artifact_path(@artifact, export_format: "source") ],
      [ :patch, artifact_path(@artifact), { artifact: { title: "Taken", content: "x", expected_version: 1 } } ],
      [ :post, publish_artifact_path(@artifact), { version_id: version.id } ],
      [ :post, restore_artifact_path(@artifact), { version_id: version.id, expected_version: 1 } ],
      [ :post, upload_artifact_path(@artifact), { expected_version: 1 } ],
      [ :post, archive_artifact_path(@artifact) ]
    ]
    requests.each do |verb, path, params|
      send(verb, path, params: params)
      assert_response :not_found, "#{verb.upcase} #{path}"
    end
    @artifact.reload
    assert_nil @artifact.published_version_id
    assert_nil @artifact.archived_at
    assert_equal 1, @artifact.versions.count
  end

  test "Active Storage routes are not mounted" do
    assert_raises(ActionController::RoutingError) { Rails.application.routes.recognize_path("/rails/active_storage/blobs/redirect/x/file.pdf") }
  end

  test "a stale save keeps the typed text and saves nothing" do
    sign_in @owner
    @artifact.revise!(expected_version: 1, title: "Plan", content: "<p>Newer</p>", author: "Agent")
    patch artifact_path(@artifact), params: { artifact: { title: "Plan", kind: "document", content: "<p>My unsaved paragraph</p>", expected_version: 1 } }
    assert_response :conflict
    assert_includes response.body, "My unsaved paragraph"
    assert_includes response.body, "changed since you opened it"
    assert_equal 2, @artifact.reload.versions.count
  end

  test "choosing Default clears the design kit" do
    sign_in @owner
    kit = @workspace.design_kits.create!(name: "Brand", tokens: DesignKit::DEFAULT_TOKENS.merge("accent" => "#ff0000"))
    @artifact.update!(design_kit: kit)
    patch artifact_path(@artifact), params: { artifact: { title: "Plan", kind: "document", content: "<p>x</p>", expected_version: 1, design_kit_id: "" } }
    assert_response :redirect
    @artifact.reload
    assert_nil @artifact.design_kit_id
    assert_equal "#171717", @artifact.current_version.design_tokens["accent"]
  end

  test "documents are sanitized when saved" do
    artifact = @workspace.artifacts.create_draft!(title: "x", kind: "document", content: '<p onclick="steal()">Hi</p><script>alert(1)</script><a href="javascript:alert(1)">l</a>', author: "Agent")
    stored = artifact.current_version.content
    refute_includes stored, "onclick"
    refute_includes stored, "<script"
    refute_includes stored, "javascript:"
    assert_includes stored, "Hi"
  end

  test "delete hides the artifact at once and purges it after 7 days" do
    sign_in @owner
    file = Rack::Test::UploadedFile.new(StringIO.new("bytes"), "text/plain", original_filename: "notes.txt")
    artifact = @workspace.artifacts.create_draft!(title: "File", kind: "file", content: "", author: @owner.email, file: file)
    artifact.publish!(version_id: artifact.current_version_id)
    blob = artifact.current_version.file.blob

    post archive_artifact_path(artifact)
    assert_redirected_to artifacts_path
    get public_artifact_path(artifact.public_id)
    assert_response :not_found
    assert_raises(ActiveRecord::RecordNotFound) { ArtifactMcp.perform("get_artifact", @workspace, { id: artifact.id }) }
    get artifact_path(artifact)
    assert_redirected_to artifacts_path

    assert_equal 0, Artifact.purge_archived!(now: 6.days.from_now)
    post unarchive_artifact_path(artifact)
    assert_redirected_to artifact_path(artifact)
    assert_nil artifact.reload.published_version_id, "restore must not re-publish"

    artifact.archive!
    assert_equal 1, Artifact.purge_archived!(now: 8.days.from_now)
    refute Artifact.exists?(artifact.id)
    refute ArtifactVersion.exists?(artifact_id: artifact.id)
    refute ActiveStorage::Blob.exists?(blob.id)
    assert Artifact.exists?(@artifact.id), "other artifacts stay"
  end

  test "PDF export answers busy instead of starting a second browser" do
    sign_in @owner
    ArtifactExports::PDF_LOCK.lock
    get export_artifact_path(@artifact, export_format: "pdf")
    assert_response :service_unavailable
  ensure
    ArtifactExports::PDF_LOCK.unlock if ArtifactExports::PDF_LOCK.owned?
  end

  test "MCP ignores keys a tool does not declare" do
    result = ArtifactMcp.perform("update_artifact", @workspace, { id: @artifact.id, title: "T", content: "<p>c</p>", expected_version: 1, author: "Spoofed", kind: "html" })
    assert_equal "MCP", result["author"]
    assert_equal "document", result["kind"]
  end

  test "MCP results carry the editor link, and the public link only while published" do
    base = "https://artifact.example"
    draft = ArtifactMcp.perform("get_artifact", @workspace, { id: @artifact.id }, base_url: base)
    assert_equal "#{base}/artifacts/#{@artifact.id}", draft["url"]
    assert_nil draft["public_url"]
    published = ArtifactMcp.perform("publish_artifact", @workspace, { id: @artifact.id, version_id: @artifact.current_version_id }, base_url: base)
    assert_equal "#{base}/p/#{@artifact.public_id}", published["public_url"]
  end

  test "revoking an OAuth client revokes all its tokens" do
    app = Doorkeeper::Application.create!(name: "Client", redirect_uri: "https://client.example/cb", scopes: "read", confidential: false)
    tokens = 2.times.map { Doorkeeper::AccessToken.create!(application: app, resource_owner_id: @owner.id, scopes: "read", expires_in: 3600) }
    sign_in @owner
    delete connection_path(app.id, oauth: 1)
    assert_redirected_to connections_path
    assert tokens.all? { |token| token.reload.revoked? }
  end

  private

  def sign_in(user)
    post session_path, params: { email: user.email, password: PASSWORD }
    assert_response :redirect
  end
end
