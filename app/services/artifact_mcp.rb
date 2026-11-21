require "mcp"
require "digest"

class ArtifactMcp
  class IdempotencyMismatch < ArgumentError; end
  class Server < MCP::Server
    private

    def error_tool_response(message)
      ArtifactMcp.error_response("invalid_request", message).to_h
    end
  end
  STRING = { type: "string" }.freeze
  INTEGER = { type: "integer", minimum: 1 }.freeze
  ID = { id: INTEGER }.freeze
  PAGE = { offset: { type: "integer", minimum: 0 } }.freeze
  KIND = { type: "string", enum: %w[markdown html doc sheet slides], description: "markdown = prose; html = interactive page; doc, sheet, slides = structured JSON." }.freeze
  CONTENT = { type: "string", description: "For doc/sheet/slides: JSON source as a string per get_artifact_schema: {kind,blocks:[{t,...}]} for doc; {kind,tabs:[{name,columns:[{title,format?}],rows:[[value or {f:\"=...\"}]]}]} for sheet (row 1 is titles); {kind,slides:[{layout,...}]} for slides. " \
    "For markdown: GitHub-flavoured Markdown (headings, lists, tables, task lists, links; raw HTML is dropped). " \
    "For html: a complete HTML document (<!doctype html>...) or a fragment. Inline <script> and <style> run in a sandbox; " \
    "libraries load only from cdnjs.cloudflare.com, cdn.jsdelivr.net, unpkg.com and cdn.tailwindcss.com, fonts from Google Fonts, images from data: or https: URLs. " \
    "No fetch/XHR and no localStorage; forms, alert() and downloads work but cannot send data anywhere. Keep all data inside the page, and give links target=\"_blank\". " \
    "Mark static text the owner should edit with a unique data-kilat-editable name on a text-only element, e.g. <h1 data-kilat-editable=\"report-title\">Quarterly report</h1>. Preserve these markers when revising." }.freeze
  INSTRUCTIONS = "Kilat Artifact stores pages you write for the user. Use markdown for prose and html for designed or interactive pages. " \
    "Every result has url: give the user that link. It opens the artifact for its owner, and for anyone once it is public. " \
    "Read the latest content before editing. Update and restore require expected_version; on version_conflict read again, reapply your change and retry. " \
    "Use request_id to retry identical create, update or restore calls safely. Public links may follow latest or be pinned. " \
    "Making something public or advancing its pin is the user's call: ask before publish_artifact.".freeze
  TOOL_SPECS = [
    [ "get_artifact_schema", "read", "Read the portable JSON schema for doc, sheet or slides", { kind: { type: "string", enum: ArtifactTypes::KINDS } }, %w[kind] ],
    [ "list_artifacts", "read", "List the workspace's artifacts, newest first (100 per page)", PAGE, [] ],
    [ "get_artifact", "read", "Read an artifact with the content of its latest version, or of an older version number", ID.merge(version: INTEGER), %w[id] ],
    [ "create_artifact", "write", "Create a private artifact. Reuse request_id only to retry the identical call", { request_id: { type: "string", minLength: 1, maxLength: 128 }, title: STRING, kind: KIND, content: CONTENT, design_kit_id: INTEGER }, %w[request_id title kind content] ],
    [ "update_artifact", "write", "Save full new content with the version you read as expected_version. Reuse request_id only for identical retries. Unpinned public links change immediately.",
      ID.merge(content: CONTENT, title: STRING, kind: KIND, expected_version: INTEGER, request_id: { type: "string", minLength: 1, maxLength: 128 }), %w[id content expected_version] ],
    [ "artifact_history", "read", "List versions (number, title, author, date; no content), newest first (100 per page). Read one with get_artifact and version", ID.merge(PAGE), %w[id] ],
    [ "restore_artifact", "write", "Append an older version as latest, requiring expected_version. Reuse request_id only for identical retries.", ID.merge(version: INTEGER, expected_version: INTEGER, request_id: { type: "string", minLength: 1, maxLength: 128 }), %w[id version expected_version] ],
    [ "delete_artifact", "write", "Delete an artifact: its link stops working at once. The owner can restore it from the web app for 7 days", ID, %w[id] ],
    [ "list_design_kits", "read", "List workspace design kits (100 per page)", PAGE, [] ],
    [ "create_design_kit", "write", "Create a shared design kit (font, colours) used to style markdown artifacts", { name: STRING, tokens: { type: "object", properties: { font: STRING, background: STRING, foreground: STRING, accent: STRING }, additionalProperties: false } }, %w[name tokens] ],
    [ "update_design_kit", "write", "Update a shared design kit", ID.merge(name: STRING, tokens: { type: "object", properties: { font: STRING, background: STRING, foreground: STRING, accent: STRING }, additionalProperties: false }), %w[id name tokens] ],
    [ "publish_artifact", "publish", "Make the artifact public, or advance an existing public pin to latest. Ask the user first; publish scope explicitly delegates this action", ID, %w[id] ],
    [ "unpublish_artifact", "publish", "Make the artifact private again: its url then works only for the owner", ID, %w[id] ]
  ].freeze
  INPUT_KEYS = TOOL_SPECS.to_h { |name, _, _, properties, _| [ name, properties.keys ] }.freeze
  TOOLS = TOOL_SPECS.map do |name, scope, description, properties, required|
    Class.new(MCP::Tool) do
      tool_name name
      description description
      input_schema(type: "object", properties: properties, required: required, additionalProperties: false)
      define_singleton_method(:call) do |server_context:, **arguments|
        unless server_context[:scopes].include?(scope)
          next ArtifactMcp.error_response("permission_denied", "Permission denied: #{scope} scope required", required_scope: scope)
        end
        begin
          result = ArtifactMcp.perform(name, server_context[:workspace], arguments, base_url: server_context[:base_url], actor: server_context[:actor])
          MCP::Tool::Response.new([ { type: "text", text: JSON.generate(result) } ])
        rescue ActiveRecord::RecordNotFound
          ArtifactMcp.error_response("not_found", "Not found in this workspace")
        rescue Artifact::Conflict => error
          ArtifactMcp.error_response("version_conflict", error.message, current_version: error.current_version,
            recovery: "Call get_artifact, reapply your change to the latest content, retry with expected_version=current_version")
        rescue IdempotencyMismatch => error
          ArtifactMcp.error_response("idempotency_mismatch", error.message)
        rescue ActiveRecord::RecordInvalid, ArgumentError => error
          ArtifactMcp.error_response("invalid_request", error.message)
        end
      end
    end
  end.freeze

  def self.error_response(code, message, **details)
    MCP::Tool::Response.new([ { type: "text", text: JSON.generate({ error: code, message: message }.merge(details)) } ], error: true)
  end

  def self.perform(name, workspace, input, base_url: nil, actor: nil, receipt: true)
    raise ActiveRecord::RecordNotFound unless workspace
    input = input.to_h.symbolize_keys.slice(*INPUT_KEYS.fetch(name))
    input[:tokens] = input[:tokens].transform_keys(&:to_s) if input[:tokens].is_a?(Hash)
    if receipt && %w[create_artifact update_artifact restore_artifact].include?(name)
      request_id = input[:request_id]
      if name == "create_artifact" || input.key?(:request_id)
        raise ArgumentError, "request_id must contain 1–128 characters" unless request_id.is_a?(String) && request_id.length.between?(1, 128)
        identity = [ actor.class.name, actor.id ] if actor
        fingerprint = Digest::SHA256.hexdigest(JSON.generate([ name, identity, input.except(:request_id).sort.to_h ]))
        return workspace.with_lock do
          previous = McpRequest.find_by(workspace: workspace, request_id: request_id)
          if previous
            raise IdempotencyMismatch, "request_id already used with different input, tool or connection" unless previous.fingerprint == fingerprint
            previous.result
          else
            result = perform(name, workspace, input, base_url: base_url, actor: actor, receipt: false)
            McpRequest.create!(workspace: workspace, request_id: request_id, fingerprint: fingerprint, result: result)
            result
          end
        end
      end
    end
    input.delete(:request_id)
    author = actor&.name || "MCP"
    case name
    when "get_artifact_schema"
      ArtifactTypes.schema(input.fetch(:kind))
    when "list_artifacts"
      workspace.artifacts.active.includes(:current_version).order(id: :desc).offset(input.fetch(:offset, 0)).limit(100).map { |artifact| summary(artifact, base_url) }
    when "get_artifact"
      artifact = workspace.artifacts.active.find(input[:id])
      version = input[:version] ? artifact.versions.find_by!(number: input[:version]) : artifact.current_version
      summary(artifact, base_url).merge("content" => version.content, "version" => version.number, "latest_version" => artifact.current_version.number, "author" => version.author, "connection" => version.connection, "file" => file_data(version))
    when "create_artifact"
      workspace.design_kits.find(input[:design_kit_id]) if input[:design_kit_id]
      summary(workspace.artifacts.create_draft!(**input, author: author, actor: actor), base_url)
    when "update_artifact"
      artifact = workspace.artifacts.active.find(input[:id])
      raise ArgumentError, "A file artifact can't be changed here" if artifact.kind == "file"
      raise ArgumentError, "expected_version is required" unless input[:expected_version]
      artifact.with_lock do
        artifact.revise!(expected_version: input[:expected_version], title: input[:title].presence || artifact.title,
          kind: input[:kind] || artifact.kind, content: input[:content], author: author, actor: actor)
        summary(artifact, base_url)
      end
    when "artifact_history"
      workspace.artifacts.active.find(input[:id]).versions.order(number: :desc).offset(input.fetch(:offset, 0)).limit(100)
        .map { |version| version.as_json(only: %i[number title kind author created_at]).merge("connection" => version.connection) }
    when "restore_artifact"
      artifact = workspace.artifacts.active.find(input[:id])
      raise ArgumentError, "expected_version is required" unless input[:expected_version]
      artifact.with_lock do
        artifact.restore!(version_id: artifact.versions.find_by!(number: input[:version]).id, expected_version: input[:expected_version], author: author, actor: actor)
        summary(artifact, base_url)
      end
    when "delete_artifact"
      artifact = workspace.artifacts.active.find(input[:id])
      artifact.archive!
      { "id" => artifact.id, "deleted" => true, "restorable_until" => artifact.purge_at }
    when "list_design_kits"
      workspace.design_kits.order(:id).offset(input.fetch(:offset, 0)).limit(100).map { |kit| kit.as_json(only: %i[id name tokens version]) }
    when "create_design_kit"
      workspace.design_kits.create!(**input).as_json(only: %i[id name tokens version])
    when "update_design_kit"
      kit = workspace.design_kits.find(input.delete(:id))
      kit.update!(**input)
      kit.as_json(only: %i[id name tokens version])
    when "publish_artifact"
      artifact = workspace.artifacts.active.find(input[:id])
      artifact.publish!
      summary(artifact, base_url)
    when "unpublish_artifact"
      artifact = workspace.artifacts.active.find(input[:id])
      artifact.unpublish!
      summary(artifact, base_url)
    end
  end

  # url is the one link to give people: the owner can open it while private, everyone once public.
  def self.summary(artifact, base_url = nil)
    data = artifact.as_json(only: %i[id title kind design_kit_id updated_at])
      .merge("version" => artifact.current_version&.number, "public" => artifact.published_version_id.present?, "public_version" => artifact.public_version_number)
    return data unless base_url
    data.merge("url" => "#{base_url}/p/#{artifact.public_id}", "edit_url" => "#{base_url}/artifacts/#{artifact.id}?edit=1")
  end

  def self.file_data(version)
    version.file.attached? ? { "filename" => version.file.filename.to_s, "content_type" => version.file.content_type, "byte_size" => version.file.byte_size } : nil
  end
end
