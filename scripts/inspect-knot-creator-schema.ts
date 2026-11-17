// Read metadata only; omit defaults, SQL function bodies and all member records.
import { execFileSync } from 'node:child_process';
const result = JSON.parse(execFileSync('rork', ['supabase', 'schema'], { encoding: 'utf8', maxBuffer: 12_000_000 })) as { schema: { table_name: string; columns: { column_name: string; data_type: string }[]; rls_policies: { policy_name: string; cmd: string }[] | null }[] };
const names = ['profiles', 'whisper_profiles', 'whisper_admins', 'whisper_one_members', 'whisper_posts', 'whisper_follows'];
for (const name of names) {
  const table = result.schema.find(row => row.table_name === name);
  console.log(JSON.stringify(table ? { name, columns: table.columns.map(column => column.column_name), policies: table.rls_policies?.map(policy => ({ name: policy.policy_name, command: policy.cmd })) } : { name, found: false }));
}
