function(core_link_library lib wraplib)
  if(CMAKE_GENERATOR MATCHES "Unix Makefiles" OR CMAKE_GENERATOR STREQUAL Ninja)
    set(wrapper_obj cores/dll-loader/exports/CMakeFiles/wrapper.dir/wrapper.c.o)
  elseif(CMAKE_GENERATOR MATCHES "Xcode")
    set(wrapper_obj cores/dll-loader/exports/kodi.build/$(CONFIGURATION)/wrapper.build/Objects-$(CURRENT_VARIANT)/$(CURRENT_ARCH)/wrapper.o)
  else()
    message(FATAL_ERROR "Unsupported generator in core_link_library")
  endif()

  set(export -bundle -undefined dynamic_lookup -read_only_relocs suppress
             -Wl,-alias_list,${CORE_BUILD_DIR}/cores/dll-loader/exports/wrapper.def
             ${CORE_BUILD_DIR}/${wrapper_obj})
  set(extension ${CMAKE_SHARED_MODULE_SUFFIX})
  set(check_arg "")
  if(TARGET ${lib})
    set(target ${lib})
    set(link_lib $<TARGET_FILE:${lib}>)
    set(check_arg ${ARGV2})
    set(data_arg  ${ARGV3})
  else()
    set(target ${ARGV2})
    set(link_lib ${lib})
    set(check_arg ${ARGV3})
    set(data_arg ${ARGV4})
  endif()
  if(check_arg STREQUAL export)
    set(export ${export}
        -Wl,--version-script=${ARGV3})
  elseif(check_arg STREQUAL nowrap)
    set(export -undefined dynamic_lookup -dynamiclib ${data_arg})
    set(extension ${CMAKE_SHARED_LIBRARY_SUFFIX})
  elseif(check_arg STREQUAL extras)
    foreach(arg ${data_arg})
      list(APPEND export ${arg})
    endforeach()
  endif()
  get_filename_component(dir ${wraplib} PATH)

  # We can't simply pass the linker flags to the args section of the custom command
  # because cmake will add quotes around it (and the linker will fail due to those).
  # We need to do this handstand first ...
  separate_arguments(CUSTOM_COMMAND_ARGS_LDFLAGS UNIX_COMMAND "${CMAKE_SHARED_LINKER_FLAGS}")

  add_custom_command(OUTPUT ${wraplib}-${ARCH}${extension}
                     COMMAND ${CMAKE_COMMAND} -E make_directory ${dir}
                     COMMAND ${CMAKE_C_COMPILER}
                     ARGS    ${CUSTOM_COMMAND_ARGS_LDFLAGS} ${export} -Wl,-force_load ${link_lib}
                             -o ${CMAKE_BINARY_DIR}/${wraplib}-${ARCH}${extension}
                     DEPENDS ${target} wrapper.def wrapper
                     VERBATIM)

  # Uncomment to create wrap_<lib> targets for debugging
  #get_filename_component(libname ${wraplib} NAME_WE)
  #add_custom_target(wrap_${libname} ALL DEPENDS ${wraplib}-${ARCH}${extension})

  list(APPEND WRAP_FILES ${wraplib}-${ARCH}${extension})
  set(WRAP_FILES ${WRAP_FILES} PARENT_SCOPE)
endfunction()

function(find_soname lib)
  cmake_parse_arguments(arg "REQUIRED" "" "" ${ARGN})

  string(TOLOWER ${lib} liblow)
  if(${lib}_LDFLAGS)
    set(link_lib "${${lib}_LDFLAGS}")
  else()
    set(link_lib "${${lib}_LIBRARIES}")
  endif()

  execute_process(COMMAND ${CMAKE_C_COMPILER} -print-search-dirs
                  COMMAND fgrep libraries:
                  COMMAND sed "s/[^=]*=\\(.*\\)/\\1/"
                  COMMAND sed "s/:/ /g"
                  ERROR_QUIET
                  OUTPUT_VARIABLE cc_lib_path
                  OUTPUT_STRIP_TRAILING_WHITESPACE)
  execute_process(COMMAND echo ${link_lib}
                  COMMAND sed "s/-L[ ]*//g"
                  COMMAND sed "s/-l[^ ]*//g"
                  ERROR_QUIET
                  OUTPUT_VARIABLE env_lib_path
                  OUTPUT_STRIP_TRAILING_WHITESPACE)

  foreach(path ${cc_lib_path} ${env_lib_path})
    if(IS_DIRECTORY ${path})
      execute_process(COMMAND ls -- ${path}/lib${liblow}.dylib
                      ERROR_QUIET
                      OUTPUT_VARIABLE lib_file
                      OUTPUT_STRIP_TRAILING_WHITESPACE)
    else()
      set(lib_file ${path})
    endif()
    if(lib_file)
      # we want the path/name that is embedded in the dylib
      execute_process(COMMAND otool -L ${lib_file}
                      COMMAND grep -v lib${liblow}.dylib
                      COMMAND grep ${liblow}
                      COMMAND awk "{V=1; print $V}"
                      ERROR_QUIET
                      OUTPUT_VARIABLE filename
                      OUTPUT_STRIP_TRAILING_WHITESPACE)
      get_filename_component(${lib}_SONAME "${filename}" NAME)
      message(STATUS "${lib} soname: ${${lib}_SONAME}")
    endif()
  endforeach()
  if(arg_REQUIRED AND NOT ${lib}_SONAME)
    message(FATAL_ERROR "Could not find dynamically loadable library ${lib}")
  endif()
  set(${lib}_SONAME ${${lib}_SONAME} PARENT_SCOPE)
endfunction()
