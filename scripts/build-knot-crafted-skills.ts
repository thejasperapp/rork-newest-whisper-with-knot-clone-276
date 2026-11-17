// Package the eight reviewed, project-authored craft guides for Cloudflare.
// No network, shell, installed-library mutation or runtime tool execution.
import { readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';

const names = ['web-research', 'spreadsheet-craft', 'gmail-behavior', 'creator-analytics', 'artefact-creation', 'browser-driving', 'memory-craft', 'build-verification'] as const;
const root = new URL('../', import.meta.url);
const records = names.map(name => {
  const path = new URL(`.agents/skills/knot-${name}/SKILL.md`, root);
  const text = readFileSync(path, 'utf8');
  const match = /^---\nname: ([a-z0-9-]+)\ndescription: ("[^\n]+")\nmetadata:\n  runtime-name: ([a-z0-9-]+)\n  source: ("https:\/\/r2-pub\.rork\.com\/attachments\/[a-z0-9]+\.md")\n---\n\n([\s\S]+)$/.exec(text);
  if (!match || match[1] !== `knot-${name}` || match[3] !== name) throw new Error(`Invalid skill frontmatter: ${name}`);
  const description: unknown = JSON.parse(match[2]), source: unknown = JSON.parse(match[4]);
  if (typeof description !== 'string' || !description.trim() || description.length > 1024 || typeof source !== 'string' || match[5].length > 16000 || text.split('\n').length > 500) throw new Error(`Invalid skill content: ${name}`);
  return { name, description, source, sha256: createHash('sha256').update(text).digest('hex'), body: match[5].trim() };
});
const output = '// Generated from .agents/skills/knot-*/SKILL.md by scripts/build-knot-crafted-skills.ts.\n// Supplemental server craft standards, NOT evidence of installed/live guide reads.\nexport const knotCraftSkills = ' + JSON.stringify(records, null, 2) + ' as const;\nexport type KnotCraftSkillName = typeof knotCraftSkills[number]["name"];\n';
const destination = new URL('functions/knot-crafted-skills-data.ts', root);
if (process.argv.includes('--check')) {
  if (readFileSync(destination, 'utf8') !== output) throw new Error('Craft bundle differs from its source guides; regenerate it.');
  console.log('Eight skill frontmatters, complete bodies, source links and hashes match the bundled runtime catalog.');
} else {
  writeFileSync(destination, output);
  console.log(`Packaged ${records.length} complete craft guides into ${fileURLToPath(destination)} (${Buffer.byteLength(output)} bytes).`);
}
