# Keep the current chart so we can manip it later
#myChart = null

TABLEAU_NULL = '%null%'

# Quick accessors for accessing the tableau bits on the parent page
getTableau = ()-> parent.parent.tableau
getCurrentViz = ()-> getTableau().VizManager.getVizs()[0]
# Returns the current worksheet.
# The path to access the sheet is hardcoded for now.
getCurrentWorksheet = ()-> getCurrentViz().getWorkbook().getActiveSheet().getWorksheets()[0]

# Because handlers in promises swallow errors and
# the error callbacks for Promises/A are flaky,
# we simply use this function to wrap calls
errorWrapped = (context, fn)->
  (args...)->
    try
      fn(args...)
    catch err
      console.error "Got error during '", context, "' : ", err.message, err.stack


# Takes a table and returns a "COLUMN_NAME" => COLUMN_IDX map
getColumnIndexes = (table, required_keys)->
  # Create a column name -> idx map
  colIdxMaps = {}
  for c in table.getColumns()
    fn = c.getFieldName()
    if fn in required_keys
      colIdxMaps[fn] = c.getIndex()
  colIdxMaps

# Takes a Tableau Row and a "COL_NAME" => COL_IDX map and returns
# a new object with the COL_NAME fields set to the corresponding values
convertRowToObject = (row, attrs_map)->
  o = {}
  for name, id of attrs_map
    o[name] = row[id].value
  o





# TABLEAU HOOKS
# ============

CANVAS_SELECTOR = '#sankey-canvas'



makeSanKeyData = (rowsIn)->

  trf = (row)->
    pn = row["Pivot Field Names"]
    pv = row["Pivot Field Values"]


    return _.extend {}, row, switch pn
      when "buyer" then {sellercod: "From: #{row.sellercod}", role: "buyer"}
      when "seller" then {buyercod: "To: #{row.buyercod}", role: "seller"}


  rows = _.map rowsIn, trf

  all_names = _.pluck(rows, "sellercod").concat( _.pluck(rows, "buyercod"))

  i = 0
  cache = {}
  for name in all_names
    unless cache.hasOwnProperty(name)
      cache[name] = i
      i++


  names = ({name: "#{name}", idx: idx}  for name, idx of cache)
  o = []
  for row, idx in rows
    value = parseFloat(row.nrdel)
    value = 0.0 if isNaN(value)
    o.push _.extend {source: cache[row.sellercod], target: cache[row.buyercod], value: value}, row

  { nodes: names, links: o }











# =========================================================================

# Draws the nodes into the SVG
drawNodes = (svg, sankey, width, nodes)->
  formatNumber = d3.format(",.0f")
  format = (d)-> formatNumber(d) + " t"
  color = d3.scaleOrdinal(d3.schemeCategory20)

  node = svg.append("g").selectAll(".node")
      .data(nodes)
      #.data([])
      .enter().append("g")
      .attr("class", "node")
      .attr("transform", (d)-> "translate(#{d.x},#{d.y})" )

  node.append("rect")
      .attr("height", (d)-> Math.max(10, d.dy))
      .attr("width", sankey.nodeWidth())
      .style("fill", (d)->  d.color = color(d.name.replace(/ .*/, "")))
      .style("stroke", (d)->  d3.rgb(d.color).darker(2))
      .append("title")
        .text((d)-> d.name + "\n" + format(d.value))

  node.append("text")
      .attr("x", -6)
      .attr("y", (d)->  d.dy / 2)
      .attr("dy", ".35em")
      .attr("text-anchor", "end")
      .attr("transform", null)
      .text((d)->  d.name)
    .filter((d)->  d.x < width / 2)
      .attr("x", 6 + sankey.nodeWidth())
      .attr("text-anchor", "start")

  node.exit().remove()
  node


# The links
drawLinks = (svg, sankey, path, links)->
  formatNumber = d3.format(",.0f")
  format = (d)-> formatNumber(d) + " t"

  link = svg.append("g").selectAll(".link")
      .data(links)
      .enter().append("path")
      .attr("class", "link")
      .attr("d", path)
      .style("stroke-width", (d)->  Math.max(1, d.dy) )
      .sort((a, b)-> b.dy - a.dy );
  link.exit().remove()

  linkTitle = link.append("title")
      .text((d)->  "#{d.source.name} → #{ d.target.name}\n#{d.desc}\n#{d.desig2}\n#{d.delyears}: #{format(d.value)}" );

  linkTitle.exit().remove()
  link


# Helper that combines drawing the nodes & links + adding handlers to them
drawNodesAndLinks = (svg, sankey, width, data)->
  path = sankey.link()
  link = drawLinks(svg, sankey, path, data.links)
  node = drawNodes(svg, sankey, width, data.nodes)





drawSanKeyGraph = (data)->
  # THe canvas we'll use
  svg = d3.select("#sankey-canvas")
  svg.selectAll("*").remove()

  # Dont freeze the machine
  if data.links.length > 2500 or data.nodes.length > 512
    # Hide the scroll bars by making the svg box smaller
    svg.node().setAttribute("height", "100px")
    console.error "TOO MUCH DATA: max 2500 links, 512 nodes"
    return

  # Some helper functions
  margin = {top: 1, right: 1, bottom: 0, left: 1}
  width = 870 # - margin.left - margin.right
  height = 830 #- margin.top - margin.bottom



  svg
    .attr("width", width - margin.left - margin.right)
    .attr("height", height - margin.top - margin.bottom )
    .append("g")
    .attr("transform", "translate(" + margin.left + "," + margin.top + ")")


  # The actual graph that does the layouting
  sankey = d3.sankey()
    .nodeWidth(15)
    .nodePadding(10)
    .size([width, height])

  sankey
    .nodes(data.nodes)
    .links(data.links)
    .layout(1)


  drawNodesAndLinks(svg, sankey, width, data)

  s = svg.node()
  bbox = s.getBBox()

  s.setAttribute("viewBox", (bbox.x-5)+" "+(bbox.y-5)+" "+(bbox.width+10)+" "+(bbox.height+10));
  s.setAttribute("width", (bbox.width+10)  + "px");
  s.setAttribute("height",(bbox.height+10) + "px");



#
# =========================================================================

initEditor = ->

  # Get the tableau bits from the parent.
  tableau = getTableau()

  # Error handler in case getting the data fails in the Promise
  onDataLoadError = (err)->
    console.err("Error during Tableau Async request:", err)

  # Handler for loading and converting the tableau data to chart data
  onDataLoadOk = errorWrapped "Getting data from Tableau", (table)->
      # Decompose the ids
      col_indexes = getColumnIndexes(table, ["buyercod", "sellercod", "nrdel", "desc", "desig2", "delyears", "Pivot Field Names", "Pivot Field Values"])

      data = (convertRowToObject(row, col_indexes) for row in table.getData())
      sanKeyData = makeSanKeyData(data)

      errorWrapped("Drawing SanKey diagram", drawSanKeyGraph)(sanKeyData)

  # Handler that gets the selected data from tableau and sends it to the chart
  # display function
  updateEditor = ()->
    getCurrentWorksheet()
      .getUnderlyingDataAsync({maxRows: 0, ignoreSelection: false, includeAllColumns: true, ignoreAliases: true})
      .then(onDataLoadOk, onDataLoadError )

  ## Add an event listener for marks change events that simply loads the
  ## selected data to the chart
  getCurrentViz().addEventListener( tableau.TableauEventName.MARKS_SELECTION,  updateEditor)




@appApi = {
  initEditor
}
