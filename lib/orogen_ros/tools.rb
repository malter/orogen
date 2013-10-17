require 'utilrb'

module Orocos
    module ROS

        @spec_file_suffix = "orogen"
        @spec_search_directories = ["."]

        # This class wraps ros tooling and set some default configurations
        class << self
            attr_reader :spec_file_suffix
            attr_accessor :spec_search_directories

            attr_reader :master_project

            # [Hash<String,Array<String>>] mappings from ROS message types to
            #   oroGen types. It is filled by Orocos::ROS.load_all_rosmaps,
            #   which is called the first time
            #   Orocos::ROS.find_all_types_for is called
            attr_reader :ros_to_orogen_mappings
            # [Hash<String,String>] mappings from oroGen types to ROS message types.
            #   It is filled by Orocos::ROS.load_all_rosmaps, which is called
            #   the first time Orocos::ROS.find_all_types_for is called
            attr_reader :orogen_to_ros_mappings

            # The set of orogen projects that are available, as a mapping from a
            # name into the project's orogen description file
            # attr_reader :available_projects

            # The set of available typekits, as a mapping from the typekit name to a
            # PkgConfig object
            # attr_reader :available_typekits
        end

        def self.suffix(filename)
            filename = filename.gsub(/\.#{spec_file_suffix}/,'')
            "#{filename}.#{spec_file_suffix}"
        end

        def self.project_name_from_file(filename)
            File.basename(filename).gsub(/\.#{spec_file_suffix}/,'')
        end

        # Find the path of a ros package
        # @return [String] Path to the rospackage
        def self.rospack_find(package_name)
            package_path = (`rospack find #{package_name}` || '').strip
            if package_path.empty?
                raise ArgumentError, "rospack cannot find package #{package_name}"
            end
            package_path
        end

        # Find the path of a rosnode binary
        # @return [String] Path to the rosnode binary
        #
        def self.rosnode_find(package_name, binary_name)
            package_path = rospack_find(package_name)

            bin_path = File.join(package_path, 'bin', binary_name)
            if !File.file?(bin_path)
                raise ArgumentError, "there is no node called #{binary_name} in #{package_name} (looked in #{bin_path})"
            end
            bin_path
        end
        
        # @return [Array] List of running ros nodes 
        def self.rosnode_list
            running_nodes = (`rosnode list` || []).split("\n")
        end

        # @return [Bool] True if a ros node of given name is currenlty running
        def self.rosnode_running?(node_name)
             # making sure node name conform to 
             # pattern "/nodename"
             rosnode_list.include?(rosnode_normalize_name(node_name))
        end

        # @
        def self.rosnode_normalize_name(node_name)
             "/#{node_name}".sub(/^\/\//,'/')
        end

        # Run the launch from the package +package_name+ given by +launch_name+
        # @options [Hash] Options are forwarded to Utilrb.spawn, e.g.
        #     :working_directory
        #     :nice
        #     :redirect
        # @return [Int] Pid of the roslaunch process
        def self.roslaunch(package_name, launch_name, options = Hash.new)
            launch_name = launch_name.gsub(/\.launch/,'')
            launch_name = launch_name + ".launch"
            arguments = [package_name, launch_name]
            arguments += [options]

            pid = Utilrb.spawn "roslaunch", "__name:=#{launch_name}", *arguments
            pid
        end

        # Locate the launch file in a given ros package 
        # @return [String] absolute path to the launch file
        # @throws [ArgumentError] if the launch file cannot be found in the ros package
        def self.roslaunch_find(package_name, launch_name)
            package_path = Orocos::ROS.rospack_find(package_name)
            launch_path = File.join(package_path, "launch")

            launch_name = launch_name.gsub(/\.launch$/,"")
            launch_name += ".launch"

            launch_path = File.join(launch_path, launch_name)
            if !File.file?(launch_path)
                raise ArgumentError, "there is no launch_file called #{launch_name} in #{package_name} (looked in #{launch_path})"
            end
            launch_path
        end

        def self.roscore(*args)
            pid = Utilrb.spawn "roscore", *args
            pid
        end

        # @return [String] the type name that should be used on the oroGen
        #   side to represent the given ROS message
        #
        # @param [String] message_type the ROS message type name
        def self.map_message_type_to_orogen(message_type)
            orogen_types = find_all_types_for(message_type)
            if orogen_types.empty?
                raise ArgumentError, "there are not oroGen equivalent for #{message_type}"
            end
            orogen_types.first
        end

        # Loads all known mappings from the oroGen types to the ROS messages.
        # Builds a reverse mapping as well
        def self.load_all_rosmaps
            @ros_to_orogen_mappings = Hash.new
            @orogen_to_ros_mappings = Hash.new
            rosmaps = available_typekits.map do |name, pkg|
                begin
                    Orocos::TypekitMarshallers::ROS.load_rosmap_by_package_name(name)
                rescue ArgumentError => e
                    Orocos::ROS.warn e
                    next
	        rescue Utilrb::PkgConfig::NotFound => e
	            Orocos::ROS.warn e
	            next
                end
            end.compact
            rosmaps << Orocos::TypekitMarshallers::ROS::DEFAULT_TYPE_TO_MSG

            rosmaps.each do |rosmap|
                orogen_to_ros_mappings.merge! rosmap
                rosmap.each do |type_name, ros_name, _|
                    set = (ros_to_orogen_mappings[ros_name] ||= Set.new)
                    set << type_name
                end
            end
            nil
        end

        # Get the list of oroGen types that can be used to communicate with a
        # given ROS message name
        #
        # At first call, it calls load_all_rosmaps to load all the known
        # mappings
        def self.find_all_types_for(message_name)
            if !ROS.ros_to_orogen_mappings
                load_all_rosmaps
            end

            ROS.ros_to_orogen_mappings[message_name] || Set.new
        end

        # Check if a given ROS message type can be accessed on this side
        #
        # At first call, it calls load_all_rosmaps to load all the known
        # mappings
        def self.compatible_message_type?(message_type)
            if !ROS.ros_to_orogen_mappings
                load_all_rosmaps
            end
            ROS.ros_to_orogen_mappings.has_key?(message_type)
        end

        # Find all available launchers defined
        # in ros specification files
        def self.available_launchers
            if !@available_launchers
                @available_launchers = Hash.new

                available_ros_projects.each do |pkg, pkg_desc|
                    _, deffile = pkg_desc
                    project = Orocos::ROS::Generation::Project.load(deffile)
                    project.ros_launchers.each do |l|
                        @available_launchers[l.name] = l
                    end
                end
            end
            @available_launchers
        end

        # Retrieve the list of available ros projects
        def self.available_ros_projects
            if !@available_ros_projects
                @available_ros_projects = Hash.new

                spec_search_directories.each do |dir|
                    specs = Dir.glob(File.join(dir, suffix("*")))
                    specs.each do |path|
                        project_name = project_name_from_file(path)
                        @available_ros_projects[project_name] = [nil, File.absolute_path(path)]
                    end
                end
                available_projects.merge!(@available_ros_projects)
            end
            @available_ros_projects
        end

        ##################################################################
        # BEGIN
        #
        # Functionality extracted from orocos.rb with modifications to allow for ROS 
        # loading
        # Future cleanup should consider moving Orocos.load functionality to orogen 
        # and then cleanup this functionality and reuse Orocos.available_projects

        # Helper method for initialize
        def self.load(*args)
            args.each do |path|
                spec_search_directories << File.absolute_path(path) if File.exists?(path)
            end

            if @available_projects && !@available_projects.empty?
                return
            end

            if @registry
                raise ArgumentError, "you must call Orocos.clear before calling Orocos.load again"
            end

            # If Orocos is in use, hook into the Orocos.master_project instead of maintaining
            # a separated version in Orocos::ROS.master_project
            @master_project = Orocos.master_project || Orocos::Generation::Component.new
            @registry = master_project.registry

            available_types
            available_ros_projects
        end

        def self.add_project_from(pkg) # :nodoc:
            project = pkg.project_name
            if project.empty?
                Orocos.warn "#{pkg.name}.pc does not have a project_name field"
            end
            if description = available_projects[project]
                return description
            end

            if pkg.deffile.empty?
                Orocos.warn "#{pkg.name}.pc does not have a deffile field"
            else
                @available_projects[pkg.project_name] = [pkg, pkg.deffile]
            end
        end

        def self.available_projects
            if !@available_projects
                @available_projects = Hash.new

                # Finally, update the set of available projects
                Utilrb::PkgConfig.each_package(/^orogen-project-/) do |pkg_name|
                    if !available_projects.has_key?(pkg_name)
                        pkg = Utilrb::PkgConfig.new(pkg_name)
                        add_project_from(pkg)
                    end
                end
            end
            @available_projects
        end


        def self.available_typekits
            if !@available_typekits

                @available_typekits = Hash.new
                Utilrb::PkgConfig.each_package(/-typekit-/) do |pkg_name|
                    pkg = Utilrb::PkgConfig.new(pkg_name)

                    # If Orocos is not loaded try without Orocos.orocos_target
                    if !Orocos.orocos_target 
                        typekit_name = pkg_name.gsub(/-typekit-\w+$/, '')
                    else
                        typekit_name = pkg_name.gsub(/-typekit-#{Orocos.orocos_target}$/, '')
                    end

                    if available_projects.has_key?(pkg.project_name)
                        if available_projects[pkg.project_name][0].type_registry
                            available_typekits[typekit_name] = pkg
                        else
                            Orocos.warn "found typekit #{typekit_name}, but the corresponding oroGen project #{pkg.project_name} does not have a typekit. Consider deleting #{pkg.path}."
                        end
                    else
                        Orocos.warn "found typekit #{typekit_name}, but the corresponding oroGen project #{pkg.project_name} could not be found. Consider deleting #{pkg.path}."
                    end 
                end
                @available_typekits
            else
                @available_typekits
            end
        end

        def self.available_types
            if !@available_types = Hash.new
                available_typekits.each do |typekit_name, typekit_pkg|
                    typelist = typekit_pkg.type_registry.gsub(/tlb$/, 'typelist')
                    typelist, typelist_exported =
                        Orocos::Generation::ImportedTypekit.parse_typelist(File.read(typelist))
                    typelist = typelist - typelist_exported
                    typelist.compact.each do |typename|
                        if existing = @available_types[typename]
                            Orocos.info "#{typename} is defined by both #{existing[0]} and #{typekit_name}"
                        else
                            @available_types[typename] = [typekit_name, false]
                        end
                    end
                    typelist_exported.compact.each do |typename|
                        if existing = @available_types[typename]
                            Orocos.info "#{typename} is defined by both #{existing[0]} and #{typekit_name}"
                        end
                        @available_types[typename] = [typekit_name, true]
                    end
                end
            end
            nil
        end
        #
        # END
        ######################################################################
    end
end
