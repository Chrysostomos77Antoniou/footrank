const {
  Document, Packer, Paragraph, TextRun, ExternalHyperlink, AlignmentType,
  BorderStyle, TabStopType, TabStopPosition, LevelFormat, convertInchesToTwip,
} = require('docx');
const fs = require('fs');

const ACCENT = '1F3864';   // deep navy
const MUTED  = '444444';
const FONT   = 'Calibri';

/* ---------- helpers ---------- */

const t = (text, opts = {}) => new TextRun({ text, font: FONT, ...opts });

// Name block
const name = (text) => new Paragraph({
  alignment: AlignmentType.CENTER,
  spacing: { after: 20 },
  children: [t(text, { bold: true, size: 34, color: ACCENT, characterSpacing: 20 })],
});

const tagline = (text) => new Paragraph({
  alignment: AlignmentType.CENTER,
  spacing: { after: 80 },
  children: [t(text, { size: 21, color: ACCENT, bold: true, allCaps: true, characterSpacing: 30 })],
});

// Contact line with optional hyperlinks. parts = [{text} | {text, link}]
const contactLine = (parts, after = 40) => new Paragraph({
  alignment: AlignmentType.CENTER,
  spacing: { after },
  children: parts.flatMap((p, i) => {
    const sep = i === 0 ? [] : [t('  •  ', { size: 18, color: '999999' })];
    const run = p.link
      ? new ExternalHyperlink({
          link: p.link,
          children: [t(p.text, { size: 18, color: ACCENT, underline: {} })],
        })
      : t(p.text, { size: 18, color: MUTED });
    return [...sep, run];
  }),
});

// Section heading with rule underneath
const section = (text) => new Paragraph({
  spacing: { before: 200, after: 90 },
  border: { bottom: { style: BorderStyle.SINGLE, size: 7, color: ACCENT, space: 3 } },
  children: [t(text, { bold: true, size: 21, color: ACCENT, allCaps: true, characterSpacing: 30 })],
});

// Body paragraph
const body = (text, opts = {}) => new Paragraph({
  spacing: { after: opts.after ?? 60, line: 250 },
  alignment: opts.justify ? AlignmentType.BOTH : AlignmentType.LEFT,
  children: [t(text, { size: 19, color: '222222' })],
});

// Role title (left) + dates (right, tabbed)
const roleHeader = (title, org, dates) => new Paragraph({
  spacing: { before: 130, after: 10 },
  tabStops: [{ type: TabStopType.RIGHT, position: TabStopPosition.MAX }],
  children: [
    t(title, { bold: true, size: 20, color: '111111' }),
    ...(org ? [t('  |  ', { size: 19, color: '999999' }), t(org, { size: 19, color: ACCENT, bold: true })] : []),
    t('\t'),
    t(dates, { size: 18, color: MUTED, italics: true }),
  ],
});

// Sub-line under a role (location / stack), optionally with a link
const subLine = (text, link, linkText) => new Paragraph({
  spacing: { after: 50 },
  children: [
    t(text, { size: 18, color: MUTED, italics: true }),
    ...(link ? [
      t('  •  ', { size: 18, color: '999999' }),
      new ExternalHyperlink({ link, children: [t(linkText || link, { size: 18, color: ACCENT, underline: {} })] }),
    ] : []),
  ],
});

// Bullet
const bullet = (text) => new Paragraph({
  numbering: { reference: 'cv-bullets', level: 0 },
  spacing: { after: 40, line: 250 },
  children: [t(text, { size: 19, color: '222222' })],
});

// Bold-label bullet: "Label: rest"
const labelBullet = (label, rest) => new Paragraph({
  numbering: { reference: 'cv-bullets', level: 0 },
  spacing: { after: 40, line: 250 },
  children: [
    t(label + ': ', { size: 19, bold: true, color: '111111' }),
    t(rest, { size: 19, color: '222222' }),
  ],
});

/* ---------- content ---------- */

const EMAIL   = 'chrysostomosantoniou77@gmail.com';
const PHONE   = '+357 96 460 190';
const LINKEDIN= 'https://www.linkedin.com/in/chrysostomos-antoniou-19186934a/';
const GH_ALL  = 'https://github.com/Chrysostomos77Antoniou?tab=repositories';
const GH_FOOT = 'https://github.com/Chrysostomos77Antoniou/footrank';
const GH_MC   = 'https://github.com/Chrysostomos77Antoniou/MissionControl';

const children = [

  name('CHRYSOSTOMOS ANTONIOU'),
  tagline('.NET Software Developer'),
  contactLine([
    { text: 'Nicosia, Cyprus' },
    { text: PHONE },
    { text: EMAIL, link: 'mailto:' + EMAIL },
  ], 30),
  contactLine([
    { text: 'GitHub Repositories', link: GH_ALL },
    { text: 'LinkedIn', link: LINKEDIN },
  ], 60),

  /* ---- SUMMARY ---- */
  section('Professional Summary'),
  body(
    'Computer Science graduate and current MSc Artificial Intelligence candidate with commercial experience designing, ' +
    'developing and maintaining .NET-based web applications in C# and SQL. Comfortable across the full stack — ' +
    'object-oriented C# on the back end, relational database design and query optimisation, and HTML5, CSS and JavaScript ' +
    'on the front end. Has delivered production applications end-to-end, from architecture and data modelling through ' +
    'REST API integration, automated system testing and Git-based release management. Fluent in Greek and English, ' +
    'with a strong appetite for learning, taking initiative and growing within a collaborative engineering team.',
    { justify: true, after: 40 },
  ),

  /* ---- SKILLS ---- */
  section('Core Technical Skills'),
  labelBullet('Languages & .NET', 'C#, .NET — object-oriented design with a focus on clean, maintainable and scalable code; C++, Java, Python, Dart, TypeScript'),
  labelBullet('Web & APIs', 'RESTful API design and integration, JSON, XML, HTML5, CSS, JavaScript'),
  labelBullet('Databases', 'SQL — query writing, updates, schema design and performance optimisation; PostgreSQL'),
  labelBullet('Testing & Quality', 'System test validation, automated unit and integration testing, regression suites, code reviews, debugging and troubleshooting'),
  labelBullet('Version Control & CI', 'Git and GitHub, branching and pull-request workflows, GitHub Actions CI pipelines'),
  labelBullet('Security & Cloud', 'Basic application security practices, authentication and row-level access control, automated dependency and security scanning, cloud-hosted backends'),
  labelBullet('Documentation', 'Technical documentation of developed code, implemented functionality and system design'),

  /* ---- EXPERIENCE ---- */
  section('Professional Experience'),

  roleHeader('Software Developer', 'ZEBRA Consultants', '06/2025 – 12/2025'),
  subLine('Nicosia, Cyprus  •  C#, .NET, SQL, HTML'),
  bullet('Developed and maintained features for existing web applications according to functional and technical specifications, working across both back end and front end using C#, HTML and SQL.'),
  bullet('Maintained and extended production software to ensure smooth day-to-day operation, improve the user experience and continuously enhance application capabilities.'),
  bullet('Supported database management tasks including writing and tuning queries, applying data updates and optimising query performance.'),
  bullet('Performed bug fixing and system testing of delivered code, validating changes before release to ensure stability.'),
  bullet('Participated in code reviews and team system updates, contributing to code quality and shared engineering standards.'),

  roleHeader('Computing Teacher', 'Pascal Education', '12/2025 – 07/2026'),
  subLine('Nicosia, Cyprus'),
  bullet('Delivered engaging Computing lessons in programming, computer science and digital skills to students of varying abilities.'),
  bullet('Explained technical concepts clearly in both Greek and English, building students’ problem-solving ability and confidence with technology.'),
  bullet('Planned lessons and classroom activities, demonstrating strong communication, interpersonal and organisational skills with students and staff.'),

  roleHeader('Machine Learning Intern', 'IQ3SOLAR', '07/2024 – 09/2024'),
  subLine('Limassol, Cyprus  •  Python, machine learning, data engineering'),
  bullet('Forecast solar power generation using machine learning models and weather data, delivering day-ahead and multi-day production forecasts.'),
  bullet('Handled data management tasks — collecting, cleaning and preparing large weather and production datasets for model training and evaluation.'),

  roleHeader('Security Systems Technician', 'A.A. Protecta Private Security Services Ltd', '06/2022 – 08/2022'),
  subLine('Nicosia, Cyprus'),
  bullet('Installed and configured security systems and programmed camera hardware on client sites.'),

  roleHeader('Infantry Soldier', 'National Guard of Cyprus', '07/2018 – 09/2019'),
  subLine('Nicosia, Cyprus'),
  bullet('Completed mandatory 14-month national service, developing discipline, responsibility and adaptability.'),
  bullet('Built strong communication, problem-solving and collaboration skills working with a diverse group of people under demanding conditions.'),

  /* ---- PROJECTS ---- */
  section('Technical Projects'),
  body('All source code available at my GitHub profile: ', { after: 30 }),
  new Paragraph({
    spacing: { after: 60 },
    children: [new ExternalHyperlink({
      link: GH_ALL,
      children: [t(GH_ALL, { size: 18, color: ACCENT, underline: {} })],
    })],
  }),

  roleHeader('FootRank — Cross-Platform Football Application', null, 'Personal Project'),
  subLine('Flutter, Dart, PostgreSQL, REST APIs, GitHub Actions', GH_FOOT, 'github.com/Chrysostomos77Antoniou/footrank'),
  bullet('Designed the architecture and shipped a production application end-to-end for organising matches, ranking teams and booking courts — defining the data model, API layer and feature roadmap from business requirements.'),
  bullet('Modelled a relational PostgreSQL schema and secured it with row-level security policies, applying basic application security practices for authentication and per-user data access.'),
  bullet('Integrated RESTful APIs with JSON payloads for all client–server communication, including real-time team ratings, match proposals, team invites and court-booking workflows.'),
  bullet('Wrote automated unit and integration test suites, including regression coverage for score submission and match-proposal flows, and ran them as system test validation in a GitHub Actions CI pipeline alongside an automated security scan.'),
  bullet('Maintained and continuously enhanced the application through versioned releases (currently v1.0.9) using Git branching and pull-request workflows, with technical documentation maintained alongside the code.'),

  roleHeader('Mission Control — Agent Operations Dashboard', null, 'Personal Project'),
  subLine('Next.js, TypeScript, REST APIs', GH_MC, 'github.com/Chrysostomos77Antoniou/MissionControl'),
  bullet('Built a web dashboard that runs autonomous agents to research, draft and act on product growth goals, with a mandatory human approval gate for high-risk actions.'),
  bullet('Implemented the front end in TypeScript against REST endpoints, applying clean separation between the UI, service and data layers.'),

  roleHeader('CRM / Admin Panel', null, 'Personal Project'),
  subLine('Flutter Web, PostgreSQL'),
  bullet('Developed an internal web admin panel for managing users, teams, courts and match data, covering full CRUD operations over a relational database.'),

  /* ---- EDUCATION ---- */
  section('Education'),

  roleHeader('MSc Artificial Intelligence', 'University of Cyprus', '09/2025 – Present'),
  subLine('Nicosia, Cyprus'),

  roleHeader('BSc Computer Science', 'University of Piraeus', '09/2019 – 02/2025'),
  subLine('Piraeus, Greece  •  Grade: 7.32 / 10'),
  bullet('Comprehensive Computer Science programme covering software engineering, web development, databases and cybersecurity, with proficiency developed in C#, C++, Java and Python.'),
  bullet('Key modules: Database Management Systems, ERP/CRM Systems, Modern Software Technology — Software for Mobile Devices.'),
  bullet('Dissertation: designed, built and deployed a mobile application — awarded a grade of 10 / 10.'),

  roleHeader('Apolytirion (High School Diploma)', 'Saint Varnavas Lyceum', '09/2015 – 06/2018'),
  subLine('Nicosia, Cyprus  •  15.75 / 20 (“Very Good”)  •  Computer Science, Physics, Mathematics'),

  /* ---- LANGUAGES & CERTS ---- */
  section('Languages & Certifications'),
  labelBullet('Greek', 'Native'),
  labelBullet('English', 'Fluent — IGCSE English as a Second Language (Grade C)'),
  labelBullet('ictEurope (Intermediate)', 'Databases, General Computing, Internet Services'),

  /* ---- INTERESTS ---- */
  section('Interests'),
  body('Football — two years in the Olympiakos Nicosia academies and one season as a semi-professional player for Ethnikos Latsion (2017/18). Muay Thai, gym and music.', { after: 0 }),
];

const doc = new Document({
  creator: 'Chrysostomos Antoniou',
  title: 'Chrysostomos Antoniou — CV',
  description: 'CV — .NET Software Developer',
  numbering: {
    config: [{
      reference: 'cv-bullets',
      levels: [{
        level: 0,
        format: LevelFormat.BULLET,
        text: '•',
        alignment: AlignmentType.LEFT,
        style: {
          paragraph: { indent: { left: convertInchesToTwip(0.22), hanging: convertInchesToTwip(0.15) } },
          run: { color: ACCENT, font: FONT },
        },
      }],
    }],
  },
  sections: [{
    properties: {
      page: {
        margin: {
          top: convertInchesToTwip(0.5),
          bottom: convertInchesToTwip(0.5),
          left: convertInchesToTwip(0.6),
          right: convertInchesToTwip(0.6),
        },
      },
    },
    children,
  }],
});

Packer.toBuffer(doc).then((buf) => {
  fs.writeFileSync(process.argv[2] || 'ChrysostomosAntoniou_CV_DotNet.docx', buf);
  console.log('written');
});
