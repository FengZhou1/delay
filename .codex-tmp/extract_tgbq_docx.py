from __future__ import annotations

import json
import sys
import zipfile
from pathlib import Path

from lxml import etree


W = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
NS = {"w": W}


def qn(local: str) -> str:
    return f"{{{W}}}{local}"


def text_with_changes(node: etree._Element) -> str:
    parts: list[str] = []

    def walk(el: etree._Element, mode: str | None = None) -> None:
        local = etree.QName(el).localname
        if local == "ins":
            mode = "ins"
        elif local == "del":
            mode = "del"
        elif local in {"t", "instrText"}:
            value = el.text or ""
            parts.append(f"{{+{value}+}}" if mode == "ins" else value)
        elif local == "delText":
            value = el.text or ""
            parts.append(f"[-{value}-]")
        elif local == "tab":
            parts.append("\t")
        elif local in {"br", "cr"}:
            parts.append("\n")
        for child in el:
            walk(child, mode)

    walk(node)
    return "".join(parts).strip()


def paragraph_style(p: etree._Element) -> str:
    vals = p.xpath("./w:pPr/w:pStyle/@w:val", namespaces=NS)
    return vals[0] if vals else ""


def main() -> None:
    source = Path(sys.argv[1]).resolve()
    output = Path(sys.argv[2]).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)

    with zipfile.ZipFile(source) as archive:
        names = set(archive.namelist())
        document = etree.fromstring(archive.read("word/document.xml"))
        comments = []
        if "word/comments.xml" in names:
            comments_root = etree.fromstring(archive.read("word/comments.xml"))
            for c in comments_root.xpath("//w:comment", namespaces=NS):
                comments.append(
                    {
                        "id": c.get(qn("id")),
                        "author": c.get(qn("author")),
                        "text": text_with_changes(c),
                    }
                )

    items: list[dict[str, object]] = []
    page = 1
    body = document.find("w:body", NS)
    assert body is not None
    for child in body:
        local = etree.QName(child).localname
        if local == "p":
            text = text_with_changes(child)
            style = paragraph_style(child)
            if text or style:
                items.append(
                    {
                        "kind": "paragraph",
                        "page_hint": page,
                        "style": style,
                        "text": text,
                    }
                )
            page += len(child.xpath(".//w:lastRenderedPageBreak", namespaces=NS))
            page += len(
                child.xpath(
                    ".//w:br[@w:type='page']",
                    namespaces=NS,
                )
            )
        elif local == "tbl":
            rows = []
            for tr in child.xpath("./w:tr", namespaces=NS):
                row = []
                for tc in tr.xpath("./w:tc", namespaces=NS):
                    cell_paragraphs = [
                        text_with_changes(p)
                        for p in tc.xpath(".//w:p", namespaces=NS)
                    ]
                    row.append("\n".join(x for x in cell_paragraphs if x))
                rows.append(row)
            items.append(
                {
                    "kind": "table",
                    "page_hint": page,
                    "rows": rows,
                }
            )
            page += len(child.xpath(".//w:lastRenderedPageBreak", namespaces=NS))
            page += len(
                child.xpath(
                    ".//w:br[@w:type='page']",
                    namespaces=NS,
                )
            )

    result = {
        "source": str(source),
        "page_hint_count": page,
        "items": items,
        "comments": comments,
    }
    output.write_text(
        json.dumps(result, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    print(
        json.dumps(
            {
                "source": str(source),
                "output": str(output),
                "page_hint_count": page,
                "item_count": len(items),
                "comment_count": len(comments),
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    main()
