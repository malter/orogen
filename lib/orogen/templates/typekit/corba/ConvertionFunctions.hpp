#ifndef OROCOS_<%= typekit.name.upcase %>_CORBA_IMPL_HPP
#define OROCOS_<%= typekit.name.upcase %>_CORBA_IMPL_HPP

#include "<%= typekit.name %>TypekitTypes.hpp"
#include "<%= typekit.name %>TypekitC.h"
#include <boost/cstdint.hpp>

namespace orogen_typekits {
    <% typesets.converted_types.each do |type| %>
    bool toCORBA( <%= type.corba_ref_type %> corba, <%= type.arg_type %> value );
    bool fromCORBA( <%= type.ref_type %> value, <%= type.corba_arg_type %> corba );
    <% end %>
    <% typesets.array_types.each do |type| %>
    bool toCORBA( <%= type.corba_ref_type %> corba, <%= type.arg_type %> value, int length );
    bool fromCORBA( <%= type.ref_type %> value, int length, <%= type.corba_arg_type %> corba );
    <% end %>
    <% typesets.opaque_types.each do |opdef|
        type = opdef.type
        intermediate_type = typekit.find_type(opdef.intermediate)
        %>
    bool toCORBA( <%= intermediate_type.corba_ref_type %> corba, <%= type.arg_type %> value );
    bool fromCORBA( <%= type.ref_type %> value, <%= intermediate_type.corba_arg_type %> corba );
    <% end %>
}

#endif

