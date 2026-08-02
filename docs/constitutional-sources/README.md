# Constitutional Source Provenance

The alignment review identifies its input by content, not by a mutable web URL.

Pinned audit artifact:

- path: `docs/constitutional-sources/2024-09-24 Constitution.pdf`
- SHA-256: `A24E56A4077D3513D3467091BDD81EA445208D4F5D1CDE207BA87EFFE076BEE6`
- visible document date: 20 September 2025
- document reference: `MJ-LP-2024-05`
- visible status: `DRAFT Constitution of Liberland`
- pages: 25

The public [Congress discussion](https://forum.liberland.org/t/congress-discussion/363) links a
[Google document](https://docs.google.com/document/d/1Wz2xkM15LNWVgX_Wm7cdUAGzZimhpHVYQFq80EhtuFg/edit?tab=t.0), but both
the document revision and export serialization can change. On 2026-08-03, the PDF supplied by the project owner and
a fresh PDF export from that Google document were byte-for-byte identical at the pinned hash above. A fresh
plain-text export had SHA-256 `15576C6AB5AFA0785F29303163BDACB79587A0E9E7B8D6A19E6436DE6CF58AFE`.

The supplied filename predates the visible document date. It is intentionally preserved as provenance rather than
silently renamed. The PDF itself also labels its final two pages `24/23` and `25/23`; the file contains 25 complete,
readable pages, so this is recorded as an upstream footer-count inconsistency rather than repaired in the audit copy.

Verify the pinned bytes with:

```bash
bash scripts/verify-constitution-source.sh
```

Do not replace this file or update the expected hash merely to make verification pass. If the intended
constitutional baseline changes, preserve the new source as a separate immutable artifact, perform a new full
alignment review, and record its filename, hash, internal document metadata, review date, and resulting
code/document changes together.
