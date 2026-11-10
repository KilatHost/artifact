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
    artifact.publish!
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
    ArtifactMcp.perform("update_artifact", @workspace, { id: @artifact.id, content: "<p>c</p>", author: "Spoofed", workspace_id: 999 })
    assert_equal "MCP", @artifact.reload.current_version.author
    assert_equal @workspace.id, @artifact.workspace_id
  end

  test "an agent succeeds first try: create, update without reading, publish, change kind, delete" do
    base = "https://artifact.example"
    perform = ->(tool, input) { ArtifactMcp.perform(tool, @workspace, input, base_url: base) }
    created = perform.("create_artifact", { request_id: "r1", title: "Deck", kind: "markdown", content: "# Plan\n\n- one" })
    assert_equal "#{base}/p/#{Artifact.find(created["id"]).public_id}", created["url"]
    assert_equal 1, created["version"]
    assert_equal false, created["public"]
    updated = perform.("update_artifact", { id: created["id"], content: "# Plan\n\n- two" })
    assert_equal 2, updated["version"]
    assert_equal "Deck", updated["title"]
    published = perform.("publish_artifact", { id: created["id"] })
    assert published["public"]
    get URI(created["url"]).path + "/frame"
    assert_response :success
    assert_includes response.body, "<li>two</li>"
    assert_raises(Artifact::Conflict) { perform.("update_artifact", { id: created["id"], content: "x", expected_version: 1 }) }
    html = perform.("update_artifact", { id: created["id"], kind: "html", content: "<!doctype html><html><body><p id=x></p><script>x.textContent='ran'</script></body></html>" })
    assert_equal "html", html["kind"]
    history = perform.("artifact_history", { id: created["id"] })
    assert_equal [ 3, 2, 1 ], history.map { |v| v["number"] }
    refute history.first.key?("content")
    assert_equal "# Plan\n\n- one", perform.("get_artifact", { id: created["id"], version: 1 })["content"]
    perform.("restore_artifact", { id: created["id"], version: 2 })
    assert_equal 4, Artifact.find(created["id"]).current_version.number
    perform.("delete_artifact", { id: created["id"] })
    get URI(created["url"]).path
    assert_response :not_found
  end

  test "the viewer shows a private artifact and its switch only to the owner" do
    get public_artifact_path(@artifact.public_id)
    assert_redirected_to new_session_path, "signed-out visitors are sent to sign in, then back"
    get public_artifact_frame_path(@artifact.public_id)
    assert_response :not_found
    sign_in @intruder
    get public_artifact_path(@artifact.public_id)
    assert_response :not_found
    get public_artifact_frame_path(@artifact.public_id)
    assert_response :not_found

    sign_in @owner
    get public_artifact_path(@artifact.public_id)
    assert_response :success
    assert_includes response.body, "Only you"
    assert_includes response.body, 'role="switch"'
    post publish_artifact_path(@artifact), params: { return_to: "viewer" }
    assert_redirected_to public_artifact_path(@artifact.public_id)
    assert_equal @artifact.current_version_id, @artifact.reload.published_version_id
    post unpublish_artifact_path(@artifact), params: { return_to: "viewer" }
    assert_redirected_to public_artifact_path(@artifact.public_id)
    assert_nil @artifact.reload.published_version_id
  end

  test "visitors of a published artifact can download it but get no switch" do
    @artifact.publish!
    get public_artifact_path(@artifact.public_id)
    assert_response :success
    refute_includes response.body, 'role="switch"'
    get public_artifact_download_path(@artifact.public_id, export_format: "html")
    assert_response :success
    assert_includes response.body, "Owner only"
    assert_match "attachment", response.headers["Content-Disposition"]
  end

  test "a private artifact stays private when new versions are saved" do
    @artifact.revise!(expected_version: 1, title: "Plan", content: "<p>v2</p>", author: "Agent")
    assert_nil @artifact.reload.published_version_id
    get public_artifact_frame_path(@artifact.public_id)
    assert_response :not_found
  end

  test "artifact content runs in an opaque-origin sandbox on every response that carries it" do
    html = @workspace.artifacts.create_draft!(title: "Deck", kind: "html", content: "<!doctype html><html><head><title>Deck</title></head><body><script>document.title='x'</script></body></html>", author: "Agent")
    html.publish!
    sign_in @owner
    [ preview_artifact_path(html), public_artifact_frame_path(html.public_id) ].each do |path|
      get path
      assert_response :success
      policy = response.headers["Content-Security-Policy"]
      assert policy.start_with?("sandbox #{ArtifactRendering::SANDBOX};"), path
      refute_includes policy, "allow-top-navigation", path
      refute_includes policy, "allow-same-origin", path
      refute_includes policy.sub(/frame-ancestors [^;]*/, ""), "'self'", path
      assert_includes policy, "connect-src 'none'", path
      assert response.body.start_with?("<!doctype html><html><head><title>Deck</title>"), "a full HTML document is served as written"
    end
  end

  test "the frame opened as a page of its own goes to the viewer" do
    @artifact.publish!
    get public_artifact_frame_path(@artifact.public_id), headers: { "Sec-Fetch-Dest" => "document" }
    assert_redirected_to public_artifact_path(@artifact.public_id)
    get public_artifact_frame_path(@artifact.public_id), headers: { "Sec-Fetch-Dest" => "iframe" }
    assert_response :success
    assert_includes response.body, '<base target="_blank">', "links in documents open in a new tab"
  end

  test "markdown renders safely and keeps its source" do
    md = @workspace.artifacts.create_draft!(title: "Brief", kind: "markdown", content: "# Plan\n\n- **bold**\n\n---\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\n<script>alert(1)</script>\n\n[x](javascript:alert(1))", author: "Agent")
    assert_includes md.current_version.content, "# Plan"
    rendered = ArtifactRendering.html(md.current_version)
    %w[<h1>Plan</h1> <strong>bold</strong> <hr> <table> <td>1</td>].each { |fragment| assert_includes rendered, fragment }
    refute_includes rendered, "<script"
    refute_includes rendered, "javascript:"
    task = ArtifactRendering.markdown("- [x] done\n\n<input type=password>")
    assert_includes ArtifactRendering.sanitize_document('<input type="checkbox" checked><input type="password"><input>'), 'type="checkbox"'
    refute_includes ArtifactRendering.sanitize_document('<input type="password"><input type="text">'), "<input"
    assert_includes task, "disabled"
  end

  test "sign-up closes after the first account unless ALLOW_SIGNUP is set" do
    get new_registration_path
    assert_redirected_to new_session_path
    ENV["ALLOW_SIGNUP"] = "true"
    get new_registration_path
    assert_response :success
  ensure
    ENV.delete("ALLOW_SIGNUP")
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
