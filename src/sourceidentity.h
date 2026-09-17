#pragma once

// The PRODUCER IDENTITY of this build: 64 lowercase hex, the SHA-256 over every file under src/ and queries/
// that compiled into it (cmake/source_identity.cmake, run on every build beside the version stamp).
//
// Declared here and defined in ONE generated translation unit (build/generated/source_identity.cpp), not in a
// generated header: a header would put the identity in the include closure of every file that reads it, so any
// edit anywhere under src/ would recompile main.cpp and ingest.cpp both. As a definition in its own object the
// cost of a changed identity is one tiny compile and the link that was happening anyway. It lives in src/, not
// src/infra/: it names this build, and the infra layer is vendorable (test/infraportcheck.sh).
namespace rw
{
extern const char kRipwireSourceIdentity[];
} // namespace rw
