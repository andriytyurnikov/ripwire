#pragma once

// pathguard.h — THE ONE RULE for "this sidecar name is a symlink, so do not write OR read through it", and
// the two atomic opens that ENFORCE it rather than merely describing it (round 3 added the read; see below).
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
// ── ROUND 2: THE FIRST FIX WAS CHECK-THEN-OPEN, AND THAT IS A SECOND DEFECT (CWE-367, TOCTOU) ─────────
//
// The first fix put an lstat/S_ISLNK REFUSAL immediately in front of each writer's unchanged truncating
// open. It closed the reported attack and was honest about its own limit, and an external reviewer then
// flagged the limit as its own finding, correctly. The guard was ADVISORY: lstat(2) answered a question
// about the destination at one instant, open(2) re-resolved the same path at a later one, and anything that
// replaced the entry in between made the write follow a link after all. A guard the code then relies on for
// safety is not a guard; it is a description that happened to be true when it was read.
//
// The stated reason for stopping there was that std::ofstream cannot express O_NOFOLLOW portably. True of
// ofstream, and not true of the problem: the writers do not need ofstream, they need a descriptor. So the
// check and the create are now ONE syscall, and it is the only one a writer makes:
//
//     ::open( path, O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW, 0666 )
//
// O_NOFOLLOW makes the KERNEL refuse a final component that is a symlink, at the instant of resolution.
// There is no window because there is no second resolution — whatever the entry is when the kernel looks
// is what the kernel acts on. POSIX, and present on both targets (macOS, Linux). MSVC is explicitly not a
// target for this project, so there is no portability scaffolding here and none is wanted.
//
// WHERE lstat SURVIVES, AND WHY THAT IS NOT A RELAPSE. isSymlink stays, for two callers that are not the
// sidecar guard:
//
//   - mcpedit, whose tmp+rename publish genuinely wants to KNOW (it refuses into a JSON-RPC error object
//     and never opens the destination at all, so there is nothing for an atomic open to be atomic with);
//   - openNoFollowTruncate itself, AFTER a failed open, to decide which sentence ELOOP has earned. ELOOP
//     is also what a symlink LOOP in an earlier directory component returns, and printing "that path is a
//     symlink" at a path whose last component is a directory would be a false security claim rather than
//     a diagnosis. That lstat is racy too, and it does not matter in the slightest: it cannot decide
//     whether to write. The worst a lost race can do there is pick the less specific of two refusals.
//
// The distinction is the whole point of the round: a check that GATES an open is a vulnerability; a check
// that WORDS an error is a message.
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
// sentence that fits neither seam would be exactly that. The same rule is why an open that failed for some
// OTHER reason — a directory at the name, a read-only tree, a full disk — reports its own errno instead of
// being folded into the symlink sentence, which would turn every failure into a security event.
//
// DELIVERY differs too, and deliberately: an MCP verb refuses into its JSON-RPC error object, a CLI sidecar
// writer refuses onto stderr. openNoFollowTruncate below is the stderr half, used by the three sidecar
// writers; mcpedit takes the predicate alone and keeps its own error payload.
//
// THE MODE, 0666, IS NOT A CHOICE — it is what std::ofstream( path, trunc ) and std::fopen( path, "w" )
// both request, and the process umask narrows it exactly as before (0644 under the usual 022). Naming a
// mode by hand is the one thing moving from a stream to a descriptor forces, so it is measured rather than
// asserted: test/sidecarsymlinkcheck.sh's (g) arms create each sidecar under `umask 000` and require 0666,
// which is the only umask under which a wrong 0644 is visible at all.
//
// ── ROUND 3: THE READERS OF THE SAME NAMES REFUSE A LINK TOO — A DECISION, NOT A DEFAULT ─────────────
//
// Rounds 1-2 guarded the writes and left every reader of these three names following a link:
// notes::readNotes, quality::readBaseline / readBaselineHeadSha / readBaselineAbsorbed, archReadBaseline,
// and a bare stream the arch verb opened only to learn whether the sidecar existed. So a link at one of the
// names still decided which file those readers opened, inside the tree or out of it, and its lines were read
// as sidecar records.
//
// No privilege is crossed; the user could read those files anyway. The boundary is the one the crawl already
// holds (ingest.h, withinCanonicalRoot): repository content does not choose which of the user's files the
// tool reads. Three answers were on the table, and the choice is pinned by the round-3 arms of
// test/sidecarsymlinkcheck.sh rather than left to whoever next edits a reader:
//
//   (a) Leave the readers following. REJECTED: a link would keep deciding what is read at three fixed names,
//       right beside a crawl that no longer lets one.
//   (c) Refuse only a link that leaves the crawl root, which is the crawl's own rule. REJECTED, three ways:
//       - It does not keep the setup that argues for it. A sidecar symlinked into a SHARED config directory
//         points outside the tree, and (c) refuses that as well. What (c) keeps beyond (b) is a link to
//         another file INSIDE the tree — which the writers already refuse, so it is readable and never
//         again updatable.
//       - It cannot be one syscall. "Where does the link lead" is realpath() followed by an open: the
//         check-then-open shape round 2 removed from the writers, or a descriptor-then-verify dance to close
//         that same race a second time.
//       - It has no single anchor. The arch baseline resolves against the process CWD (archBaselinePath),
//         not the crawl root, so "leaves the root" is not even defined for one of the three.
//   (b) Refuse a link on READ exactly as on write: O_NOFOLLOW at the open. CHOSEN. One sentence covers every
//       site — a sidecar is a regular file at its fixed name, read or written — and the kernel enforces it
//       in the very syscall that would otherwise have followed the link.
//
// The crawl follows an in-tree link and these readers do not, and that is not an inconsistency. A source
// tree's links are the user's content; a sidecar is this tool's own state file, which it never creates as
// a link and, since round 1, will not write through one. git draws the same line: since 2.32 it opens the
// in-tree .gitattributes, .gitignore and .mailmap with O_NOFOLLOW.
//
// MIGRATION. A repository that symlinks one of these sidecars on purpose now gets a stderr refusal on every
// read and no sidecar in force: no notes surface, quality-delta reports baseline="git-HEAD (symlinked
// sidecar refused)" and compares against HEAD, and the arch verb reports every violation as new. Replace
// the link with a regular copy of its target — copy the target to a temporary name beside the link, then
// mv that over the link — and if it must track a shared original, copy it in as a CI step instead.
//
// NOT COVERED, and why:
//   - `.ripwire_quality_acks` (readAckRecords). Its writer publishes by tmp+rename, which REPLACES a link
//     instead of following it, so what a refused read should make that writer do belongs to the lane that
//     guards the writer. The reader moves with it.
//   - `.ripwire_config` (readRegisterMacrosConfig). User-authored, never written by the tool, and the one
//     of these names where a link into a shared directory is the ordinary setup. Whether it takes this rule
//     is its own decision.
//   - An in-document disclosure where the document has no channel for one. The refusal reaches stderr from
//     every surface, and the document only where a marker already tells "no sidecar" from "a sidecar not
//     used" (quality-delta, CLI and MCP). A refused note is simply absent from --for, --expand and the MCP
//     verbs, and an MCP client never sees the server's stderr.
//   - Directory components. O_NOFOLLOW constrains the final component only, exactly as for the writes.
//
// Each sidecar keeps ONE read seam (readNotesSidecar / readBaselineSidecar / readArchBaselineSidecar) that
// calls readWholeFileNoFollow below and carries its own DEGRADED_PATH_ALERT, for the same once-per-site
// reason the write seams keep theirs.
//
// It carries no index/graph dependency on purpose — the emitter and the degrade macro are the whole of it —
// so it stays includable from any layer, which is the property that let the rule be missing in the first
// place. It is NOT under src/infra/: that layer is vendored into a sibling repo and may not name this
// project (test/infraportcheck.sh rule (C)), and every sentence below has to.
//
// Gated by test/sidecarsymlinkcheck.sh, whose three symlink arms were observed RED before this header
// existed, whose (e)/(f) mechanism arms were observed RED before the open below replaced the check, and
// whose round-3 read arms were observed RED against the round-2 binary before the read below existed.

#include "infra/emit.h"   // rw::emitTo — the refusal goes to stderr through THE emitter, not fprintf

#include <fcntl.h>        // ::open + O_NOFOLLOW — the whole mechanism, in one syscall
#include <sys/stat.h>     // ::lstat + S_ISLNK — mcpedit's predicate, and the post-ELOOP wording decision
#include <unistd.h>       // ::write / ::close — the descriptor the writers hold instead of a stream
#include <cerrno>
#include <cstddef>
#include <cstring>        // std::strerror — an honest reason for a failure that is not a link
#include <string>
#include <string_view>
#include <sys/types.h>    // ssize_t

namespace rw::pathguard
{

// Is the LAST path component itself a symlink? lstat, not stat: stat() answers for the target and would
// report `false` for precisely the case this exists to catch. A path that does not exist, or that cannot be
// lstat'd at all, is NOT a symlink — an absent destination is the normal first-run case for every sidecar,
// and refusing it would break the tool for everyone to defend against nobody.
//
// THIS IS NOT A WRITE GUARD and must never be used as one again: between its answer and any subsequent open
// the entry can change, which is the CWE-367 finding this header's round 2 closes. It answers a question
// (mcpedit, which never opens the destination) and it words an error (openNoFollowTruncate, after the fact).
inline bool isSymlink( const std::string& path ) noexcept
{
    struct stat linkSt{};
    return ::lstat( path.c_str(), &linkSt ) == 0 && S_ISLNK( linkSt.st_mode );
}

// What the atomic open produced: a descriptor, or the errno that explains why there is none. Both are
// returned rather than left in `errno`, because the refusal is emitted before the caller looks and an
// emitter is entitled to clobber errno on its way to stderr.
//
// `err == ELOOP` is the link case, and it is the one the caller re-words into its own site-specific
// DEGRADED_PATH_ALERT — see the three sidecar writers, which each keep the alert text they have always had.
struct OpenedFile
{
    int fd  = -1;
    int err = 0;
};

// Create-or-truncate `path` for writing WITHOUT following a symlink at the final component, and tell the
// user on stderr if that is refused. Returns a descriptor >= 0, or fd == -1 with the errno that failed.
//
// `what` names the sidecar in the user's words ("the quality baseline sidecar"), not the code's.
//
// LOUDLY, NOT SILENTLY. A skipped write that says nothing leaves the user believing a sidecar exists that
// does not — a committed baseline that is actually absent reads as "no debt", which is a worse answer than
// an error. So this always emits on failure, and every caller turns it into a non-zero exit.
//
// O_NOFOLLOW constrains the FINAL component only; an intermediate symlinked directory is still traversed.
// That is the same reach the lstat check had, so nothing regressed with the change — and widening it would
// mean refusing every repository that lives under a symlinked path, which is most of them.
inline OpenedFile openNoFollowTruncate( std::string_view what, const std::string& path )
{
    const int fd = ::open( path.c_str(), O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW, 0666 );
    if( fd >= 0 )
    {
        return { fd, 0 };
    }
    const int err = errno;

    if( err == ELOOP && isSymlink( path ) )
    {
        rw::emitTo( stderr,
                    "ripwire: refusing to write {} at '{}': that path is a symlink, and writing through it would follow the link and\n"
                    "  overwrite whatever it points at — outside this tree, if that is where it leads — while leaving the link itself in place.\n"
                    "  Nothing was written. Remove the symlink (or replace it with a real file) and re-run.\n",
                    what, path );
    }
    else if( err == ELOOP )
    {
        // ELOOP without a link at the final component: a symlink loop somewhere earlier in the path. Still a
        // refusal, still nothing written — but saying "that path is a symlink" here would be a claim about a
        // component that is not one.
        rw::emitTo( stderr,
                    "ripwire: refusing to write {} at '{}': the path could not be resolved without following a symlink loop\n"
                    "  in one of its directory components (ELOOP). Nothing was written.\n",
                    what, path );
    }
    else
    {
        // Not a link question at all — a directory at the name, a read-only tree, a full disk. Reported as
        // what it is; folding it into the symlink sentence would turn every failed write into a security
        // event and teach the user to ignore the one that is.
        rw::emitTo( stderr,
                    "ripwire: could not open {} at '{}' for writing: {}. Nothing was written.\n",
                    what, path, std::strerror( err ) );
    }
    return { -1, err };
}

// Write every byte of `bytes` to `fd`, then close it — the descriptor is consumed either way. Returns false
// if any byte did not land or the close failed, which the callers turn into their "could not write" answer.
//
// A short write is retried (a signal can truncate one), EINTR is retried, and anything else is a failure.
// writeBaseline used to `return true` regardless of whether the bytes reached the disk and now returns this;
// writeNotes already answered for its stream (`return bool( f )`) and keeps that contract through the
// descriptor. Either way a full disk stops being reported as a written sidecar.
inline bool writeAllAndClose( int fd, std::string_view bytes ) noexcept
{
    bool        wrote = true;
    std::size_t off   = 0;
    while( off < bytes.size() )
    {
        const ssize_t n = ::write( fd, bytes.data() + off, bytes.size() - off );
        if( n > 0 )
        {
            off += static_cast<std::size_t>( n );
            continue;
        }
        if( n < 0 && errno == EINTR )
        {
            continue;
        }
        wrote = false;
        break;
    }
    if( ::close( fd ) != 0 )
    {
        wrote = false;
    }
    return wrote;
}

// ── the read half (round 3) ───────────────────────────────────────────────────────────────────────────

// What the no-follow read produced. `opened` is the OPEN, not the content: a directory at the name opens and
// then fails its first read, exactly as the std::ifstream this replaces did, so a caller that tells "a
// sidecar is there" from "no sidecar" (readBaseline's `present`, the arch verb's baseline-in-force) keeps
// telling them apart the way it always has.
struct NoFollowRead
{
    std::string bytes;             // every byte read before EOF or the first read error
    bool        opened  = false;   // the open succeeded: something that is not a symlink sits at the name
    bool        refused = false;   // the open failed with ELOOP — nothing was followed, and stderr says why
    int         err     = 0;       // errno of the open or read that failed; 0 when neither did
};

// Read all of `path` WITHOUT following a symlink at the final component — openNoFollowTruncate's read twin:
// the same O_NOFOLLOW, the same single syscall with no lstat in front of it to race, and the same rule that a
// refusal is loud.
//
// ONLY THE REFUSAL IS LOUD. An absent file is every sidecar's first-run case and says nothing, and any other
// open or read failure stays exactly as silent as the stream this replaces — the callers already read those as
// "no sidecar", and making them loud is a behaviour change with questions of its own, not a rider on this
// one. A read refused over a link is different in kind: the file is RIGHT THERE, and a caller that went quiet
// about it would leave the user believing there is no sidecar at all.
//
// `what` names the sidecar in the user's words, as for the write.
inline NoFollowRead readWholeFileNoFollow( std::string_view what, const std::string& path )
{
    NoFollowRead result;
    const int    fd = ::open( path.c_str(), O_RDONLY | O_NOFOLLOW );
    if( fd < 0 )
    {
        result.err = errno;
        if( result.err != ELOOP )
        {
            return result;
        }
        result.refused = true;
        if( isSymlink( path ) )
        {
            rw::emitTo( stderr,
                        "ripwire: refusing to read {} at '{}': that path is a symlink, and reading through it would open whatever it points at\n"
                        "  — outside this tree, if that is where it leads — and use its contents as {}. Nothing was read. A sidecar behind a\n"
                        "  symlink is refused on read exactly as on write: replace the link with a regular copy of its target (or remove it) and re-run.\n",
                        what, path, what );
        }
        else
        {
            // As for the write: ELOOP with no link at the final component is a loop in an earlier directory
            // component, and "that path is a symlink" would be a claim about a component that is not one.
            rw::emitTo( stderr,
                        "ripwire: refusing to read {} at '{}': the path could not be resolved without following a symlink loop\n"
                        "  in one of its directory components (ELOOP). Nothing was read.\n",
                        what, path );
        }
        return result;
    }

    result.opened = true;
    constexpr std::size_t kReadChunkBytes = 64 * 1024;   // how much one read(2) asks for, not how much is kept
    std::size_t           used            = 0;
    for( ;; )
    {
        result.bytes.resize( used + kReadChunkBytes );
        const ssize_t n = ::read( fd, result.bytes.data() + used, kReadChunkBytes );
        if( n > 0 )
        {
            used += static_cast<std::size_t>( n );
            continue;
        }
        if( n < 0 && errno == EINTR )
        {
            continue;
        }
        if( n < 0 )
        {
            result.err = errno;
        }
        break;
    }
    result.bytes.resize( used );
    ::close( fd );
    return result;
}

} // namespace rw::pathguard
