# AWFY Json port

Source: https://github.com/smarr/are-we-fast-yet
Revision: 74306fec151070fd07157cefeacf19e7e0bcdc89

`upstream/` retains the SOM Json sources (including the fixture and EclipseSource MIT notices), repository license/authors, and matched Python comparator with its dependencies. The Harding parser is recursive and constructs the ported JsonValue hierarchy, not native JSON values.

SOM strings become Harding strings; concatenation uses `&`. The parser retains its one-based cursor for diagnostics, translating string slices/indexing at the boundary. JsonArray's public indexing is zero-based. Vector storage maps to growable Array. HashIndexTable's nonnegative power-of-two masks map exactly to modulo 256/32 (Harding `&` is concatenation, not integer bit-and). Literal singleton class slots map to globals. JsonString gains an accessor for assertions. Upstream limitations are retained, including unsupported Unicode escapes, incomplete object hash collision lookup, and no control-character validation.

Run `python3 tests/test_awfy_json.py` from the repository root. Build products and logs stay under `build/awfy-json`.
