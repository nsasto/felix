/**
 * Utility functions for parsing spec markdown content
 */

export type SyncableField = "title" | "priority" | "tags" | "depends_on";

export interface ValidationIssue {
  field: SyncableField;
  type: "mismatch";
  message: string;
  markdownValue: any;
  metadataValue: any;
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
 * Parse title from markdown (# S-XXXX: Title)
 */
export function parseTitle(markdown: string): string {
  const titleMatch = markdown.match(/^#\s+S-\d{4}:\s+(.+)$/m);
  return titleMatch ? titleMatch[1].trim() : "";
}

/**
 * Parse priority from markdown (**Priority:** High)
 */
export function parsePriority(markdown: string): string {
  const priorityMatch = markdown.match(/^\*\*Priority:\*\*\s+(.+)$/m);
  if (!priorityMatch) return "medium"; // default
  return priorityMatch[1].trim().toLowerCase();
}

/**
 * Parse tags from the ## Tags section of markdown
 */
export function parseTags(markdown: string): string[] {
  const inlineTagsMatch = markdown.match(/^\*\*Tags\*\*:?\s+(.+)$/im);
  if (inlineTagsMatch) {
    const raw = inlineTagsMatch[1].trim();
    if (raw.toLowerCase() === "none") {
      return [];
    }
    return raw
      .split(",")
      .map((tag) => tag.trim())
      .filter((tag) => tag.length > 0);
  }

  const tagsMatch = markdown.match(/^##\s+Tags\s*$/im);
  if (!tagsMatch) return [];

  const startIndex = tagsMatch.index! + tagsMatch[0].length;
  const remainingText = markdown.slice(startIndex);
  const nextSectionMatch = remainingText.match(/^##\s+/m);
  const sectionEnd = nextSectionMatch
    ? nextSectionMatch.index!
    : remainingText.length;
  const tagsSection = remainingText.slice(0, sectionEnd);

  // Check if section says "None" or is effectively empty
  const contentWithoutWhitespace = tagsSection
    .replace(/\s/g, "")
    .toLowerCase();
  if (contentWithoutWhitespace === "none" || contentWithoutWhitespace === "") {
    return [];
  }

  const bulletMatches = tagsSection.match(/^-\s+(.+)$/gm);
  return bulletMatches
    ? bulletMatches.map((m) => m.replace(/^-\s+/, "").trim())
    : [];
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
  requirement: {
    title: string;
    priority: string;
    tags: string[];
    depends_on: string[];
  },
  markdown: string,
): ValidationIssue[] {
  const issues: ValidationIssue[] = [];

  // Check title
  const markdownTitle = parseTitle(markdown);
  if (markdownTitle && markdownTitle !== requirement.title) {
    issues.push({
      field: "title",
      type: "mismatch",
      message: "Title mismatch",
      markdownValue: markdownTitle,
      metadataValue: requirement.title,
    });
  }

  // Check priority
  const markdownPriority = parsePriority(markdown);
  if (markdownPriority !== requirement.priority) {
    issues.push({
      field: "priority",
      type: "mismatch",
      message: "Priority mismatch",
      markdownValue: markdownPriority,
      metadataValue: requirement.priority,
    });
  }

  // Check tags
  const markdownTags = parseTags(markdown);
  const tagsSet1 = new Set(markdownTags);
  const tagsSet2 = new Set(requirement.tags || []);
  const tagsDiffer =
    tagsSet1.size !== tagsSet2.size ||
    [...tagsSet1].some((t) => !tagsSet2.has(t));

  if (tagsDiffer) {
    issues.push({
      field: "tags",
      type: "mismatch",
      message: "Tags mismatch",
      markdownValue: markdownTags.sort(),
      metadataValue: (requirement.tags || []).sort(),
    });
  }

  // Check dependencies
  const markdownDeps = parseSpecDependencies(markdown);
  const metadataDeps = requirement.depends_on || [];
  const depsSet1 = new Set(markdownDeps);
  const depsSet2 = new Set(metadataDeps);
  const depsDiffer =
    depsSet1.size !== depsSet2.size ||
    [...depsSet1].some((id) => !depsSet2.has(id));

  if (depsDiffer) {
    issues.push({
      field: "depends_on",
      type: "mismatch",
      message: "Dependencies mismatch",
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

/**
 * Replace title in markdown (# S-XXXX: Title)
 */
export function replaceTitle(markdown: string, title: string): string {
  const match = markdown.match(/^(#\s+S-\d{4}:)\s+.+$/m);
  if (!match) return markdown;
  return markdown.replace(match[0], `${match[1]} ${title}`);
}

/**
 * Replace priority in markdown (**Priority:** value)
 */
export function replacePriority(markdown: string, priority: string): string {
  const priorityMatch = markdown.match(/^\*\*Priority:\*\*\s+.+$/m);
  const capitalized = priority.charAt(0).toUpperCase() + priority.slice(1);

  if (!priorityMatch) {
    // Add after title if doesn't exist
    const titleMatch = markdown.match(/^#\s+S-\d{4}:.+$/m);
    if (titleMatch) {
      const insertPos = titleMatch.index! + titleMatch[0].length;
      return (
        markdown.slice(0, insertPos) +
        `\n\n**Priority:** ${capitalized}` +
        markdown.slice(insertPos)
      );
    }
    return markdown;
  }

  const trailingBreak = /\s{2}$/.test(priorityMatch[0]) ? "  " : "";
  return markdown.replace(
    priorityMatch[0],
    `**Priority:** ${capitalized}${trailingBreak}`,
  );
}

/**
 * Generate markdown Tags section from tag array
 */
export function generateTagsSection(tags: string[]): string {
  if (tags.length === 0) {
    return "## Tags\n\nNone\n";
  }

  const listItems = tags.map((tag) => `- ${tag}`).join("\n");
  return `## Tags\n\n${listItems}\n`;
}

/**
 * Replace the Tags section in markdown with new content
 */
function generateTagsLine(tags: string[], useColon: boolean): string {
  const label = useColon ? "**Tags:**" : "**Tags**";
  if (tags.length === 0) {
    return `${label} None`;
  }
  return `${label} ${tags.join(", ")}`;
}

export function replaceTags(markdown: string, tags: string[]): string {
  const inlineTagsMatch = markdown.match(/^\*\*Tags\*\*:?\s+.+$/im);
  if (inlineTagsMatch) {
    const trailingBreak = /\s{2}$/.test(inlineTagsMatch[0]) ? "  " : "";
    const useColon = inlineTagsMatch[0].includes("**Tags:**");
    return markdown.replace(
      inlineTagsMatch[0],
      `${generateTagsLine(tags, useColon)}${trailingBreak}`,
    );
  }

  const tagsMatch = markdown.match(/^##\s+Tags\s*$/im);
  const tagsSection = generateTagsSection(tags);

  if (!tagsMatch) {
    // Prefer inline tags near header metadata.
    const priorityMatch = markdown.match(/^\*\*Priority:\*\*\s+.+$/m);
    if (priorityMatch) {
      const insertPos = priorityMatch.index! + priorityMatch[0].length;
      return (
        markdown.slice(0, insertPos) +
        `\n${generateTagsLine(tags, false)}` +
        markdown.slice(insertPos)
      );
    }

    const titleMatch = markdown.match(/^#\s+S-\d{4}:.+$/m);
    if (titleMatch) {
      const insertPos = titleMatch.index! + titleMatch[0].length;
      return (
        markdown.slice(0, insertPos) +
        `\n\n${generateTagsLine(tags, false)}` +
        markdown.slice(insertPos)
      );
    }

    // Fallback: add a Tags section after Dependencies or at end.
    const depsMatch = markdown.match(/^##\s+Dependencies\s*$/im);
    if (depsMatch) {
      const startIndex = depsMatch.index! + depsMatch[0].length;
      const remainingText = markdown.slice(startIndex);
      const nextSectionMatch = remainingText.match(/^##\s+/m);
      if (nextSectionMatch) {
        const insertPos = startIndex + nextSectionMatch.index!;
        return (
          markdown.slice(0, insertPos) +
          "\n" +
          tagsSection +
          markdown.slice(insertPos)
        );
      }
    }
    return markdown + "\n\n" + tagsSection;
  }

  const startIndex = tagsMatch.index!;
  const remainingText = markdown.slice(startIndex + tagsMatch[0].length);
  const nextSectionMatch = remainingText.match(/^##\s+/m);
  const sectionEnd = nextSectionMatch
    ? startIndex + tagsMatch[0].length + nextSectionMatch.index!
    : markdown.length;

  return (
    markdown.slice(0, startIndex) + tagsSection + markdown.slice(sectionEnd)
  );
}
