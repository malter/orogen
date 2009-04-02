ADD_CUSTOM_TARGET(regen
    orogen <%= "--corba" if component.corba_enabled? %> <%= component.deffile %>
    WORKING_DIRECTORY ${PROJECT_SOURCE_DIR})

# In Orogen components, the build target is specified at generation time
set(OROCOS_TARGET "<%= component.orocos_target %>")

# Enable -Wall for compilers that know it
include(CheckCXXCompilerFlag)
CHECK_CXX_COMPILER_FLAG("-Wall", CXX_SUPPORTS_WALL)
if (CXX_SUPPORTS_WALL)
    set (CMAKE_CXX_FLAGS ${CMAKE_CXX_FLAGS} -Wall)
endif (CXX_SUPPORTS_WALL)

# Define the necessary RPath information for all binaries. That can be stripped
# later
option(WITH_RPATH "enables or disables embedding RPath information in binaries" ON)
if(WITH_RPATH)
    include(RPATHHandling)
    CMAKE_USE_FULL_RPATH("${CMAKE_INSTALL_PREFIX}/lib:${CMAKE_INSTALL_PREFIX}/lib/orocos")
endif(WITH_RPATH)

# Set the build type to debug by default
IF ( NOT CMAKE_BUILD_TYPE )
  SET( CMAKE_BUILD_TYPE Debug )
ENDIF ( NOT CMAKE_BUILD_TYPE )

# Check for Doxygen and enable documentation building if available
FIND_PACKAGE( Doxygen )
IF ( DOXYGEN )
  MESSAGE( "Found Doxygen -- documentation can be built" )
ELSE ( DOXYGEN )
  MESSAGE( "Doxygen not found -- unable to build documentation" )
ENDIF ( DOXYGEN )

include(CMakeDependentOption)
CMAKE_DEPENDENT_OPTION( DOC_GENERATE "Generate Doxygen documentation" ON "DOXYGEN" OFF )

#
# Start setting up the build itself
#

# First, we need the Orocos::RTT, and optionally the CORBA part
include(FindPkgConfig) # This is the Cmake 2.6 FindPkgConfig macro
pkg_check_modules(OrocosRTT REQUIRED "orocos-rtt-${OROCOS_TARGET}>=1.6.99")
<% if component.corba_enabled? %>
    <% if !component.toolkit || !component.toolkit.corba_enabled? %>
find_package(OrocosCORBA REQUIRED)
    <% else %>
find_package(OrocosCORBA REQUIRED COMPONENTS Toolkit)
    <% end %>
INCLUDE_DIRECTORIES(${OrocosCORBA_INCLUDE_DIRS})
ADD_DEFINITIONS(${OrocosCORBA_DEFINES})
<% end %>

# Add generic include directories
INCLUDE_DIRECTORIES(BEFORE ${PROJECT_SOURCE_DIR}/<%= Generation::AUTOMATIC_AREA_NAME %>)
INCLUDE_DIRECTORIES(BEFORE ${PROJECT_SOURCE_DIR})

# Take care of the toolkit
<% if component.toolkit %>
pkg_check_modules(TYPELIB REQUIRED "typelib>=1.1")
ADD_SUBDIRECTORY( ${CMAKE_SOURCE_DIR}/<%= Generation::AUTOMATIC_AREA_NAME %>/toolkit )
INCLUDE_DIRECTORIES("${CMAKE_SOURCE_DIR}/<%= Generation::AUTOMATIC_AREA_NAME %>/toolkit")
<% end %>

# Take care of the task library
<% if !component.self_tasks.empty? %>
ADD_SUBDIRECTORY(${CMAKE_SOURCE_DIR}/<%= Generation::AUTOMATIC_AREA_NAME %>/tasks)
ADD_SUBDIRECTORY(${CMAKE_SOURCE_DIR}/tasks)
<% end %>

# Finally, add deployment code
<% component.deployers.each do |deploy| %>
    <%= deploy.cmake_code %>
<% end %>
