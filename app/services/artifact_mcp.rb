require "mcp"
require "digest"

class ArtifactMcp
  STRING = { type: "string" }.freeze
  INTEGER = { type: "integer", minimum: 1 }.freeze
  ID = { id: INTEGER }.freeze
  TOOL_SPECS = [
    [ "list_artifacts", "read", "List private workspace artifacts (100 per page)", { offset: { type: "integer", minimum: 0 } }, [] ],
    [ "get_artifact", "read", "Read an artifact and its current version", ID, %w[id] ],
    [ "create_artifact", "write", "Create a private document or HTML draft; reuse request_id only to retry identical input", { request_id: { type: "string", minLength: 1, maxLength: 128 }, title: STRING, kind: { type: "string", enum: %w[document html] }, content: STRING, design_kit_id: INTEGER }, %w[request_id title kind content] ],
    [ "update_artifact", "write", "Revise a draft using optimistic version locking", ID.merge(title: STRING, content: STRING, expected_version: INTEGER), %w[id title content expected_version] ],
    [ "artifact_history", "read", "Read immutable version history (100 per page)", ID.merge(offset: { type: "integer", minimum: 0 }), %w[id] ],
    [ "restore_artifact", "write", "Restore an old version as a new draft", ID.merge(version_id: INTEGER, expected_version: INTEGER), %w[id version_id expected_version] ],
    [ "list_design_kits", "read", "List workspace design kits (100 per page)", { offset: { type: "integer", minimum: 0 } }, [] ],
    [ "create_design_kit", "write", "Create a shared design kit", { name: STRING, tokens: { type: "object", properties: { font: STRING, background: STRING, foreground: STRING, accent: STRING }, additionalProperties: false } }, %w[name tokens] ],
    [ "update_design_kit", "write", "Update a shared design kit", ID.merge(name: STRING, tokens: { type: "object", properties: { font: STRING, background: STRING, foreground: STRING, accent: STRING }, additionalProperties: false }), %w[id name tokens] ],
    [ "publish_artifact", "publish", "Publish a specified immutable snapshot publicly", ID.merge(version_id: INTEGER), %w[id version_id] ],
    [ "unpublish_artifact", "publish", "Remove public access to an artifact", ID, %w[id] ]
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
          result = ArtifactMcp.perform(name, server_context[:workspace], arguments)
          MCP::Tool::Response.new([ { type: "text", text: JSON.generate(result) } ])
        rescue ActiveRecord::RecordNotFound
          MCP::Tool::Response.new([ { type: "text", text: "Not found in this workspace" } ], error: true)
        rescue ActiveRecord::RecordInvalid, Artifact::Conflict, ArgumentError => error
          MCP::Tool::Response.new([ { type: "text", text: error.message } ], error: true)
        end
      end
    end
  end.freeze

  def self.perform(name, workspace, input)
    raise ActiveRecord::RecordNotFound unless workspace
    input = input.to_h.symbolize_keys.slice(*INPUT_KEYS.fetch(name))
    input[:tokens] = input[:tokens].transform_keys(&:to_s) if input[:tokens].is_a?(Hash)
    author = "MCP"
    case name
    when "list_artifacts"
      workspace.artifacts.active.order(id: :desc).offset(input.fetch(:offset, 0)).limit(100).map { |artifact| summary(artifact) }
    when "get_artifact"
      artifact = workspace.artifacts.active.find(input[:id])
      summary(artifact).merge(version: version_data(artifact.current_version))
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
          result = summary(workspace.artifacts.create_draft!(**input, author: author))
          McpRequest.create!(workspace: workspace, request_id: request_id, fingerprint: fingerprint, result: result)
          result
        end
      end
    when "update_artifact"
      artifact = workspace.artifacts.active.find(input.delete(:id))
      version_data(artifact.revise!(**input, author: author))
    when "artifact_history"
      workspace.artifacts.active.find(input[:id]).versions.order(number: :desc).offset(input.fetch(:offset, 0)).limit(100).map { |version| version_data(version) }
    when "restore_artifact"
      artifact = workspace.artifacts.active.find(input.delete(:id))
      version_data(artifact.restore!(**input, author: author))
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
      artifact.publish!(version_id: input[:version_id])
      summary(artifact)
    when "unpublish_artifact"
      artifact = workspace.artifacts.active.find(input[:id])
      artifact.unpublish!
      summary(artifact)
    end
  end

  def self.summary(artifact)
    artifact.as_json(only: %i[id title kind current_version_id published_version_id public_id design_kit_id updated_at])
  end

  def self.version_data(version)
    version.as_json(only: %i[id number title kind content design_tokens author created_at]).merge("file" => version.file.attached? ? { "filename" => version.file.filename.to_s, "content_type" => version.file.content_type, "byte_size" => version.file.byte_size } : nil)
  end
end
