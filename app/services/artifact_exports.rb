require "zip"
require "ferrum"
class ArtifactExports
  PDF_LOCK = Mutex.new

  # One Chromium per process. Returns nil when a render is already running.
  def self.pdf(version)
    return unless PDF_LOCK.try_lock
    begin
      render_pdf(version)
    ensure
      PDF_LOCK.unlock
    end
  end

  def self.render_pdf(version)
    browser = Ferrum::Browser.new(browser_path: ENV["BROWSER_PATH"].presence, headless: true, timeout: 20, process_timeout: 20, browser_options: { "disable-dev-shm-usage" => nil, "disable-background-networking" => nil, "disable-extensions" => nil, "js-flags" => "--jitless" })
    browser.network.intercept
    browser.on(:request) { |request| request.abort }
    browser.page.command("Emulation.setScriptExecutionDisabled", value: true)
    browser.page.content = ArtifactRendering.html(version)
    Base64.decode64(browser.page.command("Page.printToPDF", printBackground: true, preferCSSPageSize: true).fetch("data"))
  ensure
    browser&.quit
  end

  def self.zip(version)
    Zip::OutputStream.write_buffer do |zip|
      zip.put_next_entry("index.html")
      zip.write(ArtifactRendering.html(version))
      zip.put_next_entry("source.#{version.kind == 'html' ? 'html' : 'txt'}")
      zip.write(version.content)
      zip.put_next_entry("manifest.json")
      zip.write({ artifact_id: version.artifact_id, version: version.number, title: version.title, kind: version.kind, design_tokens: version.design_tokens }.to_json)
      if version.file.attached?
        zip.put_next_entry("attachment")
        version.file.download { |chunk| zip.write(chunk) }
      end
    end.string
  end
end
