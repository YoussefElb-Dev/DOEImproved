# Transcript import

Gradly imports text-layer PDF transcripts entirely on the device. A selected
file is read into memory while the picker still owns access to it, then moves
through these awaited stages:

`picker → file handle → bytes → PDF text → normalize → validate → review → persist → re-render`

Every boundary writes a visible pipeline log and a debug log. The save button
does not exist until parsing and validation have completed. Storage errors are
raised as `TranscriptStorageException` and shown to the student.

The earlier app had no direct transcript picker. Its profile-photo picker only
copied an image, and DOE document downloads took a separate path through
`ArchiveStore`, where broad catches could turn a failed write into an empty
result. The transcript flow now requests picker bytes immediately, falls back
to a copied local path, retains those bytes through review, and writes the JSON
and original PDF with a temporary file and recovery backup.

## Versioned schema

`NormalizedTranscript` currently uses schema version 3. It contains:

- source fingerprint, source filename/document ID, import date, and raw text;
- student name, ID, date of birth, address, and grade level;
- institution identity/address, issue date, and official status;
- program, degree sought, majors, minors, concentrations, catalog year, and
  required credits;
- semester/quarter credit system, repeat policy, and the printed grading
  legend;
- terms with dates, GPA or printed percent average, totals,
  standing, honors/probation flags, and courses;
- course identifiers, credits, grades/points, GPA inclusion, source school,
  and status/type flags;
- cumulative totals, the printed cumulative percent average, and
  institutional, major, overall, and cumulative GPAs;
- transfer blocks and degrees with conferral dates and Latin honors;
- warnings and field-level confidence scores.

Nullable source fields stay null when the transcript does not print them.
`TranscriptSchemaMigrator` upgrades records one version at a time. Unknown
newer versions fail visibly rather than being misread.

## Persistence and merging

Files live under the app's private Documents/transcripts directory. A SHA-256
fingerprint recognizes the same source file. Records with the same student ID
and institution merge in place by term and by subject + course number +
section. Another institution remains a separate record and appears in the
combined transcript view. The normalized record keeps the raw extracted text,
and the original PDF is retained beside it for later re-parsing. JSON and CSV
exports are generated from the reviewed record.

## GPA rules

The GPA audit uses printed quality points first, then printed course grade
points, then the transcript's legend. A standard 4.0 mapping is only a labelled
fallback. Pass/fail, audit, withdrawn, incomplete, in-progress, transfer, and
replaced attempts do not enter GPA math. A repeat is removed only when the
record explicitly marks the replaced attempt. The displayed stated-versus-
computed difference is the parse accuracy signal.

The 5.0, 4.3, percentage, and letter displays are estimates because there is no
universal conversion between institutional scales. Quarter credits convert to
semester credits at two thirds. The what-if calculator solves the weighted GPA
equation against remaining GPA credits.

## Heuristics and limits

PDF extraction supports generated PDFs with embedded text. Image-only scans,
encrypted PDFs, and custom subset-font encodings are rejected with a specific
error; OCR is not currently bundled.

Transcript layouts are not standardized. Labelled fields are high confidence.
Institution headings, course column positions, lone trailing credit values,
section identifiers, term headings, and unlabelled legends are heuristic and
may need correction in review. Multi-column PDFs whose drawing order differs
from visual order can produce joined or reordered rows. Repeat policies are
never inferred from a repeated course alone. Weighted GPA conversions cannot
reconstruct a school's weighting policy unless the transcript prints the
actual points or legend.

NYC DOE high-school transcripts have a dedicated parser for DBN-prefixed rows,
joined course-code/title text, `actual/earned` credit pairs, numbered terms,
single-star not-averaged marks, and double-star weighted courses. The official
NYC cumulative and term percentages remain percent values; estimated 4.0, 4.3,
5.0, and letter conversions are displayed separately and never overwrite them.

The DOE document page uses `#` links that submit a hidden form instead of
linking directly to a PDF. Gradly captures authenticated form, fetch, XHR,
popup, and blob responses inside the WebView and transfers verified PDF bytes
to local storage in chunks. It does not rely on re-fetching the visible `#`
URL outside the WebView.
