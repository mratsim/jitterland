# For now only working on POSIX
# for windows use VirtualAlloc, VirtualProtect, VrtualFree

# See - https://github.com/nim-lang/Nim/blob/devel/lib/system/osalloc.nix
const PageSize = 4096

when not defined(posix):
  {.fatal: "Only POSIX systems are supported".}
else:
  type MemProt {.size: cint.sizeof.}= enum
    ProtNone  = 0 # Page cannot be accessed
    ProtRead  = 1 # Page can be read
    ProtWrite = 2 # Page can be written
    ProtExec  = 4 # Page can be executed

  when defined(osx) or defined(ios) or defined(bsd):
    # Note: MacOS and Iphone uses MAP_ANON instead of MAP_ANONYMOUS
    # They also define MAP_JIT= 0x0800
    type MemMap {.size: cint.sizeof.}= enum
      MapPrivate = 0x02       # Changes are private
      MapAnonymous = 0x1000   # Don't use a file
  elif defined(solaris):
    type MemMap {.size: cint.sizeof.}= enum
      MapPrivate = 0x02
      MapAnonymous = 0x100
  elif defined(haiku):
    type MemMap {.size: cint.sizeof.}= enum
      MapPrivate = 0x02
      MapAnonymous = 0x08
  else: # ASM-Generic
    # Note, Nim splits linux x86-64 and the rest
    # This is at least valid on Android ARM
    # unsure about MIPS and co
    type MemMap {.size: cint.sizeof.}= enum
      MapPrivate = 0x02
      MapAnonymous = 0x20

  when not defined(release):
    block:
      var DebugMapPrivate {.importc: "MAP_PRIVATE", header: "<sys/mman.h>".}: cint
      var DebugMapAnonymous {.importc: "MAP_ANONYMOUS", header: "<sys/mman.h>".}: cint

      assert ord(MapPrivate) == DebugMapPrivate, "Your CPU+OS platform is misconfigured"
      assert ord(MapAnonymous) == DebugMapAnonymous, "Your CPU+OS platform is misconfigured"
      echo "MemMapping constants success"


