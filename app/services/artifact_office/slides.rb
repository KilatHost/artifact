module ArtifactOffice
  class Slides < Package
    P = "http://schemas.openxmlformats.org/presentationml/2006/main".freeze
    A = "http://schemas.openxmlformats.org/drawingml/2006/main".freeze
    WIDTH = 12_192_000
    HEIGHT = 6_858_000

    def generate
      ids = @source["slides"].each_with_index.map do |slide, i|
        slide_part(slide, i + 1)
        %(<p:sldId id="#{256 + i}" r:id="slide#{i + 1}"/>)
      end.join
      part("ppt/presentation.xml", %(<p:presentation #{namespaces}><p:sldMasterIdLst><p:sldMasterId id="2147483648" r:id="master"/></p:sldMasterIdLst><p:sldIdLst>#{ids}</p:sldIdLst><p:sldSz cx="#{WIDTH}" cy="#{HEIGHT}" type="screen16x9"/><p:notesSz cx="6858000" cy="9144000"/></p:presentation>), "application/vnd.openxmlformats-officedocument.presentationml.presentation.main+xml")
      entries = @source["slides"].each_index.map { |i| [ "slide#{i + 1}", "slide", "slides/slide#{i + 1}.xml" ] }
      relationships("ppt/_rels/presentation.xml.rels", entries + [ [ "master", "slideMaster", "slideMasters/slideMaster1.xml" ] ])
      master_parts
      package("ppt/presentation.xml")
    end

    private

    def namespaces
      %(xmlns:p="#{P}" xmlns:a="#{A}" xmlns:r="#{REL}")
    end

    def group
      '<p:nvGrpSpPr><p:cNvPr id="1" name=""/><p:cNvGrpSpPr/><p:nvPr/></p:nvGrpSpPr><p:grpSpPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="0" cy="0"/><a:chOff x="0" y="0"/><a:chExt cx="0" cy="0"/></a:xfrm></p:grpSpPr>'
    end

    def master_parts
      map = '<p:clrMap accent1="accent1" accent2="accent2" accent3="accent3" accent4="accent4" accent5="accent5" accent6="accent6" bg1="lt1" bg2="lt2" folHlink="folHlink" hlink="hlink" tx1="dk1" tx2="dk2"/>'
      part("ppt/slideMasters/slideMaster1.xml", %(<p:sldMaster #{namespaces}><p:cSld><p:spTree>#{group}</p:spTree></p:cSld>#{map}<p:sldLayoutIdLst><p:sldLayoutId id="2147483649" r:id="layout"/></p:sldLayoutIdLst><p:txStyles><p:titleStyle/><p:bodyStyle/><p:otherStyle/></p:txStyles></p:sldMaster>), "application/vnd.openxmlformats-officedocument.presentationml.slideMaster+xml")
      relationships("ppt/slideMasters/_rels/slideMaster1.xml.rels", [ [ "layout", "slideLayout", "../slideLayouts/slideLayout1.xml" ], [ "theme", "theme", "../theme/theme1.xml" ] ])
      part("ppt/slideLayouts/slideLayout1.xml", %(<p:sldLayout #{namespaces} type="blank" preserve="1"><p:cSld name="Blank"><p:spTree>#{group}</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sldLayout>), "application/vnd.openxmlformats-officedocument.presentationml.slideLayout+xml")
      relationships("ppt/slideLayouts/_rels/slideLayout1.xml.rels", [ [ "master", "slideMaster", "../slideMasters/slideMaster1.xml" ] ])
      theme
    end

    def theme
      colors = { "dk1" => color("foreground"), "lt1" => color("background"), "dk2" => "333333", "lt2" => "EEEEEE", "accent1" => color("accent"), "accent2" => "4472C4", "accent3" => "70AD47", "accent4" => "FFC000", "accent5" => "5B9BD5", "accent6" => "A5A5A5", "hlink" => "0563C1", "folHlink" => "954F72" }
      color_scheme = colors.map { |name, value| "<a:#{name}><a:srgbClr val=\"#{value}\"/></a:#{name}>" }.join
      fonts = %w[major minor].map { |name| %(<a:#{name}Font><a:latin typeface="#{font}"/><a:ea typeface=""/><a:cs typeface=""/></a:#{name}Font>) }.join
      fill = '<a:solidFill><a:schemeClr val="phClr"/></a:solidFill>'
      line = %(<a:ln w="9525">#{fill}<a:prstDash val="solid"/></a:ln>)
      part("ppt/theme/theme1.xml", %(<a:theme xmlns:a="#{A}" name="Artifact"><a:themeElements><a:clrScheme name="Artifact">#{color_scheme}</a:clrScheme><a:fontScheme name="Artifact">#{fonts}</a:fontScheme><a:fmtScheme name="Artifact"><a:fillStyleLst>#{fill * 3}</a:fillStyleLst><a:lnStyleLst>#{line * 3}</a:lnStyleLst><a:effectStyleLst>#{'<a:effectStyle><a:effectLst/></a:effectStyle>' * 3}</a:effectStyleLst><a:bgFillStyleLst>#{fill * 3}</a:bgFillStyleLst></a:fmtScheme></a:themeElements></a:theme>), "application/vnd.openxmlformats-officedocument.theme+xml")
    end

    def text_shape(lines, x:, y:, width:, height:, size: 2600, accent: false, bullets: false)
      id = (@shape_id += 1)
      paragraphs = lines.map do |line|
        %(<a:p><a:pPr>#{bullets ? '<a:buChar char="•"/>' : '<a:buNone/>'}</a:pPr><a:r><a:rPr lang="en-US" sz="#{size}"><a:solidFill><a:srgbClr val="#{color(accent ? 'accent' : 'foreground')}"/></a:solidFill><a:latin typeface="#{font}"/></a:rPr><a:t>#{xml(line)}</a:t></a:r><a:endParaRPr lang="en-US"/></a:p>)
      end.join
      %(<p:sp><p:nvSpPr><p:cNvPr id="#{id}" name="Text #{id}"/><p:cNvSpPr txBox="1"/><p:nvPr/></p:nvSpPr><p:spPr><a:xfrm><a:off x="#{x}" y="#{y}"/><a:ext cx="#{width}" cy="#{height}"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:noFill/></p:spPr><p:txBody><a:bodyPr wrap="square"><a:normAutofit/></a:bodyPr><a:lstStyle/>#{paragraphs.presence || '<a:p/>'}</p:txBody></p:sp>)
    end

    def slide_part(slide, index)
      @shape_id = 1
      content = slide["title"] ? text_shape([ slide["title"] ], x: 600_000, y: 400_000, width: 11_000_000, height: 1_100_000, size: 3600, accent: true) : ""
      content += case slide["layout"]
      when "title", "closing"
        text_shape([ slide["subtitle"] || slide["text"] || "" ], x: 600_000, y: 2_300_000, width: 11_000_000, height: 3_500_000)
      when "bullets"
        text_shape(slide["bullets"], x: 800_000, y: 1_700_000, width: 10_600_000, height: 4_500_000, bullets: true)
      when "big-number"
        text_shape([ slide["number"] ], x: 600_000, y: 1_500_000, width: 11_000_000, height: 2_000_000, size: 8800, accent: true) +
          text_shape([ slide["caption"] || "" ], x: 600_000, y: 3_800_000, width: 11_000_000, height: 2_000_000)
      when "two-column"
        text_shape(slide["left"], x: 600_000, y: 1_700_000, width: 5_200_000, height: 4_500_000, bullets: true) +
          text_shape(slide["right"], x: 6_400_000, y: 1_700_000, width: 5_200_000, height: 4_500_000, bullets: true)
      when "table" then table(slide)
      end
      part("ppt/slides/slide#{index}.xml", %(<p:sld #{namespaces}><p:cSld><p:bg><p:bgPr><a:solidFill><a:srgbClr val="#{color('background')}"/></a:solidFill><a:effectLst/></p:bgPr></p:bg><p:spTree>#{group}#{content}</p:spTree></p:cSld><p:clrMapOvr><a:masterClrMapping/></p:clrMapOvr></p:sld>), "application/vnd.openxmlformats-officedocument.presentationml.slide+xml")
      relationships("ppt/slides/_rels/slide#{index}.xml.rels", [ [ "layout", "slideLayout", "../slideLayouts/slideLayout1.xml" ] ])
    end

    def table(slide)
      id = (@shape_id += 1)
      width = slide["head"].length
      rows = [ slide["head"] ] + slide["rows"]
      height = [ 4_500_000 / rows.length, 600_000 ].min
      grid = Array.new(width, %(<a:gridCol w="#{11_000_000 / width}"/>)).join
      body = rows.map do |row|
        cells = width.times.map { |c| %(<a:tc><a:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:rPr sz="1800"/><a:t>#{xml(row[c])}</a:t></a:r></a:p></a:txBody><a:tcPr/></a:tc>) }.join
        %(<a:tr h="#{height}">#{cells}</a:tr>)
      end.join
      %(<p:graphicFrame><p:nvGraphicFramePr><p:cNvPr id="#{id}" name="Table"/><p:cNvGraphicFramePr/><p:nvPr/></p:nvGraphicFramePr><p:xfrm><a:off x="600000" y="1700000"/><a:ext cx="11000000" cy="#{height * rows.length}"/></p:xfrm><a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/table"><a:tbl><a:tblPr firstRow="1" bandRow="1"/><a:tblGrid>#{grid}</a:tblGrid>#{body}</a:tbl></a:graphicData></a:graphic></p:graphicFrame>)
    end
  end
end
