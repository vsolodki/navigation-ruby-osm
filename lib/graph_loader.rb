require_relative '../process_logger'
require 'nokogiri'
require 'ruby-graphviz'
require_relative 'graph'
require_relative 'visual_graph'

# Class to load graph from various formats. Actually implemented is Graphviz formats. Future is OSM format.
class GraphLoader
  attr_reader :highway_attributes

  # Create an instance, save +filename+ and preset highway attributes
  def initialize(filename, highway_attributes)
    @filename = filename
    @highway_attributes = highway_attributes
  end

  # Load graph from Graphviz file which was previously constructed from this application, i.e. contains necessary data.
  # File needs to contain 
  # => 1) For node its 'id', 'pos' (containing its re-computed position on graphviz space) and 'comment' containing string with comma separated lat and lon
  # => 2) Edge (instead of source and target nodes) might contains info about 'speed' and 'one_way'
  # => 3) Generally, graph contains parameter 'bb' containing array without bounds of map as minlon, minlat, maxlon, maxlat
  #
  # @return [+Graph+, +VisualGraph+]
  def load_graph_viz
    ProcessLogger.log("Loading graph from GraphViz file #{@filename}.")
    gv = GraphViz.parse(@filename)

    # aux data structures
    hash_of_vertices = {}
    list_of_edges = []
    hash_of_visual_vertices = {}
    list_of_visual_edges = []

    # process vertices
    gv.node_count.times { |node_index|
      node = gv.get_node_at_index(node_index)
      vid = node.id

      v = Vertex.new(vid) unless hash_of_vertices.has_key?(vid)
      hash_of_vertices[vid] = v

      geo_pos = node["comment"].to_s.delete("\"").split(",")
      pos = node["pos"].to_s.delete("\"").split(",")
      hash_of_visual_vertices[vid] = VisualVertex.new(vid, v, geo_pos[0], geo_pos[1], pos[1], pos[0])
    }

    # process edges
    gv.edge_count.times { |edge_index|
      link = gv.get_edge_at_index(edge_index)
      vid_from = link.node_one.delete("\"")
      vid_to = link.node_two.delete("\"")
      speed = 50
      one_way = false
      link.each_attribute { |k, v|
        speed = v if k == "speed"
        one_way = true if k == "oneway"
      }
      e = Edge.new(vid_from, vid_to, speed, one_way)
      list_of_edges << e
      list_of_visual_edges << VisualEdge.new(e, hash_of_visual_vertices[vid_from], hash_of_visual_vertices[vid_to])
    }

    # Create Graph instance
    g = Graph.new(hash_of_vertices, list_of_edges)

    # Create VisualGraph instance
    bounds = {}
    bounds[:minlon], bounds[:minlat], bounds[:maxlon], bounds[:maxlat] = gv["bb"].to_s.delete("\"").split(",")
    vg = VisualGraph.new(g, hash_of_visual_vertices, list_of_visual_edges, bounds)

    [g, vg]
  end

  def nodes_iter(counter, hash_of_vertices, hash_of_visual_vertices, node)
    vertex_id = node.attribute('id').to_s
    vertex = Vertex.new(vertex_id) unless hash_of_vertices.has_key?(vertex_id)
    counter += 1
    hash_of_vertices[counter] = vertex
    geo_pos_osm = [node["lat"].to_s] + [node["lon"].to_s]
    hash_of_visual_vertices[vertex_id] = VisualVertex.new(vertex_id, vertex, geo_pos_osm[0], geo_pos_osm[1], geo_pos_osm[0], geo_pos_osm[1])
  end

  # Method to load graph from OSM file and create +Graph+ and +VisualGraph+ instances from +self.filename+
  #
  # @return [+Graph+, +VisualGraph+]

  def load_graph(direction)
    ProcessLogger.log("Loading graph from OSM file #{@filename}.")
    osm = Nokogiri::XML(File.open(@filename))

    hash_of_vertices = {}
    list_of_edges = []
    hash_of_visual_vertices = {}
    list_of_visual_edges = []
    visual_edges = []
    visual_vertices = {}
    counter = 0
    edges = []
    @node_array = {}
    bounds = {}

    osm.xpath("//node").each do |node|
      nodes_iter(counter, hash_of_vertices, hash_of_visual_vertices, node)
    end

    osm.xpath("//way").each do |way|
      allowed_speed = 50
      oneway = false
      if way.xpath('tag').attribute("k").to_s == "highway" && (@highway_attributes.include? way.xpath('tag').attribute("v").to_s)
        way.xpath("*").each do |way|
          if (way.attribute("k").to_s == "oneway") && (way.attribute("v").to_s == "yes")
            oneway = true
          end
          if way.attribute("k").to_s == "maxspeed"
            allowed_speed = way.attribute("v").to_s.to_i
          end
          unless way.attribute("ref").to_s == ""
            edges << way.attribute("ref").to_s
          end
        end
        edges.each_cons(2).to_a.each do |i|
          graph_help(allowed_speed, direction, hash_of_visual_vertices, i, list_of_edges, list_of_visual_edges, oneway)
        end
        edges = []
      end
    end

    list_of_visual_edges.each do |g|
      visual_vert_iter(g, hash_of_visual_vertices, visual_edges, visual_vertices)
    end
    osm.xpath('//bounds').each do |u|
      constr_bounds(bounds, u)
    end

    # Create Graph instance
    g = Graph.new(visual_vertices, list_of_edges)
    # Create VisualGraph instance
    vg = VisualGraph.new(g, visual_vertices, visual_edges, bounds)

    [g, vg]
  end


  def visual_vert_iter(g, hash_of_visual_vertices, visual_edges, visual_vertices)
    hash_of_visual_vertices.each do |k, v|
      if k == g.v1.id || k == g.v2.id
        unless visual_edges.include?(g)
          visual_edges << g
        end
        unless visual_vertices.has_key?(k)
          visual_vertices[k] = v
        end
      end
    end
  end

  def constr_bounds(bounds, u)
    bounds[:minlat] = u.attribute("minlat").to_s
    bounds[:minlon] = u.attribute("minlon").to_s
    bounds[:maxlat] = u.attribute("maxlat").to_s
    bounds[:maxlon] = u.attribute("maxlon").to_s
  end

  def graph_help(allowed_speed, direction, hash_of_visual_vertices, i, list_of_edges, list_of_visual_edges, oneway)
    edge = Edge.new(i[0], i[1], allowed_speed, oneway)
    list_of_edges << edge
    list_of_visual_edges << VisualEdge.new(edge, hash_of_visual_vertices[i[0]], hash_of_visual_vertices[i[1]])

    if direction
      if edge.one_way == true
        unless @node_array.has_key? i[0]
          @node_array[i[0]] = []
        end
        @node_array[i[0]] << i[1]
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



