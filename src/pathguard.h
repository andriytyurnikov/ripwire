#pragma once

// pathguard.h — THE ONE RULE for "this write destination is a symlink, so do not write through it".
//
// WHY IT IS ITS OWN HEADER. The rule was born at the MCP edit seam (mcpedit.h, A4-F14) because that is
// where following a link loses an agent's edit. It was never given to the SIDECAR writers, and that gap was
// a reported vulnerability (CWE-59, link following): `.ripwire_quality_baseline` (quality::writeBaseline),
// `.ripwire_notes` (notes::writeNotes) and `.ripwire_arch_baseline` (archWriteBaseline) each opened a FIXED
// name with a truncating open — ofstream( path, trunc ) twice, fopen( path, "w" ) once — and a truncating
// open resolves its final path component through the filesystem's symlink layer. A repository carrying a
// symlink at one of those names turned the tool's own write into an arbitrary-file truncate anywhere the
// invoking user could write. Reproduced on the shipped binary: a victim file holding `important user data`
// came back holding baseline content, and the sidecar was still a symlink afterwards.
//
// The fix for a rule that exists in one place and is missing in three is not a fourth copy of it, so the
// PREDICATE moved here — where a sidecar writer can reach it without including a JSON-RPC server, and where
// a fifth writer joins the rule instead of re-deriving it.
//
// WHY THE PREDICATE IS SHARED BUT THE REFUSAL TEXT IS NOT ONE SENTENCE. The two seams fail in OPPOSITE
// directions, and a single message would have to be wrong about one of them:
//
//   - mcpedit's atomicWrite is tmp+rename. A rename REPLACES the link entry with a regular file and leaves
//     the real target untouched — the edit silently goes nowhere. Data-losing, not a write primitive.
//   - the three sidecar writers truncate in place. The link is FOLLOWED and its target destroyed, while the
//     link entry survives — an arbitrary write.
//
// So `isSymlink` is one spelling (lstat, never stat: inspect the LINK, not what it points at) and each
// caller says what would actually have happened to the user's file. Claiming the wrong mechanism in a
// security refusal is the kind of dishonesty in output the project's non-negotiables rule out; a shared
// sentence that fits neither seam would be exactly that.
//
// DELIVERY differs too, and deliberately: an MCP verb refuses into its JSON-RPC error object, a CLI sidecar
// writer refuses onto stderr. refuseSymlinkWrite below is the stderr half, used by the three sidecar
// writers; mcpedit takes the predicate alone and keeps its own error payload.
//
// It carries no index/graph dependency on purpose — the emitter and the degrade macro are the whole of it —
// so it stays includable from any layer, which is the property that let the rule be missing in the first
// place. It is NOT under src/infra/: that layer is vendored into a sibling repo and may not name this
// project (test/infraportcheck.sh rule (C)), and every sentence below has to.
//
// Gated by test/sidecarsymlinkcheck.sh, whose three symlink arms were observed RED before this header
// existed.

#include "infra/emit.h"   // rw::emitTo — the refusal goes to stderr through THE emitter, not fprintf

#include <sys/stat.h>     // ::lstat + S_ISLNK — the whole mechanism
#include <string>
#include <string_view>

namespace rw::pathguard
{

// Is the LAST path component itself a symlink? lstat, not stat: stat() answers for the target and would
// report `false` for precisely the case this exists to catch. A path that does not exist, or that cannot be
// lstat'd at all, is NOT a symlink — an absent destination is the normal first-run case for every sidecar,
// and refusing it would break the tool for everyone to defend against nobody.
inline bool isSymlink( const std::string& path ) noexcept
{
    struct stat linkSt{};
    return ::lstat( path.c_str(), &linkSt ) == 0 && S_ISLNK( linkSt.st_mode );
}

// The sidecar writers' guard: true means REFUSED (and the user has been told on stderr), false means the
// destination is safe to open. Written as a predicate the caller branches on rather than a void that also
// decides, so the caller keeps its own return value, its own exit path and its own DEGRADED_PATH_ALERT —
// the alert is per-site on purpose, because "logged once per site" would otherwise silence the second and
// third writer inside one long-lived process.
//
// `what` names the sidecar in the user's words ("the quality baseline sidecar"), not the code's.
//
// LOUDLY, NOT SILENTLY. A skipped write that says nothing leaves the user believing a sidecar exists that
// does not — a committed baseline that is actually absent reads as "no debt", which is a worse answer than
// an error. So this always emits, and every caller turns it into a non-zero exit.
inline bool refuseSymlinkWrite( std::string_view what, const std::string& path )
{
    if( !isSymlink( path ) )
    {
        return false;
    }
    rw::emitTo( stderr,
                "ripwire: refusing to write {} at '{}': that path is a symlink, and writing through it would follow the link and\n"
                "  overwrite whatever it points at — outside this tree, if that is where it leads — while leaving the link itself in place.\n"
                "  Nothing was written. Remove the symlink (or replace it with a real file) and re-run.\n",
                what, path );
    return true;
}

} // namespace rw::pathguard
