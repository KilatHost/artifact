require "mcp"
require "digest"

class ArtifactMcp
  STRING = { type: "string" }.freeze
  INTEGER = { type: "integer", minimum: 1 }.freeze
  ID = { id: INTEGER }.freeze
  PAGE = { offset: { type: "integer", minimum: 0 } }.freeze
  KIND = { type: "string", enum: %w[markdown html], description: "markdown = prose (briefs, notes, docs, reports). html = a designed or interactive page (slide decks, dashboards, landing pages, charts)." }.freeze
  CONTENT = { type: "string", description: "For markdown: GitHub-flavoured Markdown (headings, lists, tables, task lists, links; raw HTML is dropped). " \
    "For html: a complete HTML document (<!doctype html>...) or a fragment. Inline <script> and <style> run in a sandbox; " \
    "libraries load only from cdnjs.cloudflare.com, cdn.jsdelivr.net, unpkg.com and cdn.tailwindcss.com, fonts from Google Fonts, images from data: or https: URLs. " \
    "No fetch/XHR and no localStorage; forms, alert() and downloads work but cannot send data anywhere. Keep all data inside the page, and give links target=\"_blank\"." }.freeze
  INSTRUCTIONS = "Kilat Artifact stores pages you write for the user. Use markdown for prose and html for designed or interactive pages. " \
    "Every result has url: give the user that link. It opens the artifact for its owner, and for anyone once it is public. " \
    "To change an artifact, call update_artifact with its id and the full new content; there is no need to read it first. " \
    "A public artifact always shows its latest version, so an update is live at once. Making something public is the user's call: ask before publish_artifact.".freeze
  TOOL_SPECS = [
    [ "list_artifacts", "read", "List the workspace's artifacts, newest first (100 per page)", PAGE, [] ],
    [ "get_artifact", "read", "Read an artifact with the content of its latest version, or of an older version number", ID.merge(version: INTEGER), %w[id] ],
    [ "create_artifact", "write", "Create a private artifact. Reuse request_id only to retry the identical call", { request_id: { type: "string", minLength: 1, maxLength: 128 }, title: STRING, kind: KIND, content: CONTENT, design_kit_id: INTEGER }, %w[request_id title kind content] ],
    [ "update_artifact", "write", "Save a new version with the full new content. title and kind are optional (kind may switch between markdown and html). " \
      "expected_version is optional: pass the version you read to refuse saving over someone else's newer edit. Live at once if the artifact is public",
      ID.merge(content: CONTENT, title: STRING, kind: KIND, expected_version: INTEGER), %w[id content] ],
    [ "artifact_history", "read", "List versions (number, title, author, date; no content), newest first (100 per page). Read one with get_artifact and version", ID.merge(PAGE), %w[id] ],
    [ "restore_artifact", "write", "Save an older version number as the new latest version (live at once if public)", ID.merge(version: INTEGER), %w[id version] ],
    [ "delete_artifact", "write", "Delete an artifact: its link stops working at once. The owner can restore it from the web app for 7 days", ID, %w[id] ],
    [ "list_design_kits", "read", "List workspace design kits (100 per page)", PAGE, [] ],
    [ "create_design_kit", "write", "Create a shared design kit (font, colours) used to style markdown artifacts", { name: STRING, tokens: { type: "object", properties: { font: STRING, background: STRING, foreground: STRING, accent: STRING }, additionalProperties: false } }, %w[name tokens] ],
    [ "update_design_kit", "write", "Update a shared design kit", ID.merge(name: STRING, tokens: { type: "object", properties: { font: STRING, background: STRING, foreground: STRING, accent: STRING }, additionalProperties: false }), %w[id name tokens] ],
    [ "publish_artifact", "publish", "Make the artifact public: anyone with its url can open it, and it always shows the latest version. Ask the user first", ID, %w[id] ],
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
          next MCP::Tool::Response.new([ { type: "text", text: "Permission denied: #{scope} scope required" } ], error: true)
        end
        begin
          result = ArtifactMcp.perform(name, server_context[:workspace], arguments, base_url: server_context[:base_url])
          MCP::Tool::Response.new([ { type: "text", text: JSON.generate(result) } ])
        rescue ActiveRecord::RecordNotFound
          MCP::Tool::Response.new([ { type: "text", text: "Not found in this workspace" } ], error: true)
        rescue ActiveRecord::RecordInvalid, Artifact::Conflict, ArgumentError => error
          MCP::Tool::Response.new([ { type: "text", text: error.message } ], error: true)
        end
      end
    end
  end.freeze

  def self.perform(name, workspace, input, base_url: nil)
    raise ActiveRecord::RecordNotFound unless workspace
    input = input.to_h.symbolize_keys.slice(*INPUT_KEYS.fetch(name))
    input[:tokens] = input[:tokens].transform_keys(&:to_s) if input[:tokens].is_a?(Hash)
    author = "MCP"
    case name
    when "list_artifacts"
      workspace.artifacts.active.includes(:current_version).order(id: :desc).offset(input.fetch(:offset, 0)).limit(100).map { |artifact| summary(artifact, base_url) }
    when "get_artifact"
      artifact = workspace.artifacts.active.find(input[:id])
      version = input[:version] ? artifact.versions.find_by!(number: input[:version]) : artifact.current_version
      summary(artifact, base_url).merge("content" => version.content, "version" => version.number, "latest_version" => artifact.current_version.number, "author" => version.author, "file" => file_data(version))
    when "create_artifact"
      request_id = input.delete(:request_id)
      raise ArgumentError, "request_id must contain 1–128 characters" unless request_id.is_a?(String) && request_id.length.between?(1, 128)
      fingerprint = Digest::SHA256.hexdigest(JSON.generate(input.sort.to_h))
      workspace.with_lock do
        previous = McpRequest.find_by(workspace: workspace, request_id: request_id)
        if previous
          raise ArgumentError, "request_id already used with different input" unless previous.fingerprint == fingerprint
          previous.result
        else
          workspace.design_kits.find(input[:design_kit_id]) if input[:design_kit_id]
          result = summary(workspace.artifacts.create_draft!(**input, author: author), base_url)
          McpRequest.create!(workspace: workspace, request_id: request_id, fingerprint: fingerprint, result: result)
          result
        end
      end
    when "update_artifact"
      artifact = workspace.artifacts.active.find(input[:id])
      raise ArgumentError, "A file artifact can't be changed here" if artifact.kind == "file"
      artifact.revise!(expected_version: input[:expected_version] || artifact.current_version.number, title: input[:title].presence || artifact.title,
        kind: input[:kind] || artifact.kind, content: input[:content], author: author)
      summary(artifact.reload, base_url)
    when "artifact_history"
      workspace.artifacts.active.find(input[:id]).versions.order(number: :desc).offset(input.fetch(:offset, 0)).limit(100)
        .map { |version| version.as_json(only: %i[number title kind author created_at]) }
    when "restore_artifact"
      artifact = workspace.artifacts.active.find(input[:id])
      artifact.restore!(version_id: artifact.versions.find_by!(number: input[:version]).id, expected_version: artifact.current_version.number, author: author)
      summary(artifact.reload, base_url)
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
      .merge("version" => artifact.current_version&.number, "public" => artifact.published_version_id.present?)
    return data unless base_url
    data.merge("url" => "#{base_url}/p/#{artifact.public_id}", "edit_url" => "#{base_url}/artifacts/#{artifact.id}")
  end

  def self.file_data(version)
    version.file.attached? ? { "filename" => version.file.filename.to_s, "content_type" => version.file.content_type, "byte_size" => version.file.byte_size } : nil
  end
end
