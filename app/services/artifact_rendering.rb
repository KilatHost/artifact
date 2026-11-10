class ArtifactRendering
  DOCUMENT_TAGS = %w[p br h1 h2 h3 h4 strong em b i u s del blockquote pre code ul ol li a table thead tbody tr th td hr div span].freeze
  DOCUMENT_ATTRIBUTES = %w[href title colspan rowspan].freeze

  def self.sanitize_document(html)
    Rails::HTML5::SafeListSanitizer.new.sanitize(html.to_s, tags: DOCUMENT_TAGS, attributes: DOCUMENT_ATTRIBUTES)
  end

  def self.html(version)
    tokens = DesignKit::DEFAULT_TOKENS.merge(version.design_tokens)
    title = ERB::Util.html_escape(version.title)
    content = case version.kind
    when "document" then sanitize_document(version.content)
    when "file" then "<p>Download the original file to view this artifact.</p>"
    else version.content
    end
    css = "body{font-family:#{tokens.fetch('font')};background:#{tokens.fetch('background')};color:#{tokens.fetch('foreground')};margin:0;padding:34px;line-height:1.618;overflow-wrap:anywhere}main{max-width:880px;margin:auto}a{color:#{tokens.fetch('accent')}}img,svg,video{max-width:100%}pre{white-space:pre-wrap}table{border-collapse:collapse;width:100%}td,th{border:1px solid;padding:8px;text-align:left}@page{margin:15mm}@media print{body{padding:0;background:white;color:black}a{color:inherit}h1,h2,h3{break-after:avoid}tr,img{break-inside:avoid}}"
    "<!doctype html><html><head><meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\"><meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; style-src 'unsafe-inline'; img-src data:; font-src data:; base-uri 'none'; form-action 'none'\"><title>#{title}</title><style>#{css}</style></head><body><main>#{content}</main></body></html>"
  end
end
