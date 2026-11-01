if(PORT STREQUAL "tbb")
    set(VCPKG_C_FLAGS "-mrtm")
    set(VCPKG_CXX_FLAGS "-mrtm")
endif()
if(PORT MATCHES "^(re2)$")
    set(VCPKG_LIBRARY_LINKAGE static)
endif()

# Note: All gn ports still use cl unless we figure out to pass it a toolchain somehow. 
if(PORT MATCHES "^(arrow|akali|arb|cello|chakracore|flint|folly|glog|zydis|graphicsmagick|freerdp|gtk|irrlicht|libde265|llfio|mongo-c-driver|tcl|nvtt)$")
    # akali -> typedef private void (T::*POnTimer)(void); -> error
    # arb -> probably related to flint!
    # cello -> redefines throw();
    # cgicc -> error: explicit instantiation of 'vector' not in a namespace enclosing 'std'
    # chakracore
    # mongo-c-driver -> strange redefinition error. Couldn't find why it claims that the defs are different. 
    # llfio -> code has correctness issues which cl accepts. (wrong thread_local and friend declaration)
    # gtk -> .res files in archives via /WHOLEARCHIVE not correctly handled by lld-link yet
    # libde265 -> probably some macro collision
    # arrow implicit deleted default constructor
    # libirecovery missing getopt linkage -> linkage general problem in msbuild ports since autolinkage is deactivated`?
    # graphicsmagick -> requires wrapping the allocators in namespace std
    # glog hardcodes builtin expected if build with clang-cl (#if 1 otehrwise #if 0) -> folly sees that. 
    # zydis,freerdp,irrlicht UTF-16 encoding in rc file
    # tcl -> requires nmake compiler setup
    # nvtt: too complicated compiler dependent behavior to fix quickly. 
    # TODO: Recheck flint
    message(STATUS "Falling back to cl!")
    unset(VCPKG_CHAINLOAD_TOOLCHAIN_FILE)
    unset(VCPKG_PLATFORM_TOOLSET)
    unset(VCPKG_VS_CMAKE_GENERATOR)
    set(ENV{PATH} "${LLVM_PATH_BACKUP}")
endif()

if(PORT MATCHES "^gettext$" AND "tools" IN_LIST FEATURES
   OR PORT MATCHES "^gettext-libintl$") # uses /EXTRACT unsupported by llvm-lib
    list(APPEND VCPKG_CMAKE_CONFIGURE_OPTIONS "-DCMAKE_AR=llvm-ar.exe")
    set(ENV{AR} "llvm-ar.exe")
endif()

if(CMAKE_PARENT_LIST_FILE MATCHES "-lto(\\\.|-)" AND NOT PORT MATCHES "(benchmark|gtest|pkgconf|^qt[a-z]+)")
    list(APPEND VCPKG_CMAKE_CONFIGURE_OPTIONS "-DVCPKG_USE_LTO:BOOL=TRUE")
endif()
if(PORT MATCHES "(qtconnectivity|qtsensors|qtspeech)")
  list(APPEND VCPKG_CMAKE_CONFIGURE_OPTIONS "-DQT_FEATURE_cxx20=ON")
  # cppwinrt uses Coroutines which is only supported with c++20 using clang
endif()

# clang-cl accepts C++11, but recent MSVC STL headers require C++14.
# Meson with clang-cl honors -Dcpp_std=c++11 exactly, unlike its cl.exe
# backend. Raise a port's *explicit* legacy Meson standard to C++14.
#
# vcpkg_configure_meson() appends VCPKG_MESON_CONFIGURE_OPTIONS after the
# portfile's OPTIONS, so this is a supported late override. Do not redefine
# vcpkg_configure_meson: the triplet has no reliable alias for that helper.
# Only change ports that visibly request an old standard. Never force C++14
# on a port requesting C++17/20/23 (or on ports with unknown requirements).
if(DEFINED CURRENT_PORT_DIR AND EXISTS "${CURRENT_PORT_DIR}/portfile.cmake")
    file(STRINGS "${CURRENT_PORT_DIR}/portfile.cmake" _llvm_cpp_std_lines REGEX "cpp_std")
    set(_llvm_meson_standards "")
    foreach(_llvm_line IN LISTS _llvm_cpp_std_lines)
        string(STRIP "${_llvm_line}" _llvm_line)
        if(_llvm_line MATCHES "^#")
            continue()
        endif()
        # Match the literal Meson option, including options passed via a
        # CMake variable. Ignore comments and other unrelated standard flags.
        if(_llvm_line MATCHES "-Dcpp_std[ \t]*=[ \t]*(c\\+\\+|gnu\\+\\+|vc\\+\\+)(98|03|0x|11|14|17|20|23|26)([^0-9A-Za-z]|$)")
            list(APPEND _llvm_meson_standards "${CMAKE_MATCH_1}${CMAKE_MATCH_2}")
        endif()
    endforeach()
    list(REMOVE_DUPLICATES _llvm_meson_standards)
    list(LENGTH _llvm_meson_standards _llvm_std_count)
    if(_llvm_std_count EQUAL 1)
        list(GET _llvm_meson_standards 0 _llvm_requested_std)
        if(_llvm_requested_std MATCHES "^(c\\+\\+|gnu\\+\\+|vc\\+\\+)(98|03|0x|11)$")
            set(_llvm_floor_std "${CMAKE_MATCH_1}14")
            list(APPEND VCPKG_MESON_CONFIGURE_OPTIONS "-Dcpp_std=${_llvm_floor_std}")
            message(STATUS "clang-cl Meson standard floor for ${PORT}: ${_llvm_requested_std} -> ${_llvm_floor_std}")
        endif()
    elseif(_llvm_std_count GREATER 1)
        # Ambiguous source (possibly several conditional options): do not
        # override a potentially newer requested standard.
        message(STATUS "clang-cl Meson standard floor: skipping ambiguous standards in ${PORT}")
    endif()
    unset(_llvm_cpp_std_lines)
    unset(_llvm_line)
    unset(_llvm_meson_standards)
    unset(_llvm_std_count)
    unset(_llvm_requested_std)
    unset(_llvm_floor_std)
endif()
