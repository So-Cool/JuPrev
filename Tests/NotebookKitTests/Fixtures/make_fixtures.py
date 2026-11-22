#!/usr/bin/env python3
"""Regenerates the test notebooks in this folder. Run: python3 make_fixtures.py"""
import base64
import json
from pathlib import Path

HERE = Path(__file__).parent

# 1x1 PNGs (red and blue) and a tiny SVG.
RED_PNG = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8DwHwAFBQIAX8jx0gAAAABJRU5ErkJggg=="
BLUE_PNG = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPj/HwADBwIAMCbHYQAAAABJRU5ErkJggg=="
SVG = '<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><rect width="10" height="10" fill="#08f"/></svg>'


def notebook(cells, **metadata):
    return {
        "nbformat": 4,
        "nbformat_minor": 5,
        "metadata": {"kernelspec": {"name": "python3", "language": "python"},
                     "language_info": {"name": "python"}, **metadata},
        "cells": cells,
    }


def md(source, **extra):
    return {"cell_type": "markdown", "metadata": {}, "source": source, **extra}


def code(source, outputs=(), count=1):
    return {"cell_type": "code", "metadata": {}, "execution_count": count, "source": source, "outputs": list(outputs)}


def write(path, nb):
    path = HERE / path
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(nb, indent=1) + "\n")


write("markdown-math.ipynb", notebook([
    md(["# Markdown and math\n", "\n", "Inline $a_i * b_i$ and $x_{1}^2$ keep their underscores and stars.\n"]),
    md("Display:\n\n$$\\sum_{i=1}^n x_i$$\n\nand \\[ E = mc^2 \\] and \\(\\alpha\\).\n"),
    md("\\begin{align}\na &= b_1 \\\\\nc &= d_2\n\\end{align}\n"),
    md("Prices like \\$5 and \\$10 are not math. Code `$x_1$` stays literal.\n\n```python\ncost = '$$not math$$'\n```\n"),
    md("Broken TeX: $\\frac{1}{$ is shown, not thrown.\n"),
    md("$$\\newcommand{\\R}{\\mathbb{R}} \\renewcommand{\\vv}[1]{\\mathbf{#1}}$$\n"),
    md("Macros from an earlier cell: $x \\in \\R$, $\\vv{w}$. MathJax-isms: $f_\\mathring{c}$.\n"),
    md("| a | b |\n|---|---|\n| 1 | 2 |\n\n> quote with **bold** and _em_\n\n- [link](https://example.com)\n"),
    {"cell_type": "raw", "metadata": {}, "source": "raw <b>cell</b>"},
]))

write("outputs.ipynb", notebook([
    code("print('hi')", [
        {"output_type": "stream", "name": "stdout", "text": ["hello\n"]},
        {"output_type": "stream", "name": "stdout", "text": "world\n"},
        {"output_type": "stream", "name": "stderr", "text": "warning: <careful>\n"},
        {"output_type": "stream", "name": "stdout", "text": "progress 10%\rprogress 50%\rprogress 100%\n"},
    ], count=1),
    code("42", [{"output_type": "execute_result", "execution_count": 2, "metadata": {},
                 "data": {"text/plain": "42"}}], count=2),
    code("df", [{"output_type": "execute_result", "execution_count": 3, "metadata": {},
                 "data": {"text/html": "<meta http-equiv=\"refresh\" content=\"0\"><table><tr><th>x</th></tr><tr><td>1</td></tr></table>",
                          "text/plain": "   x\n0  1"}}], count=3),
    code("plot()", [
        {"output_type": "display_data", "metadata": {}, "data": {"image/png": RED_PNG + "\n", "text/plain": "<Figure>"}},
        {"output_type": "display_data", "metadata": {}, "data": {"image/svg+xml": SVG, "text/plain": "<Figure>"}},
    ], count=4),
    code("Math(...)", [{"output_type": "display_data", "metadata": {},
                        "data": {"text/latex": "$\\int_0^1 x\\,dx$", "text/plain": "<Math>"}},
                       {"output_type": "display_data", "metadata": {},
                        "data": {"text/markdown": "**bold** output", "text/plain": "<Markdown>"}}], count=5),
    code("1/0", [{"output_type": "error", "ename": "ZeroDivisionError", "evalue": "division by zero",
                  "traceback": ["\u001b[0;31m---------------------------------------------------------------------------\u001b[0m",
                                "\u001b[0;31mZeroDivisionError\u001b[0m: division by zero"]}], count=6),
    code("widget", [{"output_type": "display_data", "metadata": {},
                     "data": {"application/vnd.jupyter.widget-view+json": {"model_id": "abc", "version_major": 2},
                              "text/plain": "IntSlider(value=0)"}}], count=7),
    code("plotly_with_fallback", [{"output_type": "display_data", "metadata": {},
                                   "data": {"text/html": "<div id='p'></div><script>alert(1)</script>", "image/png": BLUE_PNG}}], count=8),
    code("plotly_without_fallback", [{"output_type": "display_data", "metadata": {},
                                      "data": {"text/html": "<img src=x onerror=\"alert(1)\">"}}], count=9),
    code("", [], count=None),
]))

# images/nb/images.ipynb with files around it to exercise the folder policy.
images = HERE / "images"
(images / "nb/img").mkdir(parents=True, exist_ok=True)
(images / "shared").mkdir(parents=True, exist_ok=True)
(images / "nb/img/red.png").write_bytes(base64.b64decode(RED_PNG))
(images / "nb/img/with space.png").write_bytes(base64.b64decode(RED_PNG))
(images / "nb/notes.txt").write_text("not an image\n")
(images / "shared/blue.png").write_bytes(base64.b64decode(BLUE_PNG))
write("images/nb/images.ipynb", notebook([
    md("![same folder](img/red.png)"),
    md("![percent](img/with%20space.png?raw=true#frag)"),
    md("![parent](../shared/blue.png)"),
    md("![absolute](/etc/hosts.png)"),
    md("![remote](https://example.com/x.png)"),
    md("![missing](img/nope.png)"),
    md("![text](notes.txt)"),
    md('<img src="img/red.png" width="50" alt="raw tag">'),
    md("![pasted](attachment:pasted.png)", attachments={"pasted.png": {"image/png": BLUE_PNG}}),
]))

write("v3.ipynb", {"nbformat": 3, "nbformat_minor": 0, "metadata": {}, "worksheets": []})
(HERE / "broken.ipynb").write_text('{"nbformat": 4, "cells": [')
