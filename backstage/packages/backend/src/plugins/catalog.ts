import { useHotCleanup } from '@backstage/backend-common';
import { CatalogBuilder, runPeriodically } from '@backstage/plugin-catalog-backend';
import { MicrosoftGraphOrgEntityProvider, MicrosoftGraphOrgReaderProcessor } from '@backstage/plugin-catalog-backend-module-msgraph';
import { ScaffolderEntitiesProcessor } from '@backstage/plugin-scaffolder-backend';
import { Router } from 'express';
import { PluginEnvironment } from '../types';

export default async function createPlugin(
  env: PluginEnvironment,
): Promise<Router> {

  const builder = await CatalogBuilder.create(env);
  
  const msGraphOrgEntityProvider = MicrosoftGraphOrgEntityProvider.fromConfig(
    env.config,
    {
      id: 'https://graph.microsoft.com/v1.0',
      target: 'https://graph.microsoft.com/v1.0',
      logger: env.logger,
    },
  );

  builder.addEntityProvider(msGraphOrgEntityProvider);

  builder.addProcessor(
    MicrosoftGraphOrgReaderProcessor.fromConfig(env.config, {
      logger: env.logger,
    }),
  );

  builder.addProcessor(new ScaffolderEntitiesProcessor());
  
  const { processingEngine, router } = await builder.build();
  
  await processingEngine.start();
  
    // Trigger a read every 5 minutes
    useHotCleanup(
      module,
      runPeriodically(() => msGraphOrgEntityProvider.read(), 5 * 60 * 1000),
    );
    
  return router;
}
