import * as cdk from 'aws-cdk-lib';
import { RetentionDays } from 'aws-cdk-lib/aws-logs';

import { BlocksStack, BlocksPresets } from '@aws-blocks/blocks/cdk';
import type { BlocksDefaults } from '@aws-blocks/blocks/cdk';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';
import { getStackName } from '@aws-blocks/blocks/scripts';

const __dirname = dirname(fileURLToPath(import.meta.url));

const app = new cdk.App();

const sandboxMode = app.node.tryGetContext('sandboxMode') === 'true';
const projectRoot = app.node.tryGetContext('projectRoot') || process.cwd();

/**
 * Settings for `npm run deploy` of this TEST app: a disposable stack.
 *
 * - Tables are deleted with the stack (no deletion protection, no retention),
 *   so `npm run destroy` removes everything. Photos in the cloud are lost then.
 * - No point-in-time-recovery backups; logs kept for one week.
 * - Low API throttling as cost protection: the API has no login, so anyone who
 *   learns the URL can call it. Raise these numbers only if testing needs it.
 * - allowedOrigins [] blocks browsers; the native iOS app is not affected by CORS.
 */
const disposableTestDefaults: BlocksDefaults = {
  ...BlocksPresets.production,
  removalPolicy: cdk.RemovalPolicy.DESTROY,
  deletionProtection: false,
  pointInTimeRecovery: false,
  logRetention: RetentionDays.ONE_WEEK,
  throttling: { rateLimit: 20, burstLimit: 40 },
  allowedOrigins: [],
};

const stackName = getStackName({ sandbox: sandboxMode, projectRoot });
export const blocksStack = await BlocksStack.create(app, stackName, {
  backendHandlerPath: join(__dirname, 'index.handler.ts'),
  backendCDKPath: join(__dirname, 'index.ts'),
  defaults: sandboxMode ? BlocksPresets.sandbox : disposableTestDefaults,
});

// No `Hosting` construct: MySyncPhotos has no web frontend, only the API used by
// the iOS app. (The template's S3 + CloudFront site hosting was removed.)
