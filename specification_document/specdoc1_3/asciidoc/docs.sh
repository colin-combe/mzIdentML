#!/bin/bash
rm -R out/*
asciidoctor -d book --attribute="commit-hash=COMMITHASH" --attribute="build-date=BUILDDATE" -D out ext.adoc
asciidoctor-pdf -d book --attribute="commit-hash=COMMITHASH" --attribute="build-date=BUILDDATE" -D out ext.adoc
html2text out/ext.html > out/ext.txt
#asciidoctor -d book --attribute="commit-hash=COMMITHASH" --attribute="build-date=BUILDDATE" -D out main.adoc
#head -n 6669 main.adoc > out/main_trimmed.adoc
#asciidoctor-pdf -d book --trace --attribute="commit-hash=COMMITHASH" --attribute="build-date=BUILDDATE" -D out out/main_trimmed.adoc

