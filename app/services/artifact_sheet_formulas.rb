require "strscan"

class ArtifactSheetFormulas
  class Invalid < StandardError; end
  ERROR = "#ERROR!".freeze
  PRECEDENCE = { "=" => 1, "<>" => 1, "<" => 1, ">" => 1, "<=" => 1, ">=" => 1, "+" => 2, "-" => 2, "*" => 3, "/" => 3 }.freeze

  def initialize(tab)
    @tab = tab
    @cache = {}
    @active = {}
  end

  def valid_syntax?(formula)
    parse(formula)
    true
  rescue StandardError, SystemStackError
    false
  end

  # Excel row 1 contains column titles; rows[0] is row 2.
  def cell(row, column)
    key = [ row, column ]
    return @cache[key] if @cache.key?(key)
    raise Invalid if @active[key] || @active.size > 100
    raise Invalid unless row.between?(0, @tab.fetch("rows").length) && column.between?(0, @tab.fetch("columns").length - 1)
    @active[key] = true
    value = row.zero? ? @tab["columns"][column]["title"] : @tab["rows"][row - 1][column]
    result = value.is_a?(Hash) ? evaluate(parse(value.fetch("f"))) : value
    raise Invalid if result.is_a?(Array) || (result.is_a?(Numeric) && !result.finite?)
    @cache[key] = result
  rescue StandardError, SystemStackError
    @cache[key] = ERROR
  ensure
    @active.delete(key)
  end

  private

  def parse(formula)
    scanner = StringScanner.new(formula.delete_prefix("="))
    tokens = []
    until scanner.eos?
      next if scanner.scan(/\s+/)
      token = scanner.scan(/"(?:[^"]|"")*"|(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?|[A-Za-z_][A-Za-z_0-9]*|<=|>=|<>|[+*\/=<>():,-]/)
      raise Invalid unless token
      tokens << token
    end
    node = expression(tokens)
    raise Invalid unless tokens.empty?
    node
  end

  def expression(tokens, minimum = 0)
    token = tokens.shift || raise(Invalid)
    left = case token
    when "+", "-" then [ :unary, token, expression(tokens, 4) ]
    when "("
      node = expression(tokens)
      raise Invalid unless tokens.shift == ")"
      node
    when /\A"/ then [ :literal, token[1...-1].gsub('""', '"') ]
    when /\A(?:\d|\.)/ then [ :literal, Float(token) ]
    else
      if tokens.first == "("
        raise Invalid unless ArtifactTypes::FORMULAS.include?(token.upcase)
        tokens.shift
        args = []
        unless tokens.first == ")"
          loop do
            args << expression(tokens)
            break unless tokens.first == ","
            tokens.shift
          end
        end
        raise Invalid unless tokens.shift == ")"
        [ :call, token.upcase, args ]
      elsif %w[TRUE FALSE].include?(token.upcase)
        [ :literal, token.upcase == "TRUE" ]
      elsif token.match?(/\A[A-Za-z]+[1-9]\d*\z/)
        if tokens.first == ":"
          tokens.shift
          [ :range, token, tokens.shift ]
        else
          [ :ref, token ]
        end
      else
        raise Invalid
      end
    end
    while (precedence = PRECEDENCE[tokens.first]) && precedence >= minimum
      operator = tokens.shift
      left = [ :binary, operator, left, expression(tokens, precedence + 1) ]
    end
    left
  end

  def coordinates(ref)
    match = /\A([A-Z]+)([1-9]\d*)\z/.match(ref.to_s.upcase) || raise(Invalid)
    [ match[2].to_i - 1, match[1].chars.reduce(0) { |n, c| n * 26 + c.ord - 64 } - 1 ]
  end

  def reference(ref)
    value = cell(*coordinates(ref))
    raise Invalid if value == ERROR
    value
  end

  def evaluate(node)
    type, a, b, c = node
    case type
    when :literal then a
    when :ref then reference(a)
    when :range
      r1, c1 = coordinates(a)
      r2, c2 = coordinates(b)
      raise Invalid unless r2 >= r1 && c2 >= c1 && r2 <= @tab["rows"].length && c2 < @tab["columns"].length
      (r1..r2).map { |r| (c1..c2).map { |col| value = cell(r, col); raise Invalid if value == ERROR; value } }
    when :unary then a == "-" ? -number(evaluate(b)) : number(evaluate(b))
    when :binary then binary(a, evaluate(b), evaluate(c))
    when :call then function(a, b)
    end
  end

  def number(value)
    return 0.0 if value.nil?
    raise Invalid unless value.is_a?(Numeric) && value.finite?
    value.to_f
  end

  def binary(operator, left, right)
    if %w[= <> < > <= >=].include?(operator)
      left = right.is_a?(String) ? "" : 0 if left.nil?
      right = left.is_a?(String) ? "" : 0 if right.nil?
    end
    case operator
    when "+" then number(left) + number(right)
    when "-" then number(left) - number(right)
    when "*" then number(left) * number(right)
    when "/"
      raise Invalid if number(right).zero?
      number(left) / number(right)
    when "=" then left == right
    when "<>" then left != right
    when "<" then left < right
    when ">" then left > right
    when "<=" then left <= right
    when ">=" then left >= right
    end
  end

  def function(name, nodes)
    if name == "IF"
      raise Invalid unless nodes.length.between?(2, 3)
      condition = evaluate(nodes[0])
      chosen = condition && condition != 0 ? nodes[1] : nodes[2]
      return chosen ? evaluate(chosen) : false
    end
    args = nodes.map { |node| evaluate(node) }
    values = args.flatten.select { |v| v.is_a?(Numeric) }
    case name
    when "SUM" then values.sum
    when "AVERAGE" then raise(Invalid) if values.empty?; values.sum.to_f / values.length
    when "MIN" then values.min || 0
    when "MAX" then values.max || 0
    when "COUNT" then values.length
    when "ROUND"
      raise Invalid unless args.length == 2 && number(args[1]).abs <= 100
      number(args[0]).round(number(args[1]).to_i)
    when "VLOOKUP"
      raise Invalid unless args.length.between?(3, 4) && args[1].is_a?(Array)
      column = number(args[2]).to_i
      raise Invalid unless column >= 1 && args[1].all? { |row| row.is_a?(Array) && column <= row.length }
      row = if args[3] == false || args[3] == 0
        args[1].find { |item| item[0] == args[0] }
      else
        args[1].select { |item| item[0] <= args[0] }.last
      end
      raise Invalid unless row
      row[column - 1]
    end
  end
end
