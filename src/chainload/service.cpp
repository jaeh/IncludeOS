// This file is a part of the IncludeOS unikernel - www.includeos.org
//
// Copyright 2017 Oslo and Akershus University College of Applied Sciences
// and Alfred Bratterud
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

#include <os>
#include <cstdint>
#include <util/elf_binary.hpp>

bool verb = true;
#define MYINFO(X,...) INFO("chainload", X, ##__VA_ARGS__)

extern "C" void hotswap(const char* base, int len, char* dest, void* start,
                        uintptr_t magic, uintptr_t bootinfo);

extern uintptr_t __multiboot_magic;
extern uintptr_t __multiboot_addr;

static void steal_commandline_from_module()
{
  auto* bootinfo = (multiboot_info_t*) __multiboot_addr;

  Expects (bootinfo->mods_count);
  auto* mod = (multiboot_module_t*) bootinfo->mods_addr;

  // Set command line param to mod param
  bootinfo->cmdline = mod->cmdline;
}

void Service::start(const std::string&)
{
  auto mods = OS::modules();
  MYINFO("%u-bit chainloader found %u modules",
        sizeof(void*) * 8, mods.size());

  if (mods.size() <= 0) {
    MYINFO("Nothing to do. Exiting.");
    exit(1);
  }
  multiboot_module_t binary = mods[0];

  Elf_binary<Elf64> elf (
      {(char*)binary.mod_start,
        (int)(binary.mod_end - binary.mod_start)});

  void* hotswap_addr = (void*)0x200000;
  extern char __hotswap_end;

  debug("Moving hotswap function (begin at %p end at %p) of size %i",
         &hotswap,  &__hotswap_end, &__hotswap_end - (char*)&hotswap);
  memcpy(hotswap_addr,(void*)&hotswap, &__hotswap_end - (char*)&hotswap );

  extern uintptr_t __multiboot_magic;
  extern uintptr_t __multiboot_addr;
  debug("Preparing for jump to %s. Multiboot magic: 0x%x, addr 0x%x",
         (char*)binary.cmdline, __multiboot_magic, __multiboot_addr);

  char* base  = (char*)binary.mod_start;
  int len = (int)(binary.mod_end - binary.mod_start);
  // FIXME: determine kernel base from ELF program header
  char* dest = (char*)0xA00000;
  void* start = (void*)elf.entry();

  MYINFO("Hotswapping with params: base: %p, len: %i, dest: %p, start: %p",
         base, len, dest, start);

  steal_commandline_from_module();

  asm("cli");
  ((decltype(&hotswap))hotswap_addr)(base, len, dest, start, __multiboot_magic, __multiboot_addr);

  panic("Should have jumped\n");
}