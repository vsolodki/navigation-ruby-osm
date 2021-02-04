require 'ruby-graphviz'
require_relative 'visual_edge'
require_relative 'visual_vertex'

# Visual graph storing representation of graph for plotting.
class VisualGraph
  # Instances of +VisualVertex+ classes
  attr_reader :visual_vertices
  # Instances of +VisualEdge+ classes
  attr_reader :visual_edges
  # Corresponding +Graph+ Class
  attr_reader :graph
  # Scale for printing to output needed for GraphViz
  attr_reader :scale

  # Create instance of +self+ by simple storing of all given parameters.
  def initialize(graph, visual_vertices, visual_edges, bounds)
    @graph = graph
    @visual_vertices = visual_vertices
    @visual_edges = visual_edges
    @showed_vertices = []
    @bounds = bounds
    @scale = ([bounds[:maxlon].to_f - bounds[:minlon].to_f, bounds[:maxlat].to_f - bounds[:minlat].to_f].min).abs / 10.0
  end


  # Export +self+ into Graphviz file given by +export_filename+.
  def export_graphviz(export_filename)
    # create GraphViz object from ruby-graphviz package
    graph_viz_output = GraphViz.new(:G,
                                    use: :neato,
                                    truecolor: true,
                                    inputscale: @scale,
                                    margin: 0,
                                    bb: "#{@bounds[:minlon]},#{@bounds[:minlat]},
                                  		    #{@bounds[:maxlon]},#{@bounds[:maxlat]}",
                                    outputorder: :nodesfirst)

    # append all vertices
    @visual_vertices.each { |k, v|
      node = graph_viz_output.add_nodes(v.id, :shape => 'point',
                                        :comment => "#{v.lat},#{v.lon}!",
                                        :pos => "#{v.y},#{v.x}!")
      if @showed_vertices.include? node.id
        node.set { |node|
          node.color = 'red'
          node.height = 0.4
        }
      end
    }

    @visual_edges.each do |edge|
      direction_constr(edge, graph_viz_output)
    end

    # export to a given format
    format_sym = export_filename.slice(export_filename.rindex('.') + 1, export_filename.size).to_sym
    graph_viz_output.output(format_sym => export_filename)
  end

  def find_distance(node1, node2)
    start = @visual_vertices[node1]
    finish = @visual_vertices[node2]
    deg = Math::PI / 180
    radius = 6371 * 1000
    lat1 = start.lat.to_f * deg
    lat2 = finish.lat.to_f * deg
    rad1 = (finish.lat.to_f - start.lat.to_f) * deg
    rad2 = (finish.lon.to_f - start.lon.to_f) * deg
    a = Math.sin(rad1 / 2) ** 2 + Math.cos(lat1) * Math.cos(lat2) * Math.sin(rad2 / 2) ** 2
    c = 2 * Math::atan2(Math::sqrt(a), Math::sqrt(1 - a))
    radius * c
  end

  def neighbour_vertex(lat, lon)
    @neighbour = nil
    q = Float::INFINITY
    @visual_vertices.each do |_, v|
      if distance(lat.to_f, lon.to_f, v.lat.to_f, v.lon.to_f) < q
        q = distance(lat.to_f, lon.to_f, v.lat.to_f, v.lon.to_f)
        @neighbour = v.id
      end
    end
    @neighbour
  end

  def max_dist_vertex
    vertices = {}
    @visual_vertices.each do |k, v|
      vertices[k] = {:id => nil, :max => 0}
      @visual_vertices.each do |k1, v1|
        if find_distance(v1.id, v.id) > vertices[k][:max]
          vertices[k] = {:id => k1, :max => find_distance(v1.id, v.id)}
        end
      end
    end
    vertices
  end

  def show_nodes
    @visual_vertices.each { |_, v|
      puts "Vertex #{v.id} : lat #{v.lat}, lon #{v.lon}"
    }
  end

  def graph_direction(boolean)
    @graph_direction = boolean
  end

  def distance(lat1, lon1, lat2, lon2)
    Math.sqrt((lat1.to_f - lat2.to_f) ** 2 + (lon1.to_f - lon2.to_f) ** 2)
  end

  def vertices_neighbours(direction)
    nodes = {}
    @visual_vertices.each do |k, _|
      nodes[k] = []
    end
    !direction ?
        @visual_edges.each do |edge|
          nodes[edge.v1.id] << {:id => edge.v2.id}
          nodes[edge.v2.id] << {:id => edge.v1.id}
        end :
        @visual_edges.each do |edge|
          if edge.edge.one_way
            nodes[edge.v1.id] << {:id => edge.v2.id}
          else
            nodes[edge.v1.id] << {:id => edge.v2.id}
            nodes[edge.v2.id] << {:id => edge.v1.id}
          end
        end
    nodes
  end

  def find_central_vertex
    nodes = {}
    nodes_dist = max_dist_vertex
    @showed_vertices = nodes_dist.min_by do |_, v|
      v[:max]
    end
    nodes
  end

  def find_min_approx_cost
    min_approx_cost = @array1[0]
    (1...@array1.size).each do |i|
      unless !(@approximate_cost.key?(min_approx_cost) && @approximate_cost.key?([@array1[i]]))
        min_approx_cost = @array1[i] if @approximate_cost[min_approx_cost] > @approximate_cost[@array1[i]]
      end
    end
    min_approx_cost
  end

  def show_path(path)
    edges = []
    @visual_edges_alt = []
    (path.length - 1).times do |i|
      edges << [path[i], path[i + 1]]
    end
    edges.each do |z|
      @visual_edges.each do |edge|
        if z[0] == edge.v1.id && z[1] == edge.v2.id
          @visual_edges_alt << edge
        elsif z[0] == edge.v2.id && z[1] == edge.v1.id
          @visual_edges_alt << edge
        end
      end
    end
    @visual_edges_alt
  end

  def new_path(vertex)
    if @nodes_before[vertex.id]
      new_path(@nodes_before[vertex.id]) + [vertex.id]
    else
      []
    end
  end

  def export_graph(boolean)
    @export_graph = boolean
  end

  def find_shortest_path(node1, node2, direction)
    @start = @visual_vertices[node1]
    @finish = @visual_vertices[node2]
    @array1 = [@start]
    @array2 = []

    estimated_cost = {}
    exact_cost = {}
    @approximate_cost = {}
    @nodes_before = {}
    exact_cost[@start] = 0
    estimated_cost[@start] = find_distance(node1, node2)

    until @array1.size <= 0
      vertex = find_min_approx_cost
      @array1 -= [vertex]
      @array2 += [vertex]
      unless vertex != @finish
        puts "Length of the shortest path between #{vertex.id} and #{vertex.id}: #{shortest_path_length(new_path(vertex)).truncate(1)} metres"
        return new_path(vertex).unshift(@start.id)
      end

      vertices_neighbours(direction)[vertex.id].each do |vertex_id|
        vertex_id = @visual_vertices[vertex_id[:id]]
        if @array2.include?(vertex_id)
          next
        end

        result = exact_cost[vertex] + find_distance(vertex.id, vertex_id.id)

        if !@array1.include?(vertex_id)
          @array1 += [vertex_id]
          better = true
        elsif result < exact_cost[vertex_id]
          better = true
        else
          better = false
        end

        unless !better
          @nodes_before[vertex_id.id] = vertex
          exact_cost[vertex_id] = result
          estimated_cost[vertex_id] = find_distance(vertex_id.id, node2)
        end
      end
    end
    []
  end

  def find_least_time(id_start, id_end, direction)
    @start = @visual_vertices[id_start]
    @finish = @visual_vertices[id_end]
    hash_of_nearest = vertices_neighbours(direction)
    @array1 = [@start]
    @array2 = []

    estimated_cost = {}
    estimated_cost[@start] = find_distance(id_start, id_end) / 50
    exact_cost = {}
    @approximate_cost = {}
    @nodes_before = {}
    exact_cost[@start] = 0

    until @array1.size <= 0
      vertex = find_min_approx_cost
      unless vertex != @finish
        puts "Approximate time for the shortest path between #{vertex.id} and #{vertex.id}: #{(find_time_value(new_path(vertex))*60).truncate(2)} minutes"
        return new_path(vertex).unshift(@start.id)
      end

      @array1 -= [vertex]
      @array2 += [vertex]
      hash_of_nearest[vertex.id].each do |near_vert|

        near_vert = @visual_vertices[near_vert[:id]]

        next if @array2.include?(near_vert)
        speed = @visual_edges.select do |k|
          (k.v1.id == vertex.id && k.v2.id == near_vert.id) || (k.v1.id == near_vert.id && k.v2.id == vertex.id)
        end.first.edge.max_speed
        result = exact_cost[vertex] + (find_distance(vertex.id, near_vert.id) / speed.to_f)
        if !@array1.include?(near_vert)
          @array1 += [near_vert]
          better = true
        elsif result < exact_cost[near_vert]
          better = true
        else
          better = false
        end
        unless !better
          @nodes_before[near_vert.id] = vertex
          exact_cost[near_vert] = result
          edge_speed_imp = @visual_edges.select do |k|
            (k.v1.id == vertex.id && k.v2.id == near_vert.id) || (k.v1.id == near_vert.id && k.v2.id == vertex.id)
          end.first.edge.max_speed
          estimated_cost[near_vert] = find_distance(near_vert.id, id_end) / edge_speed_imp.to_f
        end
      end
    end
    []
  end

  def direction_constr(edge, graph_viz_output)
    @graph_direction ?
        if edge.edge.one_way
          if @export_graph
            const_edges = graph_viz_output.add_edges(edge.v1.id, edge.v2.id, 'arrowhead' => 'vee')
          else
            const_edges = graph_viz_output.add_edges(edge.v1.id, edge.v2.id, 'arrowhead' => 'vee')
          end
        else
            const_edges = graph_viz_output.add_edges(edge.v1.id, edge.v2.id, 'arrowhead' => 'none')
        end :
        if @export_graph
          const_edges = graph_viz_output.add_edges(edge.v1.id, edge.v2.id, 'arrowhead' => 'none')
        else
          const_edges = graph_viz_output.add_edges(edge.v1.id, edge.v2.id, 'arrowhead' => 'none')
        end
    unless @visual_edges_alt == nil
      if @visual_edges_alt.include? edge
        const_edges.set { |edge|
          edge.color = 'red'
          edge.penwidth = 2
        }
      end
    end
  end

  def shortest_path_length(path)
    length = 0
    path.each_with_index do |p, q|
      unless q == (path.length - 1)
        start_node = @visual_vertices[p]
        end_node = @visual_vertices[path[q + 1]]
        length += find_distance(start_node.id, end_node.id)
      end
    end
    length
  end

  def find_time_value(path)
    time = 0
    path.each_with_index do |p, q|
      unless q == (path.length - 1)
        start = @visual_vertices[p]
        finish = @visual_vertices[path[q + 1]]
        edge = @visual_edges.select do |g|
          g.v1.id == start.id && g.v2.id == finish.id || (g.v2.id == start.id && g.v1.id == finish.id)
        end.first.edge
        time += (find_distance(start.id, finish.id) / 1000) / edge.max_speed.to_f
      end
    end
    time
  end

  def create_array_vertices(node)
    node.each do |i|
      unless @visual_vertices.any? { |k, _| k == i }
        puts "Node with id #{i} does not exist"
      end
      @showed_vertices << i
    end
  end
end
