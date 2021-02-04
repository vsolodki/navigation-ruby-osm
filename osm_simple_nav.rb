require_relative 'lib/graph_loader'
require_relative 'process_logger'
require_relative 'lib/component_finder'
# Class representing simple navigation based on OpenStreetMap project
class OSMSimpleNav
  attr_reader :point_operation, :midist_point_oper
  # Creates an instance of navigation. No input file is specified in this moment.
  def initialize
    # register
    @load_cmds_list = %w[--load --load-comp --load-dir --load-undir --load-dir-comp --load-undir-comp]
    @actions_list = %w[--export --show-nodes --midist-len --midist-time --center]

    @usage_text = <<-END.gsub(/^ {6}/, '')
	  	Usage:\truby osm_simple_nav.rb <load_command> <input.IN> <action_command> <output.OUT> 
	  	\tLoad commands: 
	  	\t\t --load <input_map.IN> ... load map from file <input_map.IN>, IN can be ['DOT']
			\t\t --load-undir <input_map.IN> ... build an undirected graph from file <input_map.IN>, IN must be ['OSM']
			\t\t --load-dir <input_map.IN> ... build a directed graph from file <input_map.IN>, IN must be ['OSM']
			\t\t --load-dir-comp <input_map.IN> ... build the largest component for a directed graph from file <input_map.IN, IN must be ['OSM']
			\t\t --load-undir-comp <input_map.IN> ... build the largest component for an undirected graph from file <input_map.IN>, IN must be ['OSM']		
	  	\tAction commands: 
	  	\t\t --export ... export graph into file <exported_map.OUT>, OUT can be ['PDF','PNG','DOT']
			\t\t --show-nodes ... list the existing nodes and export graph into file <exported_map.OUT>, OUT can be ['PDF','PNG','DOT']
			\t\t --show-nodes <id_start> <id_stop> ... list the existing nodes using start and stop ID's and export graph into file <exported_map.OUT>, OUT can be ['PDF','PNG','DOT']
			\t\t --show-nodes <lat_start> <lon_start> <lat_stop> <lon_stop> ... list the existing nodes using latitude and longitude
			\t\t and export graph into file <exported_map.OUT>, OUT can be ['PDF','PNG','DOT']
			\t\t --midist-len <id_start> <id_stop> ... find the fastest way using the way length, start ID and stop ID and export graph into file <exported_map.OUT>, OUT can be ['PDF','PNG','DOT']
			\t\t --midist-len <lat_start> <lon_start> <lat_stop> <lon_stop> ... find the fastest way using the way length, latitude and longitude
			\t\t and export graph into file <exported_map.OUT>, OUT can be ['PDF','PNG','DOT']
			\t\t --midist-time <id_start> <id_stop> ... find the fastest way using time, start ID and stop ID and export graph into file <exported_map.OUT>, OUT can be ['PDF','PNG','DOT']
			\t\t --midist-time <lat_start> <lon_start> <lat_stop> <lon_stop> ... find the fastest way using time, latitude and longitude
			\t\t and export graph into file <exported_map.OUT>, OUT can be ['PDF','PNG','DOT']
			\t\t --center ... finds nodes that have minimal eccentricity within undirected graph and exports graph into file <exported_map.OUT>, OUT can be ['PDF','PNG','DOT']
      \t\t directed graph shows arrows on the directed edges
    END
  end

  # Prints text specifying its usage
  def usage
    puts @usage_text
  end

  # Command line handling
  def process_args
    # not enough parameters - at least load command, input file and action command must be given
    unless ARGV.length >= 3
      puts 'Not enough parameters!'
      puts usage
      exit 1
    end

    # read load command, input file and action command
    @load_cmd = ARGV.shift
    unless @load_cmds_list.include?(@load_cmd)
      puts 'Load command not registred!'
      puts usage
      exit 1
    end
    @map_file = ARGV.shift
    unless File.file?(@map_file)
      puts "File #{@map_file} does not exist!"
      puts usage
      exit 1
    end
    @operation = ARGV.shift
    unless @actions_list.include?(@operation)
      puts 'Action command not registered!'
      puts usage
      exit 1
    end

    if @operation == '--export'
      @out_file = ARGV.shift

    elsif @operation == '--show-nodes'
      if ARGV.length == 0
        @point_operation = 0
      elsif ARGV.length == 3
        @point_operation = 3
        @start = ARGV.shift
        @finish = ARGV.shift
        @out_file = ARGV.shift
      elsif ARGV.length == 5
        @point_operation = 5
        @lat1 = ARGV.shift
        @lon1 = ARGV.shift
        @lat2 = ARGV.shift
        @lon2 = ARGV.shift
        @out_file = ARGV.shift
      else
        wrong
      end
    elsif @operation == '--midist-len' || @operation == '--midist-time'
      if ARGV.length == 3
        @midist_point_oper = 3
        @start = ARGV.shift
        @finish = ARGV.shift
        @out_file = ARGV.shift
      elsif ARGV.length == 5
        @midist_point_oper = 5
        @lat1 = ARGV.shift.to_f
        @lon1 = ARGV.shift.to_f
        @lat2 = ARGV.shift.to_f
        @lon2 = ARGV.shift.to_f
        @out_file = ARGV.shift
      else
        wrong
      end
    elsif @operation == '--center'
      @out_file = ARGV.shift
    else
      wrong
    end
  end

  def wrong
    puts "Its a wrong amount of the parameters for #{@operation}."
  end

  # Determine type of file given by +file_name+ as suffix.
  #
  # @return [String]
  def file_type(file_name)
    file_name[file_name.rindex('.') + 1, file_name.size]
  end

  # Specify log name to be used to log processing information.
  def prepare_log
    ProcessLogger.construct('log/logfile.log')
  end

  # Load graph from OSM file. This methods loads graph and create +Graph+ as well as +VisualGraph+ instances.
  def load_graph(direction)
    graph_loader = GraphLoader.new(@map_file, @highway_attributes)
    @graph, @visual_graph = graph_loader.load_graph(direction)
  end

  def load_graph_comp(direction)
    component_finder = ComponentFinder.new(@map_file, @highway_attributes)
    @graph, @visual_graph = component_finder.load_graph_comp(direction)
  end

  # Load graph from Graphviz file. This methods loads graph and create +Graph+ as well as +VisualGraph+ instances.
  def import_graph
    graph_loader = GraphLoader.new(@map_file, @highway_attributes)
    @graph, @visual_graph = graph_loader.load_graph_viz
  end

  # Run navigation according to arguments from command line
  def run
    # prepare log and read command line arguments
    prepare_log
    process_args

    # load graph - action depends on last suffix
    @highway_attributes = %w[residential motorway trunk primary secondary tertiary unclassified]
    if (file_type(@map_file) == 'osm') || (file_type(@map_file) == 'xml')

      if '--load-undir' == @load_cmd
        load_graph(false)
        direction = false

      else
        if '--load-dir' == @load_cmd
          load_graph(true)
          direction = true
        end
      end

      if '--load-undir-comp' == @load_cmd
        load_graph_comp(false)
        direction = false

      else
        if '--load-dir-comp' == @load_cmd
          load_graph_comp(true)
          direction = true
        end
      end

    else
      if (file_type(@map_file) == 'dot') || (file_type(@map_file) == 'gv')
        import_graph
      else
        puts 'Input file type not recognized!'
        usage
      end

    end

    if direction
      @visual_graph.graph_direction(true)
    else
      @visual_graph.graph_direction(false)
    end

    case @operation
      when '--export'
        @visual_graph.export_graph(true)
        @visual_graph.export_graphviz(@out_file)
      when '--center'
        if @load_cmd == '--load-undir-comp'
          @visual_graph.find_central_vertex
          @visual_graph.export_graphviz(@out_file)
        end
      when '--show-nodes'
        if @point_operation == 0
          @visual_graph.show_nodes
        else
          if @point_operation == 3
            @visual_graph.create_array_vertices([@start, @finish])
            @visual_graph.export_graphviz(@out_file)
          else
            if @point_operation == 5
              id_start = @visual_graph.neighbour_vertex(@lat1, @lon1)
              id_end = @visual_graph.neighbour_vertex(@lat2, @lon2)
              @visual_graph.create_array_vertices([id_start, id_end])
              @visual_graph.export_graphviz(@out_file)
            end
          end
        end
      when '--midist-len'
        if @midist_point_oper == 3
          @visual_graph.create_array_vertices([@start, @finish])
          shortest_path = @visual_graph.find_shortest_path(@start, @finish, direction)
          @visual_graph.max_dist_vertex
          @visual_graph.shortest_path_length(shortest_path)
          @visual_graph.show_path(shortest_path)
          @visual_graph.export_graphviz(@out_file)
        end
        unless @midist_point_oper != 5
          id_start = @visual_graph.neighbour_vertex(@lat1, @lon1)
          id_end = @visual_graph.neighbour_vertex(@lat2, @lon2)
          @visual_graph.create_array_vertices([id_start, id_end])
          shortest_path = @visual_graph.find_shortest_path(id_start, id_end, direction)
          @visual_graph.shortest_path_length(shortest_path)
          @visual_graph.show_path(shortest_path)
          @visual_graph.export_graphviz(@out_file)
        end
      when '--midist-time'
        unless @midist_point_oper != 3
          @visual_graph.create_array_vertices([@start, @finish])
          shortest_path = @visual_graph.find_least_time(@start, @finish, direction)
          @visual_graph.max_dist_vertex
          @visual_graph.shortest_path_length(shortest_path)
          @visual_graph.show_path(shortest_path)
          @visual_graph.export_graphviz(@out_file)
        end
        unless @midist_point_oper != 5
          id_start = @visual_graph.neighbour_vertex(@lat1, @lon1)
          id_end = @visual_graph.neighbour_vertex(@lat2, @lon2)
          @visual_graph.create_array_vertices([id_start, id_end])
          shortest_path = @visual_graph.find_least_time(id_start, id_end, direction)
          @visual_graph.shortest_path_length(shortest_path)
          @visual_graph.show_path(shortest_path)
          @visual_graph.export_graphviz(@out_file)
        end
      else
        usage
        exit 1
      end
  end
end

osm_simple_nav = OSMSimpleNav.new
osm_simple_nav.run