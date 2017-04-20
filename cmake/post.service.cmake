###                                 ###
## CMakeList for IncludeOS services ##
#___________________________________#

# IncludeOS install location
if (NOT DEFINED ENV{INCLUDEOS_PREFIX})
  set(ENV{INCLUDEOS_PREFIX} /usr/local)
endif()

set(INSTALL_LOC $ENV{INCLUDEOS_PREFIX}/includeos)

# TODO: Verify that the OS libraries exist
set(ARCH x86_64)
if(DEFINED ENV{ARCH})
  set(ARCH $ENV{ARCH})
endif()
message(STATUS "Target CPU architecture ${ARCH}")

set(TRIPLE "${ARCH}-pc-linux-elf")
set(CMAKE_CXX_COMPILER_TARGET ${TRIPLE})
set(CMAKE_C_COMPILER_TARGET ${TRIPLE})
message(STATUS "Target triple ${TRIPLE}")

# Assembler
if ("${ARCH}" STREQUAL "x86_64")
  set (ARCH_INTERNAL "ARCH_X64")
  set(CMAKE_ASM_NASM_OBJECT_FORMAT "elf64")
else()
  set (ARCH_INTERNAL "ARCH_X86")
  set(CMAKE_ASM_NASM_OBJECT_FORMAT "elf")
endif()
enable_language(ASM_NASM)

# defines $CAPABS depending on installation
include(${CMAKE_CURRENT_LIST_DIR}/settings.cmake)

# Various global defines
# * OS_TERMINATE_ON_CONTRACT_VIOLATION provides classic assert-like output from Expects / Ensures
# * _GNU_SOURCE enables POSIX-extensions in newlib, such as strnlen. ("everything newlib has", ref. cdefs.h)
set(CAPABS "${CAPABS} -fstack-protector-strong -DOS_TERMINATE_ON_CONTRACT_VIOLATION -D_GNU_SOURCE -DSERVICE=\"\\\"${BINARY}\\\"\" -DSERVICE_NAME=\"\\\"${SERVICE_NAME}\\\"\"")
set(WARNS  "-Wall -Wextra") #-pedantic

# configure options
option(debug "Build with debugging symbols (OBS: increases binary size)" OFF)
option(minimal "Build for minimal size" OFF)
option(stripped "Strip symbols to further reduce size" OFF)

add_definitions(-D${ARCH})

# Compiler optimization
set(OPTIMIZE "-O2")
if (minimal)
  set(OPTIMIZE "-Os")
endif()
if (debug)
  set(CAPABS "${CAPABS} -g")
endif()

if (CMAKE_COMPILER_IS_GNUCC)
  set(CMAKE_CXX_FLAGS "-m32 -MMD ${CAPABS} ${WARNS} -nostdlib -c -std=c++14 -D_LIBCPP_HAS_NO_THREADS=1")
  set(CMAKE_C_FLAGS "-m32 -MMD ${CAPABS} ${WARNS} -nostdlib -c")
else()
  # these kinda work with llvm
  set(CMAKE_CXX_FLAGS "-MMD ${CAPABS} ${OPTIMIZE} ${WARNS} -nostdlib -nostdlibinc -c -std=c++14 -D_LIBCPP_HAS_NO_THREADS=1")
  set(CMAKE_C_FLAGS "-MMD ${CAPABS} ${OPTIMIZE} ${WARNS} -nostdlib -nostdlibinc -c")
endif()

# executable
set(SERVICE_STUB "${INSTALL_LOC}/src/service_name.cpp")

add_executable(service ${SOURCES} ${SERVICE_STUB})
set_target_properties(service PROPERTIES OUTPUT_NAME ${BINARY})


#
# DRIVERS / PLUGINS - support for parent cmake list specification
#

# Function:
# Add plugin / driver as library, set link options
function(configure_plugin type plugin_name path)
  add_library(${type}_${plugin_name} STATIC IMPORTED)
  set_target_properties(${type}_${plugin_name} PROPERTIES LINKER_LANGUAGE CXX)
  set_target_properties(${type}_${plugin_name} PROPERTIES IMPORTED_LOCATION ${path})
  target_link_libraries(service --whole-archive ${type}_${plugin_name} --no-whole-archive)
endfunction()

# Function:
# Configure plugins / drivers in a given list provided by e.g. parent script
function(enable_plugins plugin_list search_loc)

  if (NOT ${plugin_list})
    return()
  endif()

  get_filename_component(type ${search_loc} NAME_WE)
  message(STATUS "Looking for ${type} in ${search_loc}")
  foreach(plugin_name ${${plugin_list}})
    unset(path_found CACHE)
    find_library(path_found ${plugin_name} PATHS ${search_loc} NO_DEFAULT_PATH)
    if (NOT path_found)
      message(FATAL_ERROR "Couldn't find " ${type} ":" ${plugin_name})
    else()
      message(STATUS "\t* Found " ${plugin_name})
    endif()
    configure_plugin(${type} ${plugin_name} ${path_found})
  endforeach()
endfunction()

# Function:
# Adds driver / plugin configure option, enables if option is ON
function(plugin_config_option type plugin_list)
  foreach(FILENAME ${${plugin_list}})
    get_filename_component(OPTNAME ${FILENAME} NAME_WE)
    option(${OPTNAME} "Add ${OPTNAME} ${type}" OFF)
    if (${OPTNAME})
      message(STATUS "Enabling ${type} ${OPTNAME}")
      configure_plugin(${type} ${OPTNAME} ${FILENAME})
    endif()
  endforeach()
endfunction()

# Location of installed drivers / plugins
set(DRIVER_LOC ${INSTALL_LOC}/${ARCH}/drivers)
set(PLUGIN_LOC ${INSTALL_LOC}/${ARCH}/plugins)

# Enable DRIVERS which may be specified by parent cmake list
enable_plugins(DRIVERS ${DRIVER_LOC})
enable_plugins(PLUGINS ${PLUGIN_LOC})

# Global lists of installed Drivers / Plugins
file(GLOB DRIVER_LIST "${DRIVER_LOC}/*.a")
file(GLOB PLUGIN_LIST "${PLUGIN_LOC}/*.a")

# Set configure option for each installed driver
plugin_config_option(driver DRIVER_LIST)
plugin_config_option(plugin PLUGIN_LIST)

# Simple way to build subdirectories before service
foreach(DEP ${DEPENDENCIES})
  get_filename_component(DIR_PATH "${DEP}" DIRECTORY BASE_DIR "${CMAKE_SOURCE_DIR}")
  get_filename_component(DEP_NAME "${DEP}" NAME BASE_DIR "${CMAKE_SOURCE_DIR}")
  #get_filename_component(BIN_PATH "${DEP}" REALPATH BASE_DIR "${CMAKE_CURRENT_BINARY_DIR}")
  add_subdirectory(${DIR_PATH})
  add_dependencies(service ${DEP_NAME})
endforeach()

# add all extra libs
foreach(LIBR ${LIBRARIES})
  # if relative path but not local, use includeos lib.
  if(NOT IS_ABSOLUTE ${LIBR} AND NOT EXISTS ${LIBR})
    set(OS_LIB "$ENV{INCLUDEOS_PREFIX}/includeos/${ARCH}/lib/${LIBR}")
    if(EXISTS ${OS_LIB})
      message(STATUS "Cannot find local ${LIBR}; using ${OS_LIB} instead")
      set(LIBR ${OS_LIB})
    endif()
  endif()
  get_filename_component(LNAME ${LIBR} NAME_WE)
  add_library(libr_${LNAME} STATIC IMPORTED)
  set_target_properties(libr_${LNAME} PROPERTIES LINKER_LANGUAGE CXX)
  set_target_properties(libr_${LNAME} PROPERTIES IMPORTED_LOCATION ${LIBR})

  target_link_libraries(service libr_${LNAME})
endforeach()


# includes
include_directories(${LOCAL_INCLUDES})
include_directories(${INSTALL_LOC}/api/posix)
include_directories(${INSTALL_LOC}/${ARCH}/include/libcxx)
include_directories(${INSTALL_LOC}/${ARCH}/include/newlib)
include_directories(${INSTALL_LOC}/api)
include_directories(${INSTALL_LOC}/include)
include_directories($ENV{INCLUDEOS_PREFIX}/include)


# linker stuff
set(CMAKE_SHARED_LIBRARY_LINK_CXX_FLAGS) # this removed -rdynamic from linker output
set(CMAKE_CXX_LINK_EXECUTABLE "<CMAKE_LINKER> -o <TARGET> <LINK_FLAGS> <OBJECTS> <LINK_LIBRARIES>")

set(BUILD_SHARED_LIBRARIES OFF)
set(CMAKE_EXE_LINKER_FLAGS "-static")

set(STRIP_LV)
if (NOT debug)
  set(STRIP_LV "--strip-debug")
endif()
if (stripped)
  set(STRIP_LV "--strip-all")
endif()

set(ELF ${ARCH})
if (${ELF} STREQUAL "i686")
  set(ELF "i386")
endif()


set(LDFLAGS "-nostdlib -melf_${ELF} -N --eh-frame-hdr ${STRIP_LV} --script=${INSTALL_LOC}/linker.ld ${INSTALL_LOC}/${ARCH}/lib/crtbegin.o")

set_target_properties(service PROPERTIES LINK_FLAGS "${LDFLAGS}")


add_library(crti STATIC IMPORTED)
set_target_properties(crti PROPERTIES LINKER_LANGUAGE CXX)
set_target_properties(crti PROPERTIES IMPORTED_LOCATION ${INSTALL_LOC}/${ARCH}/lib/libcrti.a)

target_link_libraries(service --whole-archive crti --no-whole-archive)

add_library(libos STATIC IMPORTED)
set_target_properties(libos PROPERTIES LINKER_LANGUAGE CXX)
set_target_properties(libos PROPERTIES IMPORTED_LOCATION ${INSTALL_LOC}/${ARCH}/lib/libos.a)

add_library(libarch STATIC IMPORTED)
set_target_properties(libarch PROPERTIES LINKER_LANGUAGE CXX)
set_target_properties(libarch PROPERTIES IMPORTED_LOCATION ${INSTALL_LOC}/${ARCH}/lib/libarch.a)


add_library(libbotan STATIC IMPORTED)
set_target_properties(libbotan PROPERTIES LINKER_LANGUAGE CXX)
set_target_properties(libbotan PROPERTIES IMPORTED_LOCATION ${INSTALL_LOC}/${ARCH}/lib/libbotan-2.a)

add_library(libosdeps STATIC IMPORTED)
set_target_properties(libosdeps PROPERTIES LINKER_LANGUAGE CXX)
set_target_properties(libosdeps PROPERTIES IMPORTED_LOCATION ${INSTALL_LOC}/${ARCH}/lib/libosdeps.a)

add_library(libcxx STATIC IMPORTED)
add_library(cxxabi STATIC IMPORTED)
set_target_properties(libcxx PROPERTIES LINKER_LANGUAGE CXX)
set_target_properties(libcxx PROPERTIES IMPORTED_LOCATION ${INSTALL_LOC}/${ARCH}/lib/libc++.a)
set_target_properties(cxxabi PROPERTIES LINKER_LANGUAGE CXX)
set_target_properties(cxxabi PROPERTIES IMPORTED_LOCATION ${INSTALL_LOC}/${ARCH}/lib/libc++abi.a)

add_library(libc STATIC IMPORTED)
set_target_properties(libc PROPERTIES LINKER_LANGUAGE C)
set_target_properties(libc PROPERTIES IMPORTED_LOCATION ${INSTALL_LOC}/${ARCH}/lib/libc.a)
add_library(libm STATIC IMPORTED)
set_target_properties(libm PROPERTIES LINKER_LANGUAGE C)
set_target_properties(libm PROPERTIES IMPORTED_LOCATION ${INSTALL_LOC}/${ARCH}/lib/libm.a)
add_library(libg STATIC IMPORTED)
set_target_properties(libg PROPERTIES LINKER_LANGUAGE C)
set_target_properties(libg PROPERTIES IMPORTED_LOCATION ${INSTALL_LOC}/${ARCH}/lib/libg.a)
add_library(libgcc STATIC IMPORTED)
set_target_properties(libgcc PROPERTIES LINKER_LANGUAGE C)
set_target_properties(libgcc PROPERTIES IMPORTED_LOCATION ${INSTALL_LOC}/${ARCH}/lib/libgcc.a)

# add memdisk
function(add_memdisk DISK)
  get_filename_component(DISK_RELPATH "${DISK}"
                         REALPATH BASE_DIR "${CMAKE_SOURCE_DIR}")
  add_custom_command(
    OUTPUT  memdisk.o
    COMMAND python ${INSTALL_LOC}/memdisk/memdisk.py --file ${INSTALL_LOC}/memdisk/memdisk.asm ${DISK_RELPATH}
    COMMAND nasm -f ${CMAKE_ASM_NASM_OBJECT_FORMAT} ${INSTALL_LOC}/memdisk/memdisk.asm -o memdisk.o
    DEPENDS ${DISK_RELPATH}
  )
  add_library(memdisk STATIC memdisk.o)
  set_target_properties(memdisk PROPERTIES LINKER_LANGUAGE CXX)
  target_link_libraries(service --whole-archive memdisk --no-whole-archive)
endfunction()

# automatically build memdisk from folder
function(diskbuilder FOLD)
  get_filename_component(REL_PATH "${FOLD}" REALPATH BASE_DIR "${CMAKE_SOURCE_DIR}")
  add_custom_command(
      OUTPUT  memdisk.fat
      COMMAND ${INSTALL_LOC}/bin/diskbuilder -o memdisk.fat ${REL_PATH}
    )
  add_custom_target(diskbuilder ALL DEPENDS memdisk.fat)
  add_dependencies(service diskbuilder)
  add_memdisk("${CMAKE_BINARY_DIR}/memdisk.fat")
endfunction()

if(TARFILE)
  get_filename_component(TAR_RELPATH "${TARFILE}"
                         REALPATH BASE_DIR "${CMAKE_SOURCE_DIR}")

  if(CREATE_TAR)
    get_filename_component(TAR_BASE_NAME "${CREATE_TAR}" NAME)
    add_custom_command(
      OUTPUT tarfile.o
      COMMAND tar cf ${TAR_RELPATH} -C ${CMAKE_SOURCE_DIR} ${TAR_BASE_NAME}
      COMMAND cp ${TAR_RELPATH} input.bin
      COMMAND ${CMAKE_OBJCOPY} -I binary -O elf32-i386 -B i386 input.bin tarfile.o
      COMMAND rm input.bin
    )
  elseif(CREATE_TAR_GZ)
    get_filename_component(TAR_BASE_NAME "${CREATE_TAR_GZ}" NAME)
    add_custom_command(
      OUTPUT tarfile.o
      COMMAND tar czf ${TAR_RELPATH} -C ${CMAKE_SOURCE_DIR} ${TAR_BASE_NAME}
      COMMAND cp ${TAR_RELPATH} input.bin
      COMMAND ${CMAKE_OBJCOPY} -I binary -O elf32-i386 -B i386 input.bin tarfile.o
      COMMAND rm input.bin
    )
  else(true)
    add_custom_command(
      OUTPUT tarfile.o
      COMMAND cp ${TAR_RELPATH} input.bin
      COMMAND ${CMAKE_OBJCOPY} -I binary -O elf32-i386 -B i386 input.bin tarfile.o
      COMMAND rm input.bin
    )
  endif(CREATE_TAR)

  add_library(tarfile STATIC tarfile.o)
  set_target_properties(tarfile PROPERTIES LINKER_LANGUAGE CXX)
  target_link_libraries(service --whole-archive tarfile --no-whole-archive)
endif(TARFILE)

add_library(crtn STATIC IMPORTED)
set_target_properties(crtn PROPERTIES LINKER_LANGUAGE CXX)
set_target_properties(crtn PROPERTIES IMPORTED_LOCATION ${INSTALL_LOC}/${ARCH}/lib/libcrtn.a)

# all the OS and C/C++ libraries + crt end
target_link_libraries(service
  libarch
  libos
  libbotan
  libosdeps
  cxxabi
  libarch
  libos
  libc
  libos
  libcxx
  libm
  libg
  libgcc
  ${INSTALL_LOC}/${ARCH}/lib/crtend.o
  --whole-archive crtn --no-whole-archive
  )
# write binary location to known file
file(WRITE ${CMAKE_BINARY_DIR}/binary.txt ${BINARY})

set(STRIP_LV ${CMAKE_STRIP} --strip-all ${BINARY})
if (debug)
  set(STRIP_LV /bin/true)
endif()

add_custom_target(
  pruned_elf_symbols ALL
  COMMAND ${INSTALL_LOC}/bin/elf_syms ${BINARY}
  COMMAND ${CMAKE_OBJCOPY} --update-section .elf_symbols=_elf_symbols.bin ${BINARY} ${BINARY}
  COMMAND ${STRIP_LV}
  DEPENDS service
)

# create .img files too automatically
add_custom_target(
  prepend_bootloader ALL
  COMMAND ${INSTALL_LOC}/bin/vmbuild ${BINARY} ${INSTALL_LOC}/${ARCH}/boot/bootloader
  DEPENDS service
)

# install binary directly to prefix (which should be service root)
install(TARGETS service                                 DESTINATION ${CMAKE_INSTALL_PREFIX})
install(FILES ${CMAKE_CURRENT_BINARY_DIR}/${BINARY}.img DESTINATION ${CMAKE_INSTALL_PREFIX})