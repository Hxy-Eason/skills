#!/usr/bin/env node
"use strict";

const fs = require("fs");
const path = require("path");

const defaultMaxFindings = 80;
const excludedDirs = new Set([
  ".git",
  ".next",
  ".nuxt",
  ".cache",
  ".turbo",
  "node_modules",
  "dist",
  "build",
  "coverage",
  "target",
  "out",
]);

const textExtensions = new Set([
  ".cjs",
  ".css",
  ".csv",
  ".html",
  ".ini",
  ".js",
  ".json",
  ".jsx",
  ".md",
  ".mdx",
  ".mjs",
  ".ps1",
  ".sql",
  ".svg",
  ".ts",
  ".tsx",
  ".txt",
  ".vue",
  ".yaml",
  ".yml",
]);

const mojibakePatterns = [
  new RegExp("[\\u93BA\\u93C0\\u59AB\\u7D31\\u9428\\u4E36\\u6D63\\u4FAB\\u4E1F]"),
  new RegExp("[\\u951B\\u922B\\u923B\\u9286\\u20AC]"),
  new RegExp("(?:\\u9473\\u85C9|\\u9366|\\u934A|\\u55D7|\\u7D1D|\\u95C6|\\u7223|\\u934B)"),
  new RegExp("[\\uE000-\\uF8FF]"),
  new RegExp("(?:\\u7F02\\u682C|\\u74A7\\u52EC|\\u7C2E|\\u936B\\u6212|\\u890B\\u6383|\\u935B\\u6212|\\u9352\\u72B)"),
  new RegExp("(?:\\u00E2|\\u00E5|\\u00E4|\\u00E7|\\u00E9|\\u00EF|\\u00F0|\\u00C2|\\u00C3)[\\u0080-\\u00ff]?"),
  new RegExp("\\u20AC\\?"),
  new RegExp("\\uFFFD"),
];

const brokenStringPattern = new RegExp(
  "(?:label|title|description|placeholder|value)\\s*=\\s*[\"'`][^\"'`]*[\\u93BA\\u93C0\\u59AB\\u7D31\\u951B\\u922B\\u9286\\u20AC\\u9473\\u9366\\u95C6][^\"'`]*$",
);
const unsafePowerShellWritePattern = /\b(Set-Content|Out-File)\b(?![^\r\n]*-Encoding\s+utf8)/i;

function parseArgs(argv) {
  const options = {
    json: false,
    editorconfig: true,
    maxFindings: defaultMaxFindings,
    roots: [],
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    if (arg === "--json") {
      options.json = true;
    } else if (arg === "--no-editorconfig") {
      options.editorconfig = false;
    } else if (arg === "--max-findings") {
      const value = Number(argv[index + 1]);
      if (!Number.isFinite(value) || value < 1) throw new Error("--max-findings requires a positive number");
      options.maxFindings = value;
      index += 1;
    } else if (arg === "--help" || arg === "-h") {
      printHelp();
      process.exit(0);
    } else if (arg.startsWith("--")) {
      throw new Error(`Unknown option: ${arg}`);
    } else {
      options.roots.push(arg);
    }
  }

  if (options.roots.length === 0) options.roots.push(".");
  return options;
}

function printHelp() {
  console.log(`CJK Encoding Guard

Usage:
  node scan_mojibake.js [paths...] [--json] [--no-editorconfig] [--max-findings N]

Examples:
  node scan_mojibake.js
  node scan_mojibake.js src/app src/components/Shell.tsx
`);
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  const cwd = process.cwd();
  const files = collectFiles(options.roots, cwd);
  const findings = [];

  for (const file of files) {
    findings.push(...scanFile(file, cwd));
  }

  if (options.editorconfig) {
    findings.push(...scanEditorConfig(cwd));
  }

  const summary = summarize(findings, files.length);
  if (options.json) {
    console.log(JSON.stringify({ summary, findings }, null, 2));
  } else {
    printReport(summary, findings, options.maxFindings);
  }

  process.exit(summary.high > 0 ? 1 : 0);
}

function collectFiles(roots, cwd) {
  const files = [];

  for (const root of roots) {
    const absolute = path.resolve(cwd, root);
    if (!fs.existsSync(absolute)) continue;
    const stat = fs.statSync(absolute);
    if (stat.isDirectory()) {
      walk(absolute, files);
    } else if (stat.isFile() && isTextFile(absolute)) {
      files.push(absolute);
    }
  }

  return [...new Set(files)];
}

function walk(directory, files) {
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    if (entry.isDirectory()) {
      if (excludedDirs.has(entry.name)) continue;
      walk(path.join(directory, entry.name), files);
    } else if (entry.isFile()) {
      const file = path.join(directory, entry.name);
      if (isTextFile(file)) files.push(file);
    }
  }
}

function isTextFile(file) {
  return textExtensions.has(path.extname(file).toLowerCase());
}

function scanFile(file, cwd) {
  const relative = path.relative(cwd, file) || file;
  const text = fs.readFileSync(file, "utf8");
  const lines = text.split(/\r?\n/);
  const findings = [];

  lines.forEach((line, index) => {
    const lineNumber = index + 1;
    for (const pattern of mojibakePatterns) {
      if (pattern.test(line)) {
        findings.push({
          severity: "high",
          file: relative,
          line: lineNumber,
          code: "mojibake",
          message: "Suspicious CJK mojibake or replacement character found",
          excerpt: trimExcerpt(line),
        });
        break;
      }
    }

    if (brokenStringPattern.test(line)) {
      findings.push({
        severity: "high",
        file: relative,
        line: lineNumber,
        code: "possibly-broken-jsx-string",
        message: "Possible unclosed JSX/TSX string containing mojibake",
        excerpt: trimExcerpt(line),
      });
    }

    if (path.extname(file).toLowerCase() === ".ps1" && unsafePowerShellWritePattern.test(line)) {
      findings.push({
        severity: "medium",
        file: relative,
        line: lineNumber,
        code: "powershell-write-without-utf8",
        message: "PowerShell text write without explicit UTF-8 encoding",
        excerpt: trimExcerpt(line),
      });
    }
  });

  return findings;
}

function scanEditorConfig(cwd) {
  const file = path.join(cwd, ".editorconfig");
  if (!fs.existsSync(file)) {
    return [
      {
        severity: "low",
        file: ".editorconfig",
        line: 0,
        code: "missing-editorconfig",
        message: "No .editorconfig found; consider adding charset = utf-8",
        excerpt: "",
      },
    ];
  }

  const text = fs.readFileSync(file, "utf8").toLowerCase();
  if (!/charset\s*=\s*utf-8/.test(text)) {
    return [
      {
        severity: "low",
        file: ".editorconfig",
        line: 0,
        code: "missing-utf8-charset",
        message: ".editorconfig exists but does not declare charset = utf-8",
        excerpt: "",
      },
    ];
  }

  return [];
}

function summarize(findings, scannedFiles) {
  return {
    scannedFiles,
    high: findings.filter((finding) => finding.severity === "high").length,
    medium: findings.filter((finding) => finding.severity === "medium").length,
    low: findings.filter((finding) => finding.severity === "low").length,
    total: findings.length,
  };
}

function printReport(summary, findings, maxFindings) {
  console.log("CJK Encoding Guard");
  console.log(`Scanned files: ${summary.scannedFiles}`);
  console.log(`Findings: ${summary.total} (high ${summary.high}, medium ${summary.medium}, low ${summary.low})`);

  if (findings.length === 0) {
    console.log("No CJK encoding risks found.");
    return;
  }

  console.log("");
  for (const finding of findings.slice(0, maxFindings)) {
    const location = finding.line ? `${finding.file}:${finding.line}` : finding.file;
    console.log(`[${finding.severity}] ${location} ${finding.code} - ${finding.message}`);
    if (finding.excerpt) console.log(`  ${finding.excerpt}`);
  }

  if (findings.length > maxFindings) {
    console.log(`... ${findings.length - maxFindings} more findings omitted. Use --max-findings to show more.`);
  }
}

function trimExcerpt(line) {
  const compact = line.trim().replace(/\s+/g, " ");
  return compact.length > 160 ? `${compact.slice(0, 157)}...` : compact;
}

try {
  main();
} catch (error) {
  console.error(error instanceof Error ? error.message : String(error));
  process.exit(2);
}
