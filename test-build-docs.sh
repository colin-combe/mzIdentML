DOC_IN="$PWD/specification_document/specdoc1_3/asciidoc"
for f in mzidentml.adoc crosslinking_ext.adoc; do
  ./build-docs.sh -i "$DOC_IN" -o "$DOC_IN/output" \
    -c "$(git rev-parse --short HEAD)" \
    -d "$(date -u +'%Y-%m-%d %H:%M:%S UTC')" -f "$f" -r
done