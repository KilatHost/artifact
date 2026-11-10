module ApplicationHelper
  # Line icons from the Kilat set (24px grid, 1.7 stroke), copied from KilatHost/web@7ba727b.
  ICONS = {
    "moon" => "M20 15a9 9 0 0 1-11-11A9 9 0 1 0 20 15",
    "sun" => "M12 8a4 4 0 1 1 0 8 4 4 0 0 1 0-8 M12 2v2 M12 20v2 M2 12h2 M20 12h2 M5 5l1 1 M18 18l1 1 M5 19l1-1 M18 6l1-1",
    "monitor" => "M3 4h18v12H3z M8 20h8 M12 16v4",
    "plus" => "M12 5v14 M5 12h14",
    "copy" => "M9 9h11v11H9z M5 15H4V4h11v1",
    "check" => "M5 12.5l4.5 4.5L19 7.5",
    "external" => "M14 4h6v6 M20 4l-9 9 M18 14v6H4V6h6",
    "arrow-left" => "M19 12H5 M11 6l-6 6 6 6",
    "trash" => "M4 7h16 M10 11v6 M14 11v6 M6 7l1 13h10l1-13 M9 7V4h6v3",
    "download" => "M12 4v11 M7 10l5 5 5-5 M5 20h14",
    "globe" => "M12 2a10 10 0 1 0 0 20 10 10 0 0 0 0-20z M2 12h20 M12 2c3 3 4.5 6.5 4.5 10S15 19 12 22c-3-3-4.5-6.5-4.5-10S9 5 12 2z",
    "key" => "M18 9a3 3 0 1 1-6 0 3 3 0 0 1 6 0 M12.9 11.1 4 20 M7 17l2 2 M5 19l2 2",
    "alert" => "M12 9v4 M12 17h.01 M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z",
    "chevron-down" => "M6 9l6 6 6-6",
    "home" => "M3 10.5 12 3l9 7.5 M5 9v11a1 1 0 0 0 1 1h4v-6h4v6h4a1 1 0 0 0 1-1V9"
  }.freeze

  def icon(name, css: "icon")
    tag.svg(viewBox: "0 0 24 24", fill: "none", stroke: "currentColor", "stroke-width": 1.7, "stroke-linecap": "round", "stroke-linejoin": "round", class: css, "aria-hidden": true) do
      tag.path(d: ICONS.fetch(name))
    end
  end

  # Kilat Artifact mark: the Kilat bolt inside print crop marks (Frame, founder 2026-11-10).
  def artifact_mark
    tag.svg(viewBox: "0 0 100 100", "aria-hidden": true) do
      tag.path(fill: "currentColor", d: "M57.5 14L31 55H49L42.5 86L69 45H51Z") +
        tag.path(fill: "none", stroke: "currentColor", "stroke-width": 8, "stroke-linecap": "round", "stroke-linejoin": "round", d: "M10 31V10H31M69 10H90V31M90 69V90H69M31 90H10V69")
    end
  end

  def brand
    link_to root_path, class: "brand" do
      tag.span(artifact_mark, class: "brand-tile") + tag.span(safe_join([ "Kilat ", tag.span("Artifact") ]), class: "brand-name")
    end
  end

  def theme_toggle
    tag.button(type: "button", class: "icon-button", data: { theme_toggle: true }, aria: { label: "Appearance" }) do
      safe_join(%w[sun moon monitor].map { |name| tag.span(icon(name), class: "theme-#{name}") })
    end
  end

  def kind_label(kind)
    { "document" => "Document", "html" => "HTML", "file" => "File" }.fetch(kind, kind)
  end

  def artifact_export_formats(version)
    version.kind == "file" ? %w[file pdf html zip source] : %w[pdf html zip source]
  end

  def export_label(format)
    { "file" => "Original", "pdf" => "PDF", "html" => "HTML", "zip" => "ZIP", "source" => "Source" }.fetch(format)
  end
end
