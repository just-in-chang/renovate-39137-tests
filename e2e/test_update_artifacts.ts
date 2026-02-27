/**
 * E2E test that directly invokes renovate's cargo updateArtifacts() function
 * against fixture repos. This exercises the actual cargoUpdatePrecise code path
 * including the fix for #39137 (skipping --precise when currentValue !== newValue).
 *
 * Usage: tsx test_update_artifacts.ts <fixture-dir> <scenario-json>
 */

import { cpSync } from 'node:fs';

async function main(): Promise<void> {
  const { GlobalConfig } = await import('/opt/renovate/lib/config/global.ts');

  const fixtureDir = process.argv[2];
  const scenarioJson = process.argv[3];

  if (!fixtureDir || !scenarioJson) {
    console.error(
      'Usage: tsx test_update_artifacts.ts <fixture-dir> <scenario-json>',
    );
    process.exit(2);
  }

  // Work on a copy so the original fixture is not modified
  const workDir = `/tmp/e2e-work-${Date.now()}`;
  cpSync(fixtureDir, workDir, { recursive: true });

  GlobalConfig.set({
    localDir: workDir,
    cacheDir: '/tmp/renovate-cache',
    binarySource: 'global',
    exposeAllEnv: true,
  });

  const { updateArtifacts } = await import(
    '/opt/renovate/lib/modules/manager/cargo/artifacts.ts'
  );

  const scenario = JSON.parse(scenarioJson);

  // Build the updatedDeps array with the 'crate' datasource
  const updatedDeps = scenario.updatedDeps.map(
    (dep: Record<string, string>) => ({
      ...dep,
      datasource: 'crate',
    }),
  );

  try {
    const results = await updateArtifacts({
      packageFileName: scenario.packageFileName,
      updatedDeps,
      newPackageFileContent: scenario.newPackageFileContent,
      config: {
        isLockFileMaintenance: false,
        constraints: {},
      },
    });

    if (!results) {
      console.log('RESULT:NO_CHANGE');
    } else {
      const hasError = results.some(
        (r: Record<string, unknown>) => r.artifactError,
      );
      if (hasError) {
        for (const r of results) {
          if (r.artifactError) {
            console.error('ARTIFACT_ERROR:', JSON.stringify(r.artifactError));
          }
        }
        console.log('RESULT:ERROR');
      } else {
        console.log('RESULT:SUCCESS');
      }
    }
  } catch (err: unknown) {
    const error = err as Error & { stderr?: string };
    console.error('EXCEPTION:', error.message);
    if (error.stderr) {
      console.error('STDERR:', error.stderr);
    }
    console.log('RESULT:ERROR');
  }
}

main().catch((err) => {
  console.error('FATAL:', err);
  process.exit(1);
});
