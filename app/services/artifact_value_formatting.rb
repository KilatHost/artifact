module ArtifactValueFormatting
  def self.format(value, format)
    return value.to_s if value.nil?
    helper = ActiveSupport::NumberHelper
    case format
    when "int" then helper.number_to_rounded(value, precision: 0, delimiter: ".", separator: ",")
    when "idr" then "Rp #{helper.number_to_rounded(value, precision: 0, delimiter: '.', separator: ',')}"
    when "pct" then value.is_a?(Numeric) ? "#{helper.number_to_rounded(value * 100, precision: 2, strip_insignificant_zeros: true, separator: ',')}%" : value.to_s
    when "date" then (value.is_a?(Numeric) ? Date.new(1899, 12, 30) + value.to_i : Date.iso8601(value.to_s)).strftime("%d/%m/%Y")
    else value.to_s
    end
  rescue Date::Error, ArgumentError
    value.to_s
  end
end
