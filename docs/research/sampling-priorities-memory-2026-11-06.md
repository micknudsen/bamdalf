# Stable sampling priorities without a historical inventory

Research date: 2026-11-06. Primary-source inspection of the official samtools 1.25 manual and release source, pinned to commit `7162950d0988480faeddeb49f03520737e13a9c4`. No implementation or benchmark was performed.

This evidence informed Q70's stable, recomputable per-group priorities. [design.md](../design.md) is the authority for current selection and navigation behavior.

## Verified samtools precedent

The official `samtools view` manual describes `--subsample` as retaining a fraction of templates/pairs, applying the same sampling decision to their alignment records. `--subsample-seed` controls the chosen subset. Version 1.25 defaults to a header-derived `auto` seed; callers can specify an integer seed. [Official manual](https://www.htslib.org/doc/samtools-view.html), [pinned manual](https://github.com/samtools/samtools/blob/7162950d0988480faeddeb49f03520737e13a9c4/doc/samtools-view.1#L463-L490).

The implementation computes each record's sampling score directly from its QNAME and the effective seed: it hashes QNAME, XORs the seed, mixes the result, and compares the low 24 bits, scaled into `[0,1)`, with the requested fraction. That decision does not consult a map of previously encountered templates or depend on record encounter order. The same QNAME and effective seed reproduce the same score. Thus mates and supplementary records sharing QNAME receive the same sampling decision whenever they reach this step. Other filters and region selection can still exclude individual records. [Sampling and preceding filters](https://github.com/samtools/samtools/blob/7162950d0988480faeddeb49f03520737e13a9c4/sam_view.c#L152-L182).

This is fractional hash-threshold sampling, analogous to a Bernoulli decision per template. It does **not** select exactly `B` groups, sort priorities, or implement Bamdalf's accepted highest-priority selection. It demonstrates repeatable decisions without retaining decision history. Nonzero seeds are transformed once using `srand`/`rand`; this inspection does not establish identical results across arbitrary versions or platforms. [Seed preparation](https://github.com/samtools/samtools/blob/7162950d0988480faeddeb49f03520737e13a9c4/sam_view.c#L1382-L1410), [threshold rule](https://github.com/samtools/samtools/blob/7162950d0988480faeddeb49f03520737e13a9c4/sam_view.c#L179-L182).

## Design implication

Conceptually, compute:

`priority = keyedHash(openFileSessionSeed, stableGroupID)`

One session seed plus a stable identifier regenerates priorities after eviction, without historical priority storage or a whole-BAM prescan. The formula illustrates Q70; no particular hash or samtools algorithm is selected.

Selection still needs regional candidate processing and temporary state; removing a historical priority inventory does not remove alignment, candidate, cache, or row-layout state. Stable priorities also do not guarantee stable membership when the candidate set changes.

The exact hash, group identity/encoding, handling of missing or nonunique identifiers, ties, and selection data structures require design. An arbitrary hash does not establish ideal sampling uniformity. samtools provides a precedent for reproducible scores without history, not an implementation of Bamdalf's exact group cap or navigation contract.
