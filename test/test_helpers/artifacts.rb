module ArtifactTestHelpers
  def doc_source
    { "kind" => "doc", "page" => "A4", "blocks" => [
      { "t" => "heading", "text" => "Faktur #INV-2026-011", "level" => 1 },
      { "t" => "fields", "rows" => [ [ "Dari", "Toko Sinar Jaya" ], [ "Kepada", "CV Maju Bersama" ], [ "Tanggal", "16 November 2026" ] ] },
      { "t" => "table", "head" => [ "Barang", "Qty", "Harga", "Jumlah" ], "format" => [ "text", "int", "idr", "idr" ],
        "rows" => [ [ "Beras 5 kg", 10, 75_000, 750_000 ], [ "Minyak 2 L", 5, 38_000, 190_000 ] ] },
      { "t" => "totals", "format" => "idr", "rows" => [ [ "Subtotal", 940_000 ], [ "PPN 11%", 103_400 ], [ "Total", 1_043_400 ] ] },
      { "t" => "signature", "name" => "Budi Santoso", "role" => "Pemilik", "place_date" => "Bandung, 16 November 2026" }
    ] }
  end

  def sheet_source
    { "kind" => "sheet", "tabs" => [ { "name" => "Harga", "columns" => [ { "title" => "Produk" }, { "title" => "Modal", "format" => "idr" },
      { "title" => "Margin", "format" => "pct" }, { "title" => "Harga jual", "format" => "idr" } ],
      "rows" => [ [ "Keripik Singkong 250 g", 12_000, 0.4, { "f" => "=ROUND(B2*(1+C2),-2)" } ],
        [ "Sambal Bawang 150 ml", 15_000, 0.35, { "f" => "=ROUND(B3*(1+C3),-2)" } ],
        [ "Rata-rata", nil, nil, { "f" => "=AVERAGE(D2:D3)" } ] ] } ] }
  end

  def slides_source
    { "kind" => "slides", "ratio" => "16:9", "slides" => [
      { "layout" => "title", "title" => "Promo 12.12", "subtitle" => "Toko Sinar Jaya" },
      { "layout" => "big-number", "number" => "12%", "caption" => "Diskon semua keripik" },
      { "layout" => "bullets", "title" => "Cara ikut", "bullets" => [ "Belanja minimal Rp50.000", "Tunjukkan pesan ini di kasir" ] },
      { "layout" => "closing", "title" => "Sampai jumpa 12 Desember", "text" => "Buka 08.00 sampai 21.00" }
    ] }
  end

  def typed_source(kind)
    { "doc" => doc_source, "sheet" => sheet_source, "slides" => slides_source }.fetch(kind)
  end
end
