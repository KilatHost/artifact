require "test_helper"
require_relative "../test_helpers/artifacts"

class ArtifactEditingFlowTest < ActionDispatch::IntegrationTest
  include ArtifactTestHelpers
  PASSWORD = "long-test-password-123".freeze

  setup do
    @owner = User.create!(email: "editor-#{SecureRandom.hex(4)}@example.test", password: PASSWORD)
    @workspace = @owner.create_workspace!(name: "Editing")
    @browser = open_session
    @browser.post session_path, params: { email: @owner.email, password: PASSWORD }
    @first_agent = agent_connection("Creator")
    @second_agent = agent_connection("Reviewer")
  end

  test "typed artifacts use source editing and retain MCP version and actor contracts" do
    ArtifactTypes::KINDS.each do |kind|
      source = typed_source(kind).to_json
      artifact = create_from_agent(kind, source)
      @browser.get public_artifact_path(artifact.public_id, edit: "1")
      @browser.assert_response :success
      @browser.assert_select "label", "JSON source"
      @browser.assert_select "textarea[name='artifact[content]']", text: source
      @browser.assert_select "#draft-text-mode", count: 0
      @browser.patch artifact_path(artifact), params: { return_to: "viewer", artifact: { title: "Edited", expected_version: 1, content: source } }
      @browser.assert_response :see_other
      read = call_agent(@second_agent, "get_artifact", id: artifact.id)
      assert_equal [ 2, @owner.email, source ], read.values_at("version", "author", "content")
      revised = call_agent(@second_agent, "update_artifact", id: artifact.id, expected_version: 2, content: source)
      assert_equal 3, revised["version"]
      assert_equal "api_token", artifact.reload.current_version.actor_type
      @browser.patch artifact_path(artifact), params: { artifact: { title: "Invalid", expected_version: 3, content: "{}" } }
      @browser.assert_response :unprocessable_entity
      @browser.assert_select "textarea[name='artifact[content]']", text: "{}"
      assert_equal 3, artifact.versions.count
    end
  end

  test "typed draft previews report the same validation messages as saves without changing versions" do
    ArtifactTypes::KINDS.each do |kind|
      source = typed_source(kind).to_json
      artifact = create_from_agent(kind, source)
      edit = { title: "Preview", expected_version: 1, content: source }
      @browser.patch artifact_path(artifact), params: { preview: "1", artifact: edit }
      @browser.assert_response :success
      [ "{", "{}", "" ].each do |invalid|
        @browser.patch artifact_path(artifact), params: { preview: "1", artifact: edit.merge(content: invalid) }
        @browser.assert_response :unprocessable_entity
        assert_equal "text/plain", @browser.response.media_type
        message = @browser.response.body
        @browser.patch artifact_path(artifact), params: { artifact: edit.merge(content: invalid) }
        @browser.assert_response :unprocessable_entity
        @browser.assert_select "[role='alert']", text: message
        assert_equal source, artifact.reload.current_version.content
        assert_equal 1, artifact.versions.count
      end
    end
  end

  test "an MCP brief can be edited on the viewer then read and revised by a second agent" do
    source = "# Agent brief\n\nFirst paragraph.\n\n| Metric |\n| --- |\n| 42 |"
    artifact = create_from_agent("markdown", source)
    viewer_path = public_artifact_path(artifact.public_id)

    @browser.get viewer_path
    @browser.assert_select "a", "Edit"
    @browser.assert_select "a.viewer-edit-action[data-turbo=false]", "Edit"
    @browser.assert_select "form[data-controller='draft-editor']", count: 0
    @browser.get public_artifact_path(artifact.public_id, edit: "1")
    @browser.assert_select "input#markdown-line-0[value='Agent brief']"
    @browser.assert_select "textarea[name='artifact[content]']", text: /\| Metric \|/
    @browser.assert_select "a", "Cancel"

    edited = source.sub("Agent brief", "Human brief")
    @browser.patch artifact_path(artifact), params: { return_to: "viewer", artifact: { title: "Human brief", expected_version: 1, content: edited } }
    @browser.assert_redirected_to viewer_path
    @browser.follow_redirect!
    @browser.assert_select "[role='status']", "Version saved."
    @browser.get viewer_path
    @browser.assert_select ".viewer-menu strong", "Human brief"
    @browser.get public_artifact_frame_path(artifact.public_id)
    assert_includes @browser.response.body, "<h1>Human brief</h1>"

    read = call_agent(@second_agent, "get_artifact", id: artifact.id)
    assert_equal [ 2, @owner.email, edited ], read.values_at("version", "author", "content")
    revised = call_agent(@second_agent, "update_artifact", id: artifact.id, expected_version: 2, content: edited + "\n\nReviewed.")
    assert_equal 3, revised["version"]
    assert_equal source, artifact.versions.find_by!(number: 1).content
  end

  test "marked HTML edits are escaped, previewed without saving, and available to another agent" do
    source = '<h1 data-kilat-editable="report-title">Report</h1><div id="chart"><script>document.title="chart"</script></div>'
    artifact = create_from_agent("html", source)
    viewer_path = public_artifact_path(artifact.public_id)
    @browser.get public_artifact_path(artifact.public_id, edit: "1")
    @browser.assert_select "#html-block-report-title", "Report"
    @browser.assert_select "iframe[sandbox]:not([srcdoc])"
    assert_equal "same-origin", @browser.response.headers["Referrer-Policy"]

    edit = { title: "Report", expected_version: 1, blocks: { "report-title" => "<b>Approved</b>" } }
    @browser.patch artifact_path(artifact), params: { preview: "1", artifact: edit }
    @browser.assert_response :success
    assert_includes @browser.response.headers["Content-Security-Policy"], "sandbox #{ArtifactRendering::SANDBOX}"
    assert_includes @browser.response.body, "&lt;b&gt;Approved&lt;/b&gt;"
    assert_equal 1, artifact.versions.count

    @browser.patch artifact_path(artifact), params: { return_to: "viewer", artifact: edit }
    @browser.assert_redirected_to viewer_path
    read = call_agent(@second_agent, "get_artifact", id: artifact.id)
    assert_equal [ 2, @owner.email ], read.values_at("version", "author")
    assert_includes read["content"], 'data-kilat-editable="report-title">&lt;b&gt;Approved&lt;/b&gt;'
    assert_includes read["content"], '<script>document.title="chart"</script>'
    assert_equal source, artifact.versions.find_by!(number: 1).content
  end

  test "preview uses the selected design kit without changing the saved artifact" do
    artifact = create_from_agent("markdown", "# Brief")
    kit = @workspace.design_kits.create!(name: "Blue", tokens: { "accent" => "#123abc" })
    edit = { title: artifact.title, expected_version: 1, content: "# Edited brief", design_kit_id: kit.id }

    @browser.patch artifact_path(artifact), params: { preview: "1", artifact: edit }
    @browser.assert_response :success
    assert_includes @browser.response.body, "a{color:#123abc}"
    assert_nil artifact.reload.design_kit_id
    assert_equal 1, artifact.versions.count

    @browser.patch artifact_path(artifact), params: { artifact: edit }
    @browser.assert_redirected_to artifact_path(artifact)
    assert_equal "#123abc", artifact.reload.current_version.design_tokens.fetch("accent")

    @browser.patch artifact_path(artifact), params: { preview: "1", artifact: edit.merge(expected_version: 2, design_kit_id: "") }
    @browser.assert_response :success
    assert_includes @browser.response.body, "a{color:#171717}"
    assert_equal kit.id, artifact.reload.design_kit_id
    assert_equal 2, artifact.versions.count
  end

  test "a competing agent save keeps the owner's marked text and refuses the stale save" do
    artifact = create_from_agent("html", '<h1 data-kilat-editable="title">Original</h1>')
    @browser.get public_artifact_path(artifact.public_id, edit: "1")
    call_agent(@second_agent, "update_artifact", id: artifact.id, expected_version: 1, content: '<h1 data-kilat-editable="different">Agent revision</h1>')

    @browser.patch artifact_path(artifact), params: { return_to: "viewer", artifact: { title: "Unsaved title", expected_version: 1, blocks: { title: "Unsaved text" } } }

    @browser.assert_response :conflict
    @browser.assert_select "[role='alert']", text: /changed since you opened it/
    @browser.assert_select "#html-block-title", "Unsaved text"
    @browser.assert_select "input[name='artifact[title]'][value='Unsaved title']"
    @browser.assert_select "input[name='artifact[expected_version]'][value='1']"
    @browser.assert_select "input[type=submit][disabled]"
    assert_equal 2, artifact.versions.count
    assert_includes artifact.reload.current_version.content, "Agent revision"
  end

  test "public visitors and other workspaces cannot open or submit the editor" do
    artifact = create_from_agent("markdown", "# Public brief")
    artifact.publish!
    edit_viewer = public_artifact_path(artifact.public_id, edit: "1")
    get edit_viewer
    assert_response :success
    assert_select "a", text: "Edit", count: 0
    assert_select "form[data-controller='draft-editor']", count: 0

    patch artifact_path(artifact), params: { artifact: { title: "Forged", content: "Forged", expected_version: 1 } }
    assert_redirected_to new_session_path

    outsider = User.create!(email: "outsider-#{SecureRandom.hex(4)}@example.test", password: PASSWORD)
    outsider.create_workspace!(name: "Other")
    post session_path, params: { email: outsider.email, password: PASSWORD }
    get edit_viewer
    assert_response :success
    assert_select "form[data-controller='draft-editor']", count: 0
    patch artifact_path(artifact), params: { artifact: { title: "Forged", content: "Forged", expected_version: 1 }, preview: "1" }
    assert_response :not_found
    assert_equal 1, artifact.versions.count
  end

  test "saving in the viewer leaves the public link pinned until the owner updates it" do
    previous_mode = ENV["KILAT_PUBLIC_LINKS"]
    ENV["KILAT_PUBLIC_LINKS"] = "pinned"
    artifact = create_from_agent("markdown", "# Shared revision")
    viewer_path = public_artifact_path(artifact.public_id)
    frame_path = public_artifact_frame_path(artifact.public_id)

    @browser.post publish_artifact_path(artifact), params: { return_to: "viewer" }
    @browser.assert_redirected_to viewer_path
    assert_equal 1, artifact.reload.public_version_number

    @browser.get public_artifact_path(artifact.public_id, edit: "1")
    @browser.assert_select ".caption", "Saving leaves the public link pinned until you update it."
    @browser.patch artifact_path(artifact), params: { return_to: "viewer", artifact: { title: "Working draft", content: "# Working draft", expected_version: 1 } }
    @browser.assert_redirected_to viewer_path
    @browser.follow_redirect!
    @browser.assert_select "[role=status]", "Version saved."
    @browser.assert_select ".viewer-visibility", "Public link: version 1"
    assert_equal 1, artifact.reload.public_version_number
    assert_equal [ 2, "user", @owner.id ], artifact.current_version.attributes.values_at("number", "actor_type", "actor_id")

    @browser.assert_select "iframe[src=?]", preview_artifact_path(artifact, version_id: artifact.current_version_id)
    get viewer_path
    assert_select ".viewer-menu strong", "Agent draft"
    get frame_path
    assert_includes response.body, "<h1>Shared revision</h1>"
    refute_includes response.body, "Working draft"

    @browser.get artifact_path(artifact)
    @browser.assert_select "button", "Update public link"
    @browser.post update_public_link_artifact_path(artifact)
    @browser.assert_redirected_to artifact_path(artifact)
    assert_equal 2, artifact.reload.public_version_number
    get frame_path
    assert_includes response.body, "<h1>Working draft</h1>"
  ensure
    ENV["KILAT_PUBLIC_LINKS"] = previous_mode
  end

  test "rich text uses Trix and uploaded files keep their separate replacement action" do
    document = @workspace.artifacts.create_draft!(title: "Notes", kind: "document", content: "<p>Original notes</p>", author: @owner.email)
    @browser.get public_artifact_path(document.public_id, edit: "1")
    @browser.assert_select "trix-editor[input='draft-document']"
    @browser.patch artifact_path(document), params: { return_to: "viewer", artifact: { title: "Notes", content: "<p>Updated <strong>notes</strong></p>", expected_version: 1 } }
    @browser.assert_redirected_to public_artifact_path(document.public_id)
    assert_equal "<p>Updated <strong>notes</strong></p>", document.reload.current_version.content

    file = Rack::Test::UploadedFile.new(StringIO.new("bytes"), "text/plain", original_filename: "notes.txt")
    upload = @workspace.artifacts.create_draft!(title: "Attachment", kind: "file", content: "", author: @owner.email, file: file)
    @browser.get artifact_path(upload, edit: "1")
    @browser.assert_select "form[data-controller='draft-editor']", count: 0
    @browser.assert_select "form[action=?] input[type=file]", upload_artifact_path(upload)
    @browser.patch artifact_path(upload), params: { artifact: { title: "Attachment", content: "Forged", expected_version: 1 } }
    @browser.assert_response :not_found
    assert_equal 1, upload.versions.count
  end

  private

  def agent_connection(name)
    _, secret = ApiToken.issue!(workspace: @workspace, name: name, scopes: %w[read write])
    [ open_session, { "Content-Type" => "application/json", "Accept" => "application/json, text/event-stream", "Authorization" => "Bearer #{secret}" } ]
  end

  def call_agent(connection, tool, **arguments)
    agent, headers = connection
    agent.post "/mcp", headers: headers, params: { jsonrpc: "2.0", id: 1, method: "tools/call", params: { name: tool, arguments: arguments } }.to_json
    agent.assert_response :success
    result = JSON.parse(agent.response.body).fetch("result")
    refute result["isError"], result.inspect
    JSON.parse(result.fetch("content").first.fetch("text"))
  end

  def create_from_agent(kind, content)
    result = call_agent(@first_agent, "create_artifact", request_id: SecureRandom.uuid, title: "Agent draft", kind: kind, content: content)
    Artifact.find(result.fetch("id"))
  end
end
