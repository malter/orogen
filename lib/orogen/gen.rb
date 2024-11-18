# frozen_string_literal: true

require "orogen"

module OroGen
    module Gen
        extend Logger::Hierarchy

        module RTT_CPP
            extend Logger::Hierarchy

            ConfigError = OroGen::ConfigError
            OROGEN_LIB_DIR = OroGen::OROGEN_LIB_DIR

            ConfigurationObject = Spec::ConfigurationObject
            Attribute           = Spec::Attribute
            Property            = Spec::Property

            Operation           = Spec::Operation

            Port                = Spec::Port
            OutputPort          = Spec::OutputPort
            InputPort           = Spec::InputPort
            DynamicInputPort    = Spec::DynamicInputPort
            DynamicOutputPort   = Spec::DynamicInputPort

            TaskContext         = Spec::TaskContext
        end
    end
    Generation = Gen::RTT_CPP
end

require "orogen/gen/enable"
require "orogen/gen/base"
require "orogen/gen/templates"
require "orogen/gen/typekit"
require "orogen/marshallers"
require "orogen/gen/deployment"
require "orogen/gen/tasks"
require "orogen/gen/project"
require "orogen/gen/imports"
OroGen::Gen::RTT_CPP::Typekit.register_plugin(OroGen::TypekitMarshallers::ROS::Plugin)
OroGen::Gen::RTT_CPP::Typekit.register_plugin(OroGen::TypekitMarshallers::Corba::Plugin)
OroGen::Gen::RTT_CPP::Typekit.register_plugin(OroGen::TypekitMarshallers::MQueue::Plugin)
OroGen::Gen::RTT_CPP::Typekit.register_plugin(OroGen::TypekitMarshallers::TypeInfo::Plugin)
OroGen::Gen::RTT_CPP::Typekit.register_plugin(OroGen::TypekitMarshallers::TypelibMarshaller::Plugin)

OroGen::Gen::RTT_CPP::Deployment.register_global_initializer(
    :qt,
    global_scope: <<~QT_GLOBAL_SCOPE,
        static int QT_ARGC = 1;
        static char const* QT_ARGV[] = { "orogen", nullptr };
        #include <pthread.h>
        #include <QApplication>

        void* qt_thread_exit(void*)
        {
            while(!exiting) usleep(10000);
            // due to the signal handling the qapp is
            // reopend before this thread closes. So we have to
            // quit the new app again.
            qApp->exit();
            return NULL;
        }
    QT_GLOBAL_SCOPE
    run: <<~QT_RUN_CODE,
    if( !vm.count("no-qtapp") or vm["no-qtapp"].as<bool>() == false) {

      pthread_t qt_thread;
      pthread_create(&qt_thread, NULL, qt_thread_exit, NULL);
      pthread_t o_thread;
      pthread_create(&o_thread, NULL, oro_thread, NULL);
      /*
        This loop generates a new qApp. The qApp can be closed if the application
        main window is closed. By generating a new qApp in that case, we can
        reconfigure the task and open a new GUI.
      */
      while(!exiting) {
         QApplication *qapp = new QApplication(argc,argv);
        qapp->exec();
      }
      pthread_join(qt_thread, NULL);
      pthread_join(o_thread, NULL);
    }
    QT_RUN_CODE
    tasks_cmake: <<~QT_DEPLOYMENT_CMAKE,
        find_package(lib_manager)
        lib_defaults()
        setup_qt()
        if (${USE_QT5})
          qt5_use_modules(_to_be_adapted_ Widgets)
        endif (${USE_QT5})
        set(CMAKE_AUTOMOC true)
    QT_DEPLOYMENT_CMAKE
    deployment_cmake: <<~QT_DEPLOYMENT_CMAKE,
        find_package(lib_manager)
        lib_defaults()
        setup_qt()
        if (${USE_QT5})
          qt5_use_modules(<%= deployer.name %> Widgets)
        endif (${USE_QT5})
        target_link_libraries(<%= deployer.name %> ${QT_LIBRARIES})
        set(CMAKE_AUTOMOC true)
    QT_DEPLOYMENT_CMAKE
)
