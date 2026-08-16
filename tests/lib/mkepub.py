#!/usr/bin/env python3
"""Build a Standard-Ebooks-shaped epub for the test suite.

Real zips, because standardebooks-dl reads them with the real unzip: a fixture
that only pretends to be an epub would test the fixture and not the script.

    mkepub.py OUT --slug the-slug --title T --author-fileas "Last, First"

Everything else is a knob for one specific edge the suite has to cover: where
the OPF sits inside the zip, how the cover-image item is spelled, whether the
Standard Ebooks identifier is there at all, and whether the file is a valid zip
in the first place.
"""

import argparse
import zipfile

CONTAINER = """<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="{opf}" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
"""

OPF = """<?xml version="1.0" encoding="utf-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="uid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    {identifier}
    <dc:title id="title">{title}</dc:title>
    <meta property="file-as" refines="#title">{title}</meta>
    <dc:creator id="author">{author_display}</dc:creator>
    <meta property="file-as" refines="#author">{author_fileas}</meta>
  </metadata>
  <manifest>
    <item href="text/body.xhtml" id="body.xhtml" media-type="application/xhtml+xml"/>
    {cover_item}
  </manifest>
  <spine><itemref idref="body.xhtml"/></spine>
</package>
"""


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("out")
    p.add_argument("--slug", default="author/title")
    p.add_argument("--title", default="A Title")
    p.add_argument("--author-fileas", default="Last, First")
    p.add_argument("--author-display", default="First Last")
    # The OPF is wherever container.xml says it is; both a root-level and a
    # subdirectory layout occur in the wild, and the cover href is relative to
    # whichever it turns out to be.
    p.add_argument("--opf-path", default="epub/content.opf")
    p.add_argument("--cover-href", default="images/cover.jpg")
    # The href as written *in the OPF*, when it differs from the real zip entry
    # (an &amp; that has to be unescaped before it will match anything).
    p.add_argument("--cover-href-xml", default=None)
    p.add_argument("--cover-bytes", type=int, default=1024)
    p.add_argument("--properties", default="cover-image")
    p.add_argument("--no-cover-item", action="store_true")
    p.add_argument("--no-identifier", action="store_true")
    p.add_argument("--corrupt", action="store_true")
    args = p.parse_args()

    if args.corrupt:
        with open(args.out, "wb") as fh:
            fh.write(b"PK\x03\x04 this is not really a zip file at all")
        return

    href_xml = args.cover_href_xml or args.cover_href
    cover_item = (
        ""
        if args.no_cover_item
        else '<item href="%s" id="cover.jpg" media-type="image/jpeg" properties="%s"/>'
        % (href_xml, args.properties)
    )
    identifier = (
        ""
        if args.no_identifier
        else "<dc:identifier id=\"uid\">https://standardebooks.org/ebooks/%s</dc:identifier>"
        % args.slug
    )
    opf = OPF.format(
        identifier=identifier,
        title=args.title,
        author_display=args.author_display,
        author_fileas=args.author_fileas,
        cover_item=cover_item,
    )

    opf_dir = args.opf_path.rsplit("/", 1)[0] if "/" in args.opf_path else ""
    cover_zip_path = (opf_dir + "/" if opf_dir else "") + args.cover_href

    with zipfile.ZipFile(args.out, "w", zipfile.ZIP_DEFLATED) as z:
        # mimetype first and stored, the way the spec asks and every real SE
        # epub does it.
        z.writestr(zipfile.ZipInfo("mimetype"), "application/epub+zip",
                   compress_type=zipfile.ZIP_STORED)
        z.writestr("META-INF/container.xml", CONTAINER.format(opf=args.opf_path))
        z.writestr(args.opf_path, opf)
        z.writestr((opf_dir + "/" if opf_dir else "") + "text/body.xhtml",
                   "<html><body><p>text</p></body></html>")
        if not args.no_cover_item:
            # cover-bytes 0 means a genuinely empty entry: a download that was
            # cut off, which must count as missing rather than as a cover.
            data = b"" if args.cover_bytes == 0 else (
                b"\xff\xd8\xff\xe0" + b"j" * max(0, args.cover_bytes - 4))
            z.writestr(cover_zip_path, data)


if __name__ == "__main__":
    main()
