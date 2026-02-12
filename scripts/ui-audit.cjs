/*
  UI audit helper: scans frontend TS/TSX files for inline styles, inline SVGs,
  and raw form elements that should use shared UI components.

  Usage:
    - From repo root: `node scripts/ui-audit.cjs`
    - From frontend package: `npm run ui-audit` (via app/frontend/package.json)

  Exit codes:
    - 0: no issues found
    - 1: issues found (listed in stdout)
*/
const fs = require("fs");
const path = require("path");

const ROOT = path.join(__dirname, "..", "app", "frontend");
const TARGET_DIRS = [
  path.join(ROOT, "components"),
  path.join(ROOT, "views"),
  path.join(ROOT, "App.tsx"),
];

const ALLOWED_SVG = [
  path.join(ROOT, "components", "copilot", "CopilotAvatar.tsx"),
];

const ALLOWED_INLINE_STYLE = [
  path.join(ROOT, "components", "copilot", "CopilotAvatar.tsx"),
  path.join(ROOT, "components", "copilot", "building-blocks", "CopilotLoading.tsx"),
];

const ALLOWED_RAW_INPUT = [
  path.join(ROOT, "components", "RequirementDetailSlideOut.tsx"),
];

const UI_COMPONENT_DIR = path.join(ROOT, "components", "ui");

const fileList = [];

const collectFiles = (entry) => {
  if (!fs.existsSync(entry)) return;
  const stat = fs.statSync(entry);
  if (stat.isFile()) {
    if (entry.endsWith(".ts") || entry.endsWith(".tsx")) {
      fileList.push(entry);
    }
    return;
  }
  const items = fs.readdirSync(entry);
  items.forEach((item) => collectFiles(path.join(entry, item)));
};

TARGET_DIRS.forEach((entry) => collectFiles(entry));

const issues = [];

const addIssue = (file, line, type, detail) => {
  issues.push({ file, line, type, detail });
};

const hasUiImport = (content, name) => {
  const regex = new RegExp(`from\\s+["']\\./ui/${name}["']`);
  return regex.test(content);
};

const checkFile = (filePath) => {
  const content = fs.readFileSync(filePath, "utf8");
  const lines = content.split(/\r?\n/);
  const isUiComponentFile = filePath.startsWith(UI_COMPONENT_DIR + path.sep);

  lines.forEach((line, index) => {
    const lineNum = index + 1;

    if (line.includes("style={{")) {
      if (ALLOWED_INLINE_STYLE.includes(filePath)) {
        return;
      }
      addIssue(filePath, lineNum, "inline-style", line.trim());
    }

    if (/<svg\b/.test(line)) {
      if (!ALLOWED_SVG.includes(filePath)) {
        addIssue(filePath, lineNum, "inline-svg", line.trim());
      }
    }

    if (!isUiComponentFile && /<button\b/.test(line)) {
      if (!hasUiImport(content, "button")) {
        addIssue(filePath, lineNum, "raw-button", "Use Button from components/ui/button");
      }
    }

    if (!isUiComponentFile && /<input\b/.test(line)) {
      if (ALLOWED_RAW_INPUT.includes(filePath)) {
        return;
      }
      if (!hasUiImport(content, "input")) {
        addIssue(filePath, lineNum, "raw-input", "Use Input from components/ui/input");
      }
    }

    if (!isUiComponentFile && /<select\b/.test(line)) {
      if (!hasUiImport(content, "select")) {
        addIssue(filePath, lineNum, "raw-select", "Use Select from components/ui/select");
      }
    }

    if (!isUiComponentFile && /<textarea\b/.test(line)) {
      if (!hasUiImport(content, "textarea")) {
        addIssue(filePath, lineNum, "raw-textarea", "Use Textarea from components/ui/textarea");
      }
    }
  });
};

fileList.forEach(checkFile);

if (issues.length === 0) {
  console.log("UI audit: no issues found");
  process.exit(0);
}

issues.forEach((issue) => {
  const rel = path.relative(process.cwd(), issue.file);
  console.log(`${rel}:${issue.line} [${issue.type}] ${issue.detail}`);
});

process.exit(1);
