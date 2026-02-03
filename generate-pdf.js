const puppeteer = require("puppeteer");
const fs = require("fs");
const path = require("path");
const MarkdownIt = require("markdown-it");

const md = new MarkdownIt({
  html: true,
  linkify: true,
  typographer: true,
});

// File order based on your requirements - README first, then rest in order
const files = [
  "README.md",
  "01-architecture-analysis.md",
  "02-security-analysis.md",
  "03-typescript-analysis.md",
  "04-testing-analysis.md",
  "05-performance-analysis.md",
  "06-code-duplication-analysis.md",
  "07-dependency-analysis.md",
  "08-i18n-responsive-analysis.md",
  "09-business-impact-assessment.md",
  "10-implementation-roadmap.md",
];

const basePath = "c:/Users/PG518JW/Downloads/analysis/analysis";

// CSS for professional styling
const css = `
<style>
  @import url('https://fonts.googleapis.com/css2?family=Inter:wght@300;400;500;600;700&display=swap');
  
  * {
    margin: 0;
    padding: 0;
    box-sizing: border-box;
  }
  
  body {
    font-family: 'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
    line-height: 1.6;
    color: #2d3748;
    font-size: 11px;
    background: white;
    margin: 0;
    padding: 20px;
  }
  
  .page-break {
    page-break-before: always;
    margin-top: 0;
    padding-top: 30px;
  }
  
  .cover-page {
    display: flex;
    flex-direction: column;
    justify-content: center;
    align-items: center;
    height: 100vh;
    text-align: center;
    page-break-after: always;
  }
  
  .cover-title {
    font-size: 32px;
    font-weight: 700;
    color: #1a365d;
    margin-bottom: 20px;
    line-height: 1.2;
  }
  
  .cover-subtitle {
    font-size: 18px;
    color: #4a5568;
    margin-bottom: 40px;
    font-weight: 400;
  }
  
  .cover-meta {
    font-size: 14px;
    color: #718096;
    border-top: 1px solid #e2e8f0;
    padding-top: 20px;
    margin-top: 40px;
  }
  
  h1 {
    font-size: 24px;
    font-weight: 700;
    color: #1a365d;
    margin-top: 40px;
    margin-bottom: 20px;
    padding-bottom: 10px;
    border-bottom: 3px solid #3182ce;
  }
  
  h2 {
    font-size: 18px;
    font-weight: 600;
    color: #2d3748;
    margin-top: 30px;
    margin-bottom: 15px;
    padding-left: 10px;
    border-left: 4px solid #3182ce;
  }
  
  h3 {
    font-size: 14px;
    font-weight: 600;
    color: #4a5568;
    margin-top: 20px;
    margin-bottom: 10px;
  }
  
  h4, h5, h6 {
    font-size: 12px;
    font-weight: 600;
    color: #718096;
    margin-top: 15px;
    margin-bottom: 8px;
  }
  
  p {
    margin-bottom: 12px;
    text-align: justify;
  }
  
  ul, ol {
    margin-bottom: 12px;
    padding-left: 20px;
  }
  
  li {
    margin-bottom: 4px;
  }
  
  table {
    width: 100%;
    border-collapse: collapse;
    margin: 15px 0;
    font-size: 10px;
  }
  
  th, td {
    border: 1px solid #e2e8f0;
    padding: 6px 8px;
    text-align: left;
  }
  
  th {
    background-color: #f7fafc;
    font-weight: 600;
    color: #2d3748;
  }
  
  tr:nth-child(even) {
    background-color: #f8f9fa;
  }
  
  code {
    background: #f1f5f9;
    padding: 2px 4px;
    border-radius: 3px;
    font-family: 'Courier New', monospace;
    font-size: 9px;
    color: #e53e3e;
  }
  
  pre {
    background: #1a202c;
    color: #e2e8f0;
    padding: 12px;
    border-radius: 6px;
    overflow-x: auto;
    margin: 12px 0;
    font-size: 9px;
  }
  
  pre code {
    background: none;
    padding: 0;
    color: #e2e8f0;
  }
  
  blockquote {
    border-left: 4px solid #3182ce;
    padding-left: 12px;
    margin: 12px 0;
    font-style: italic;
    color: #4a5568;
    background: #f7fafc;
    padding: 8px 12px;
    border-radius: 0 4px 4px 0;
  }
  
  .emoji {
    font-size: 12px;
    margin-right: 5px;
  }
  
  .grade-critical { color: #e53e3e; font-weight: 600; }
  .grade-high { color: #dd6b20; font-weight: 600; }
  .grade-medium { color: #d69e2e; font-weight: 600; }
  .grade-low { color: #38a169; font-weight: 600; }
  
  .status-red { color: #e53e3e; }
  .status-yellow { color: #d69e2e; }
  .status-green { color: #38a169; }
  
  .metric-card {
    background: #f7fafc;
    border: 1px solid #e2e8f0;
    border-radius: 6px;
    padding: 12px;
    margin: 10px 0;
  }
  
  .metric-title {
    font-weight: 600;
    color: #2d3748;
    margin-bottom: 5px;
  }
  
  .metric-value {
    font-size: 16px;
    font-weight: 700;
    color: #3182ce;
  }
  
  /* Print optimizations */
  @media print {
    body { margin: 0; padding: 15px; }
    .page-break { margin-top: 0; }
    h1 { margin-top: 20px; }
  }
</style>
`;

async function generatePDF() {
  try {
    console.log("Starting PDF generation...");

    // Read all markdown files
    let htmlContent = "";

    // Add cover page
    htmlContent += `
      <div class="cover-page">
        <h1 class="cover-title">OPP Survey Tool<br/>Enterprise Codebase Analysis</h1>
        <p class="cover-subtitle">Comprehensive Technical Assessment & Implementation Roadmap</p>
        <div class="cover-meta">
          <p><strong>Repository:</strong> ey-org/opp-survey-tool</p>
          <p><strong>Branch:</strong> soh-3.2 (default: develop)</p>
          <p><strong>Technology:</strong> React 18.3.1, TypeScript 4.5.5, Context API, SCSS</p>
          <p><strong>Analysis Date:</strong> February 2026</p>
          <p><strong>Overall Grade:</strong> C+ (Satisfactory with Critical Issues)</p>
          <p><strong>Prepared By:</strong> Factory.ai Droid Code Audit System</p>
        </div>
      </div>
    `;

    // Process each file
    for (let i = 0; i < files.length; i++) {
      const fileName = files[i];
      const filePath = path.join(basePath, fileName);

      console.log(`Processing ${fileName}...`);

      if (!fs.existsSync(filePath)) {
        console.warn(`File not found: ${filePath}`);
        continue;
      }

      const content = fs.readFileSync(filePath, "utf8");

      // Add page break before each section (except the first)
      if (i > 0) {
        htmlContent += '<div class="page-break"></div>';
      }

      // Convert markdown to HTML
      const htmlSection = md.render(content);
      htmlContent += htmlSection;
    }

    // Create complete HTML document
    const fullHtml = `
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>OPP Survey Tool - Enterprise Codebase Analysis</title>
  ${css}
</head>
<body>
  ${htmlContent}
</body>
</html>
    `;

    console.log("Launching browser...");
    const browser = await puppeteer.launch({
      headless: true,
      args: ["--no-sandbox", "--disable-setuid-sandbox"],
    });

    const page = await browser.newPage();

    // Set content and wait for fonts to load
    await page.setContent(fullHtml, { waitUntil: "networkidle0" });

    console.log("Generating PDF...");
    await page.pdf({
      path: "OPP-Survey-Tool-Analysis-Report.pdf",
      format: "A4",
      margin: {
        top: "20mm",
        right: "15mm",
        bottom: "20mm",
        left: "15mm",
      },
      printBackground: true,
      displayHeaderFooter: true,
      headerTemplate: `
        <div style="font-size: 8px; color: #666; margin: 0 15mm; width: 100%; text-align: center;">
          OPP Survey Tool - Enterprise Codebase Analysis
        </div>
      `,
      footerTemplate: `
        <div style="font-size: 8px; color: #666; margin: 0 15mm; width: 100%; text-align: center;">
          <span>Page <span class="pageNumber"></span> of <span class="totalPages"></span></span>
          <span style="float: right;">Confidential - EY Internal Use</span>
        </div>
      `,
    });

    await browser.close();
    console.log(
      "PDF generated successfully: OPP-Survey-Tool-Analysis-Report.pdf",
    );
  } catch (error) {
    console.error("Error generating PDF:", error);
    throw error;
  }
}

generatePDF();
