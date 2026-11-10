require "commonmarker"

class ArtifactRendering
  DOCUMENT_TAGS = %w[p br h1 h2 h3 h4 h5 h6 strong em b i u s del blockquote pre code ul ol li a table thead tbody tr th td hr div span input].freeze
  DOCUMENT_ATTRIBUTES = %w[href title colspan rowspan align type checked disabled].freeze
  MARKDOWN_OPTIONS = { render: { unsafe: false }, extension: { table: true, strikethrough: true, autolink: true, tasklist: true, header_ids: nil } }.freeze
  # Hosts agent-written HTML may load libraries, styles and fonts from (founder, 2026-11-11).
  # ARTIFACT_EXTERNAL_RESOURCES=false limits artifacts to inline code and data: URIs.
  SCRIPT_HOSTS = %w[https://cdnjs.cloudflare.com https://cdn.jsdelivr.net https://unpkg.com https://cdn.tailwindcss.com].freeze
  STYLE_HOSTS = %w[https://fonts.googleapis.com https://cdnjs.cloudflare.com https://cdn.jsdelivr.net https://unpkg.com].freeze
  FONT_HOSTS = %w[https://fonts.gstatic.com https://cdnjs.cloudflare.com https://cdn.jsdelivr.net https://unpkg.com].freeze

  # Matches KilatHost/web's viewer. Never add allow-same-origin or allow-top-navigation.
  SANDBOX = "allow-scripts allow-forms allow-modals allow-popups allow-popups-to-escape-sandbox allow-downloads".freeze

  # Sent as a response header on every response that carries artifact content (preview and
  # frame). The sandbox has no allow-same-origin, so the page runs with an opaque origin: it
  # can run its own scripts but cannot read the app's cookies, storage or pages, and
  # connect-src 'none' stops it calling anything. Never add 'self' or allow-same-origin here.
  def self.content_security_policy
    external = ENV.fetch("ARTIFACT_EXTERNAL_RESOURCES", "true") != "false"
    hosts = ->(list) { external ? " #{list.join(' ')}" : "" }
    [
      "sandbox #{SANDBOX}",
      "default-src 'none'",
      "script-src 'unsafe-inline' 'unsafe-eval'#{hosts.(SCRIPT_HOSTS)}",
      "style-src 'unsafe-inline'#{hosts.(STYLE_HOSTS)}",
      "font-src data:#{hosts.(FONT_HOSTS)}",
      "img-src data: blob:#{external ? ' https:' : ''}",
      "media-src data: blob:#{external ? ' https:' : ''}",
      "connect-src 'none'", "form-action 'none'", "base-uri 'none'", "frame-ancestors 'self'"
    ].join("; ")
  end

  # input is allowed only for Markdown task lists: anything but a disabled checkbox is removed.
  def self.sanitize_document(html)
    clean = Rails::HTML5::SafeListSanitizer.new.sanitize(html.to_s, tags: DOCUMENT_TAGS, attributes: DOCUMENT_ATTRIBUTES)
    return clean unless clean.include?("<input")
    fragment = Nokogiri::HTML5.fragment(clean)
    fragment.css("input").each { |input| input["type"] == "checkbox" ? input["disabled"] = "" : input.remove }
    fragment.to_html
  end

  # Markdown is stored as written and rendered on view, so agents read back what they wrote.
  def self.markdown(source)
    sanitize_document(Commonmarker.to_html(source.to_s, options: MARKDOWN_OPTIONS, plugins: { syntax_highlighter: nil }))
  end

  def self.full_document?(content)
    content.to_s.lstrip.match?(/\A(<!--.*?-->\s*)*(<!doctype html|<html[\s>])/im)
  end

  # A complete HTML document is served exactly as written. Everything else is placed in a
  # plain page styled by the version's design tokens.
  def self.html(version)
    return version.content if version.kind == "html" && full_document?(version.content)

    tokens = DesignKit::DEFAULT_TOKENS.merge(version.design_tokens)
    title = ERB::Util.html_escape(version.title)
    body = case version.kind
    when "document" then "<main>#{sanitize_document(version.content)}</main>"
    when "markdown" then "<main>#{markdown(version.content)}</main>"
    when "file" then "<main><p>Download the original file to view this artifact.</p></main>"
    else version.content
    end
    css = "body{font-family:#{tokens.fetch('font')};background:#{tokens.fetch('background')};color:#{tokens.fetch('foreground')};margin:0;line-height:1.618;overflow-wrap:anywhere}main{max-width:880px;margin:auto;padding:34px}a{color:#{tokens.fetch('accent')}}img,svg,video{max-width:100%}pre{white-space:pre-wrap}code{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:.92em}pre,:not(pre)>code{background:color-mix(in srgb,currentColor 7%,transparent);border-radius:6px}pre{padding:13px}:not(pre)>code{padding:1px 5px}blockquote{margin:21px 0;padding-left:21px;border-left:3px solid color-mix(in srgb,currentColor 25%,transparent)}hr{border:0;border-top:1px solid color-mix(in srgb,currentColor 20%,transparent);margin:34px 0}table{border-collapse:collapse;width:100%}td,th{border:1px solid color-mix(in srgb,currentColor 25%,transparent);padding:8px;text-align:left}li:has(>input[type=checkbox]){list-style:none;margin-left:-1.2em}li>input[type=checkbox]{margin-right:8px}@page{margin:15mm}@media print{main{padding:0}body{background:white;color:black}a{color:inherit}h1,h2,h3{break-after:avoid}tr,img{break-inside:avoid}}"
    "<!doctype html><html><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><base target=\"_blank\"><title>#{title}</title><style>#{css}</style></head><body>#{body}</body></html>"
  end
end
