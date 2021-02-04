class ComponentFinder

  def initialize(filename, highway_attributes)
    @filename = filename
    @highway_attributes = highway_attributes
  end

  def find_component(v, visited, nearest)
    visited[v] = true
    array_comp = []
    array_comp << v
    nearest[v].each do |node|
      array_comp.concat(find_component(node, visited, nearest)) unless visited[node]
    end
    array_comp
  end

  def load_graph_comp(direction)
    ProcessLogger.log("Loading graph from OSM file #{@filename}.")
    osm = Nokogiri::XML(File.open(@filename))

    hash_of_vertices = {}
    list_of_edges = []
    hash_of_visual_vertices = {}
    list_of_visual_edges = []

    counter = 0
    edges = []
    @oneway = false
    @allowed_speed = 50
    @node_array = {}

    components = []
    visited_vertices = {}
    count = 0
    bounds = {}

    osm.xpath("//node").each do |node|
      process_nodes(counter, hash_of_vertices, hash_of_visual_vertices, node)
    end

    osm.xpath("//way").each do |way|
      allowed_speed = 50
      oneway = false
      if way.xpath('tag').attribute("k").to_s == "highway" && (@highway_attributes.include? way.xpath('tag').attribute("v").to_s)
        way.xpath("*").each do |way|
          if way.attribute("k").to_s == "maxspeed"
            allowed_speed = way.attribute("v").to_s.to_i
          end
          unless way.attribute("ref").to_s == ""
            edges << way.attribute("ref").to_s
          end
          if way.attribute("k").to_s == "oneway" && way.attribute("v").to_s == "yes"
            oneway = true
          end
        end
        edges.each_cons(2).to_a.each do |i|
          comp_help(allowed_speed, direction, hash_of_visual_vertices, i, list_of_edges, list_of_visual_edges, oneway)
        end
        edges = []
      end
    end

    visual_component_vertex = {}
    @node_array.each do |vertex, _|
      unless visited_vertices[vertex]
        components[count] = find_component(vertex, visited_vertices, @node_array)
        count += 1
      end
    end
    components.each do |r|
    end
    biggest_component = components.max_by { |x| x.length }

    biggest_component.each do |i|
      visual_component_vertex[i] = hash_of_visual_vertices[i]
    end

    comp_edges = []

    list_of_visual_edges.each do |edge|
      biggest_component.each do |comp|
        component_help(comp, comp_edges, edge)
      end
    end

    osm.xpath("//bounds").each do |u|
      find_bounds(bounds, u)
    end

    # Create Graph instance
    g = Graph.new(visual_component_vertex, list_of_edges)
    # Create VisualGraph instance
    vg = VisualGraph.new(g, visual_component_vertex, comp_edges, bounds)

    [g, vg]
  end

  def process_nodes(counter, hash_of_vertices, hash_of_visual_vertices, node)
    node_id = node.attribute('id').to_s
    vertex = Vertex.new(node_id) unless hash_of_vertices.has_key?(node_id)
    counter += 1
    hash_of_vertices[counter] = vertex
    lat_lon = [node["lat"].to_s] + [node["lon"].to_s]
    hash_of_visual_vertices[node_id] = VisualVertex.new(node_id, vertex, lat_lon[0], lat_lon[1], lat_lon[0], lat_lon[1])
  end

  def component_help(comp, comp_edges, edge)
    if comp == edge.v1.id || comp == edge.v2.id
      unless comp_edges.include?(edge)
        comp_edges << edge
      end
    end
  end

  def find_bounds(bounds, u)
    bounds[:minlat] = u.attribute("minlat").to_s
    bounds[:minlon] = u.attribute("minlon").to_s
    bounds[:maxlat] = u.attribute("maxlat").to_s
    bounds[:maxlon] = u.attribute("maxlon").to_s
  end

  def comp_help(allowed_speed, direction, hash_of_visual_vertices, i, list_of_edges, list_of_visual_edges, oneway)
    edge = Edge.new(i[0], i[1], allowed_speed, oneway)
    list_of_edges << edge
    list_of_visual_edges << VisualEdge.new(edge, hash_of_visual_vertices[i[0]], hash_of_visual_vertices[i[1]])

    if direction
      if edge.one_way == true
        unless @node_array.has_key? i[0]
          @node_array[i[0]] = []
        end
        unless @node_array.has_key? i[1]
          @node_array[i[1]] = []
        end
        @node_array[i[0]] << i[1]
        @node_array[i[1]] << i[0]
      else
        unless @node_array.has_key? i[0]
          @node_array[i[0]] = []
        end
        unless @node_array.has_key? i[1]
          @node_array[i[1]] = []
        end
        @node_array[i[0]] << i[1]
        @node_array[i[1]] << i[0]
      end
    else
      unless @node_array.has_key? i[0]
        @node_array[i[0]] = []
      end
      unless @node_array.has_key? i[1]
        @node_array[i[1]] = []
      end
      @node_array[i[0]] << i[1]
      @node_array[i[1]] << i[0]
    end
  end

end