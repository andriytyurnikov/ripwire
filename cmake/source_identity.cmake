# The PRODUCER IDENTITY of a build: SHA-256 over the sorted (relative path, SHA-256) of every file under
# src/ and queries/ — the program text and the tags queries it embeds. src/quality.h folds it into the qsnap
# and qbody cache keys and blob header, so a Snapshot one build computed is never served to a build whose
# sources differ (a resolver change moves the dead set; nothing else in the key moved with it). Derived per
# build rather than bumped by hand, because a hand-bumped version is exactly what this cache has missed before.
# See the note at src/quality.h producerIdentity.
#
# Content, not git: a dirty tree, an untracked new header and a tarball with no .git all get the identity of
# what was actually compiled. Path components starting with '.' are skipped (.DS_Store, editor swap files);
# any other stray file only renames the cache, which costs a cold HEAD snapshot and never a wrong answer.
# Out of scope, and why that is sound: third_party/ (vendored grammars move kParserVer by the extraction rule,
# and kParserVer is already in the key) and the compiler (output must not depend on it — the determinism
# contract).
#
#   cmake -DRIPWIRE_SOURCE_DIR=<tree> -P cmake/source_identity.cmake
#       prints `-- source_identity=<64 hex>` — what test/qsnapproducercheck.sh compares a blob against
#   cmake -DRIPWIRE_SOURCE_DIR=<tree> -DRIPWIRE_OUTPUT=<file.cpp> -P cmake/source_identity.cmake
#       writes the one definition src/sourceidentity.h declares; copy_if_different, so an unchanged
#       tree recompiles nothing
if(NOT RIPWIRE_SOURCE_DIR)
  message(FATAL_ERROR "source_identity.cmake: RIPWIRE_SOURCE_DIR is required")
endif()

file(GLOB_RECURSE _files LIST_DIRECTORIES false RELATIVE "${RIPWIRE_SOURCE_DIR}"
  "${RIPWIRE_SOURCE_DIR}/src/*"
  "${RIPWIRE_SOURCE_DIR}/queries/*")
list(FILTER _files EXCLUDE REGEX "(^|/)\\.")
list(SORT _files)
list(LENGTH _files _count)
if(_count EQUAL 0)
  message(FATAL_ERROR "source_identity.cmake: no files under ${RIPWIRE_SOURCE_DIR}/src or queries — refusing to stamp an empty identity")
endif()

set(_manifest "")
foreach(_f IN LISTS _files)
  file(SHA256 "${RIPWIRE_SOURCE_DIR}/${_f}" _h)
  string(APPEND _manifest "${_f}\t${_h}\n")
endforeach()
string(SHA256 _identity "${_manifest}")

if(NOT RIPWIRE_OUTPUT)
  message(STATUS "source_identity=${_identity}")
  return()
endif()

set(_body "// Generated at build time by cmake/source_identity.cmake — do not edit.\n// ${_count} files under src/ and queries/.\nnamespace rw\n{\nextern const char kRipwireSourceIdentity[];\nconst char kRipwireSourceIdentity[] = \"${_identity}\";\n} // namespace rw\n")
# A tmp name of its own, next to the output (same filesystem for the copy): two builds of one tree running this at
# once (separate `cmake --build --config X` invocations) shared "<output>.tmp", so one could REMOVE the other's tmp
# before its copy, or copy it half-written. string(RANDOM) is seeded per process. Every path below removes the tmp.
string(RANDOM LENGTH 12 _tmp_tag)
set(_tmp "${RIPWIRE_OUTPUT}.${_tmp_tag}.tmp")
file(WRITE "${_tmp}" "${_body}")
execute_process(COMMAND "${CMAKE_COMMAND}" -E copy_if_different "${_tmp}" "${RIPWIRE_OUTPUT}" RESULT_VARIABLE _copy_rc)
file(REMOVE "${_tmp}")
if(NOT _copy_rc EQUAL 0)
  message(FATAL_ERROR "could not write ${RIPWIRE_OUTPUT}")
endif()
