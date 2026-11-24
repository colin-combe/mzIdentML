# Specification sources have moved

The AsciiDoc sources of the mzIdentML 1.3 specification and the crosslinking
extension are now in
[`docs/mzidentml/modules/developers/partials/`](../../../docs/mzidentml/modules/developers/partials/)
(`mzidentml.adoc`, `model-in-xml-schema.adoc`, `crosslinking_ext.adoc`), and
their figures in
[`docs/mzidentml/modules/developers/images/img/`](../../../docs/mzidentml/modules/developers/images/img/).
The documentation site and the PDF/DOCX downloads are both built from there;
see `build-spec-docs.sh` in the repository root.

This folder keeps the frozen copies of released text that `gen-docs.sh` compares
the current sources against, and the reports it generates.
