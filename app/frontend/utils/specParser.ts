/**
 * Utility functions for parsing spec markdown content
 */

export interface ValidationIssue {
  type: "dependency_mismatch";
  message: string;
  markdownValue: string[];
  metadataValue: string[];
}

/**
 * Extract spec ID patterns (S-XXXX) from text
 */
function extractSpecIds(text: string): string[] {
  const specIdPattern = /S-\d{4}/g;
  const matches = text.match(specIdPattern) || [];
  // Return unique IDs
  return [...new Set(matches)];
}

/**
 * Parse dependencies from the ## Dependencies section of markdown
 * Returns array of spec IDs found in the section
 */
export function parseSpecDependencies(markdown: string): string[] {
  // Find the Dependencies section (case-insensitive)
  const dependenciesMatch = markdown.match(/^##\s+Dependencies\s*$/im);

  if (!dependenciesMatch) {
    return [];
  }

  const startIndex = dependenciesMatch.index! + dependenciesMatch[0].length;

  // Find the next ## heading or end of file
  const remainingText = markdown.slice(startIndex);
  const nextSectionMatch = remainingText.match(/^##\s+/m);
  const sectionEnd = nextSectionMatch
    ? nextSectionMatch.index!
    : remainingText.length;

  const dependenciesSection = remainingText.slice(0, sectionEnd);

  // Check if section says "None" or is effectively empty
  const contentWithoutWhitespace = dependenciesSection
    .replace(/\s/g, "")
    .toLowerCase();
  if (contentWithoutWhitespace === "none" || contentWithoutWhitespace === "") {
    return [];
  }

  // Extract all S-XXXX patterns from the section
  return extractSpecIds(dependenciesSection);
}

/**
 * Validate spec metadata against markdown content
 * Returns validation issues if any discrepancies found
 */
export function validateSpecMetadata(
  requirement: { depends_on: string[] },
  markdown: string,
): ValidationIssue[] {
  const issues: ValidationIssue[] = [];

  const markdownDeps = parseSpecDependencies(markdown);
  const metadataDeps = requirement.depends_on || [];

  // Check if arrays are different (order-independent comparison)
  const markdownSet = new Set(markdownDeps);
  const metadataSet = new Set(metadataDeps);

  const hasDifference =
    markdownSet.size !== metadataSet.size ||
    [...markdownSet].some((id) => !metadataSet.has(id));

  if (hasDifference) {
    issues.push({
      type: "dependency_mismatch",
      message: "Markdown↔metadata mismatch",
      markdownValue: markdownDeps.sort(),
      metadataValue: metadataDeps.sort(),
    });
  }

  return issues;
}

/**
 * Generate markdown Dependencies section from spec IDs
 */
export function generateDependenciesSection(specIds: string[]): string {
  if (specIds.length === 0) {
    return "## Dependencies\n\nNone\n";
  }

  const listItems = specIds.map((id) => `- ${id}`).join("\n");
  return `## Dependencies\n\n${listItems}\n`;
}

/**
 * Replace the Dependencies section in markdown with new content
 */
export function replaceDependenciesSection(
  markdown: string,
  newSpecIds: string[],
): string {
  const dependenciesMatch = markdown.match(/^##\s+Dependencies\s*$/im);

  if (!dependenciesMatch) {
    // Section doesn't exist, append it before the first ## section after Overview
    const overviewMatch = markdown.match(/^##\s+Overview\s*$/im);
    if (overviewMatch) {
      const overviewEnd = markdown.indexOf(
        "\n##",
        overviewMatch.index! + overviewMatch[0].length,
      );
      if (overviewEnd > -1) {
        const before = markdown.slice(0, overviewEnd);
        const after = markdown.slice(overviewEnd);
        return (
          before + "\n\n" + generateDependenciesSection(newSpecIds) + after
        );
      }
    }
    // Fallback: append at end
    return markdown + "\n\n" + generateDependenciesSection(newSpecIds);
  }

  const startIndex = dependenciesMatch.index!;

  // Find the next ## heading or end of file
  const remainingText = markdown.slice(
    startIndex + dependenciesMatch[0].length,
  );
  const nextSectionMatch = remainingText.match(/^##\s+/m);
  const sectionEnd = nextSectionMatch
    ? startIndex + dependenciesMatch[0].length + nextSectionMatch.index!
    : markdown.length;

  const before = markdown.slice(0, startIndex);
  const after = markdown.slice(sectionEnd);

  return before + generateDependenciesSection(newSpecIds) + after;
}

/**
 * Parse the Overview section from markdown
 * Returns the content of the Overview section (without the heading)
 */
export function parseSpecOverview(markdown: string): string {
  // Find the Overview section (case-insensitive)
  const overviewMatch = markdown.match(/^##\s+Overview\s*$/im);

  if (!overviewMatch) {
    return "";
  }

  const startIndex = overviewMatch.index! + overviewMatch[0].length;

  // Find the next ## heading or end of file
  const remainingText = markdown.slice(startIndex);
  const nextSectionMatch = remainingText.match(/^##\s+/m);
  const sectionEnd = nextSectionMatch
    ? nextSectionMatch.index!
    : remainingText.length;

  const overviewSection = remainingText.slice(0, sectionEnd);

  // Trim whitespace and return
  return overviewSection.trim();
}

/**
 * Replace the Overview section in markdown with new content
 */
export function replaceOverviewSection(
  markdown: string,
  newContent: string,
): string {
  const overviewMatch = markdown.match(/^##\s+Overview\s*$/im);

  if (!overviewMatch) {
    // Section doesn't exist, add it after the title (# heading)
    const titleMatch = markdown.match(/^#\s+.+$/m);
    if (titleMatch) {
      const titleEnd = titleMatch.index! + titleMatch[0].length;
      const before = markdown.slice(0, titleEnd);
      const after = markdown.slice(titleEnd);
      return before + "\n\n## Overview\n\n" + newContent + "\n" + after;
    }
    // Fallback: prepend at start
    return "## Overview\n\n" + newContent + "\n\n" + markdown;
  }

  const startIndex = overviewMatch.index!;

  // Find the next ## heading or end of file
  const remainingText = markdown.slice(startIndex + overviewMatch[0].length);
  const nextSectionMatch = remainingText.match(/^##\s+/m);
  const sectionEnd = nextSectionMatch
    ? startIndex + overviewMatch[0].length + nextSectionMatch.index!
    : markdown.length;

  const before = markdown.slice(0, startIndex);
  const after = markdown.slice(sectionEnd);

  return before + "## Overview\n\n" + newContent + "\n\n" + after;
}
