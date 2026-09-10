# CV — .NET Software Developer application

`ChrysostomosAntoniou_CV_DotNet.docx` is the tailored CV, targeted at a
.NET Developer role (C#, ASP.NET, .NET, REST APIs, MS SQL Server, Git).

It is generated from `build_cv.js` so it can be re-tailored for other
applications without hand-editing Word.

## Rebuilding

```bash
npm install docx
node build_cv.js ChrysostomosAntoniou_CV_DotNet.docx
```

## Structure

Summary → Core Technical Skills → Professional Experience → Technical
Projects → Education → Languages & Certifications → Interests.

Section wording deliberately mirrors the job description (design/develop/
maintain, technical documentation, system test validation, architecture
contribution) so it reads well to both an ATS keyword screen and a human
reviewer. Hyperlinks are embedded for email, GitHub repositories, LinkedIn
and each linked project repo.

## PDF

`ChrysostomosAntoniou_CV_DotNet.pdf` is the version to send to recruiters.
It is rendered from `cv.html` with headless Chromium, which preserves the
embedded hyperlinks as real clickable PDF link annotations:

```bash
chrome --headless --no-pdf-header-footer \
  --print-to-pdf=ChrysostomosAntoniou_CV_DotNet.pdf cv.html
```

A4, 2 pages. `cv.html` and `build_cv.js` hold the same content — edit both
if the wording changes.
