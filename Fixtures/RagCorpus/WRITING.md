# Writing chapters for the RAG corpus

Read `Fixtures/RagCorpus/source/book-01/EPUB/ch01.xhtml` first. It is the exact
format model — match its shape, its register, and its punctuation.

## Format

```xml
<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
  <head><title>CHAPTER TITLE</title></head>
  <body>
    <h1>CHAPTER TITLE</h1>
    <p>…</p>          <!-- exactly 26 of these -->
    <h2>…</h2>        <!-- exactly one, roughly 60% down -->
  </body>
</html>
```

- Simplified Chinese, sober expository prose (科普随笔 register). Real content,
  no filler, no bullet lists, no markdown, no headings inside paragraphs.
- Plain `<p>` only. No attributes, no inline tags, no entities.
- Full-width Chinese punctuation: `，。？——、`.
- Each `<p>` roughly 90–140 characters. Do not write one enormous paragraph.
- Total `<p>` text (regex `<p>(.*?)</p>`, summed) between **2800 and 3500**.

## Reserved strings

These twelve strings carry the corpus's controlled properties. Each belongs to
exactly one chapter. **Do not write any of them unless your chapter is the one
listed.**

| string | belongs to |
|---|---|
| `把白天的碎片挪进长期仓库` | book-01 ch02 (written) |
| `让新痕迹在旧网络上重新固定` | book-01 ch06 |
| `让人愿意停下脚步的余地` | book-02 ch02 |
| `把路过的人留成在场的人` | book-02 ch06 |
| `两种语言之间没有并排的座位` | book-03 ch02 |
| `意义在换轨的地方会掉落一点` | book-03 ch06 |
| `突触稳态假说` | book-01 ch07 |
| `胶质淋巴系统` | book-01 ch08 |
| `破窗理论` | book-02 ch07 |
| `场所精神` | book-02 ch08 |
| `动态对等` | book-03 ch07 |
| `译本的生命周期` | book-03 ch08 |

A chapter whose property is one of these strings must contain it, verbatim,
exactly once (or, where stated, in three different paragraphs). Every other
chapter must avoid it entirely.

## Verify before finishing

```sh
cd /Users/zpc/projects/elsepage && python3 -c "
import re
p='FIXTURES_PATH'
s=open(p,encoding='utf-8').read()
ps=re.findall(r'<p>(.*?)</p>',s,re.S)
print('paras=%d chars=%d h2=%d' % (len(ps), sum(len(x) for x in ps), len(re.findall(r'<h2>',s))))
RESERVED=['把白天的碎片挪进长期仓库','让新痕迹在旧网络上重新固定','让人愿意停下脚步的余地','把路过的人留成在场的人','两种语言之间没有并排的座位','意义在换轨的地方会掉落一点','突触稳态假说','胶质淋巴系统','破窗理论','场所精神','动态对等','译本的生命周期']
print('reserved_hits=', [x for x in RESERVED if x in s])
"
```

Target output: `paras=26`, `chars` in range, `h2=1`, and `reserved_hits` empty
except for the one string your chapter owns.
