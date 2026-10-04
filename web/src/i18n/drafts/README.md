# Maintained machine-drafted fallbacks

Locale JSON files contain only in-use keys without a usable legacy, server, native or exact source-gap value.
They were drafted during implementation, without a translation API, and are not native-speaker approved.
Keep usable originals; correct draft wording here after language review. English-identical international labels
and product names are allowed, and provenance reports them separately from distinct translated wording.

The catalog appends inherited in-use English keys after web keys and includes implicit `_one` variants.
`english.json` pins the wording reviewed for these drafts. When production English changes, review the affected
translations before updating that snapshot. Do not blindly regenerate drafts from English to increase coverage.

Run `python3 web/scripts/import-web-gap-sources.py` for allowlisted exact source copies, then
`npm --prefix web run i18n:validate` for actual-hole/stale-key, placeholder-multiset, newline and source-hash checks.
The validator updates `provenance.json` with hashes and honest carried/copy/draft counts. These checks establish
structural coverage, not linguistic or assistive-technology acceptance. Connection/OIDC page titles, client
error copy and initial server-rendered English remain outside this table increment.

Administration and setup additions in `../pending-english.json` have English wording only.
They use the runtime's English fallback rather than duplicated locale drafts. Validation reports them separately
as `pendingEnglishFallbacks`; they are not translated coverage. Add reviewed locale wording before removing a
key from this registry. Leafwake is the independent product name in every locale. Existing translations remain.
The initial public release is en-GB. Physical assistive-technology and native-speaker acceptance remain distinct
from catalog structure, browser keyboard, responsive layout and reduced-motion checks.
