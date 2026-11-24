#!/bin/bash
# PLACEHOLDER: generating "changes" documents (what changed between a released
# version of the specification, e.g. 1.3.0, and the version in development,
# e.g. 1.3.1-dev) is not implemented yet. To be designed once the 1.3.0 Antora
# release is out.
#
# With every version on its own v* branch, the changes can be derived from git,
# e.g.  git diff v1.3.0 v1.3.1-dev -- docs/mzidentml/modules/developers/partials/
#
# The specification sources are docs/mzidentml/modules/developers/partials/
# (mzidentml.adoc, model-in-xml-schema.adoc, crosslinking_ext.adoc). They are
# edited in place: nothing needs regenerating after editing them.

echo "scripts/gen-docs.sh: generating changes documents is not implemented yet; see the comment in this script." >&2
exit 1
