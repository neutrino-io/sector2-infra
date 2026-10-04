import { defineRailway, github, group, image, postgres, preserve, project, service, volume } from "railway/iac";

export default defineRailway((ctx) => {
  const prod = ctx.environment === "production";

  // ============================================================================
  // Volumes
  // ============================================================================
  // Volumes hold the few pieces of state the services can't regenerate:
  //   - postgresVolume:        Superset metadata DB (legacy backups)
  //   - apacheSupersetRailwayVolume: Superset app state (DBs, charts, users)
  //   - clickhouseVolume:        Nematix-managed ClickHouse, included for parity
  //
  // NOTE: `alerts: { usage: { ... } }` was in the legacy config but the
  // current Railway SDK (v5.62+) silently ignores the field. Removed; if
  // usage alerts are needed in the future, set them via the Railway UI.
  // ============================================================================
  const postgresVolume = volume("postgres-volume", {
    region: prod ? "asia-southeast1-eqsg3a" : "asia-southeast1-eqsg3a",
    sizeMB: 5000,
  });
  const apacheSupersetRailwayVolume = volume("apache-superset-railway-volume", {
    region: prod ? "asia-southeast1-eqsg3a" : "asia-southeast1-eqsg3a",
    sizeMB: 50000,
  });
  const clickhouseVolume = volume("clickhouse-volume", {
    region: "sin",
    sizeMB: 10000,
  });

  // ============================================================================
  // Databases
  // ============================================================================
  // postgres is provisioned as a Railway-managed plugin; the IaC declares
  // intent (region, CPU, memory, private networking) but the actual
  // provision happens via Railway's product workflow.
  // ============================================================================
  const Postgres = postgres("Postgres", { region: "asia-southeast1-eqsg3a" });
  Postgres.deploy = { limitOverride: { containers: { cpu: 4, memoryBytes: 4000000000 } } };
  Postgres.networking = { privateNetworkEndpoint: "postgres", tcpProxies: { "5432": {} } };

  // ============================================================================
  // ClickHouse (Nematix-managed legacy voter roll DB)
  // ============================================================================
  // This service is provisioned but not fully deployed from this repo.
  // Nematix manages the actual ClickHouse deployment externally; this
  // block declares the service's intent and reserves the Railway slot.
  // ============================================================================
  const ClickHouse = service("ClickHouse", {
    source: image("clickhouse/clickhouse-server:25.8"),
    healthcheck: "/ping",
    replicas: 1,
    deploy: { limitOverride: { containers: { cpu: 4, memoryBytes: 4000000000 } } },
    networking: { privateNetworkEndpoint: "clickhouse" },
    volumeMounts: { "/var/lib/clickhouse": clickhouseVolume },
    env: {
      CLICKHOUSE_DB: preserve(),
      CLICKHOUSE_PASSWORD: preserve(),
      CLICKHOUSE_USER: preserve(),
      DATABASE_JDBC_URL: preserve(),
      DATABASE_URL: preserve(),
      HOST: preserve(),
      HOST_PORT: preserve(),
      PORT: preserve(),
      PUBLIC_DATABASE_JDBC_URL: preserve(),
      PUBLIC_DATABASE_URL: preserve(),
      PUBLIC_HOST: preserve(),
      PUBLIC_HOST_PORT: preserve(),
      PUBLIC_PORT: preserve(),
    },
  });

  const chUi = service("ch-ui", {
    source: image("ghcr.io/caioricciuti/ch-ui:latest"),
    replicas: 1,
    env: {
      VITE_CLICKHOUSE_PASS: preserve(),
      VITE_CLICKHOUSE_URL: preserve(),
      VITE_CLICKHOUSE_USER: preserve(),
    },
  });

  // ============================================================================
  // sector2-app-echo (Aokmer front-end)
  // ============================================================================
  // Source: GitHub repo. Branch defaults to "main"; the deploy pipeline
  // builds on Railway's NIXPACKS builder (the default for `github()`
  // sources, so we don't set it explicitly).
  // ============================================================================
  const sector2AppEcho = service("sector2-app-echo", {
    source: github("sector-two/sector2-app-echo", { checkSuites: false }),
    start: "pnpm start",
    replicas: 1,
    domains: ["aokmer.yp.org.my"],
    env: {
      VITE_AUTH_SECRET: preserve(),
      VITE_DIRECTUS_TOKEN: preserve(),
      VITE_DIRECTUS_URL: preserve(),
      VITE_FACEBOOK_CLIENT_ID: preserve(),
      VITE_FACEBOOK_CLIENT_SECRET: preserve(),
      VITE_GOOGLE_CLIENT_ID: preserve(),
      VITE_GOOGLE_CLIENT_SECRET: preserve(),
      VITE_PUBLIC_BUILDER_KEY: preserve(),
      VITE_WEBHOOK_SECRET: preserve(),
    },
  });

  // ============================================================================
  // sector2-trino (Query engine — 2-node topology: coordinator + worker)
  // ============================================================================
  // Build context is set per-role via the Trino entrypoint script
  // (services/trino/trino-entrypoint.sh) which renders either the
  // coordinator or worker config depending on TRINO_ROLE.
  //
  // The /v1/memory endpoint (which the coordinator polls to verify
  // worker health) requires `http-server.authentication.allow-insecure-over-http=true`
  // — see services/trino/template/trino-config/config.properties.template
  // for the rationale. Without that flag, the Item #3 bug recurs:
  // worker is registered for liveness but never enters the query-execution
  // pool, and queries stay in state=QUEUED with nodes=0.
  // ============================================================================
  const sector2Trino = service("sector2-trino", {
    source: github("neutrino-io/sector2-infra", {
      checkSuites: false,
      rootDirectory: "/services/trino",
    }),
    replicas: 1,
    networking: { privateNetworkEndpoint: "sector2-trino" },
    env: {
      TRINO_ROLE: "coordinator",
      ADMIN_EMAIL: preserve(),
      ADMIN_PASSWORD: preserve(),
      ADMIN_USERNAME: preserve(),
      CLICKHOUSE_DATABASE: preserve(),
      CLICKHOUSE_HOST: preserve(),
      CLICKHOUSE_PASSWORD: preserve(),
      CLICKHOUSE_PORT: preserve(),
      CLICKHOUSE_USER: preserve(),
      FLASK_APP: preserve(),
      FORCE_REBUILD_TEST: preserve(),
      R2_ACCESS_KEY: preserve(),
      R2_CATALOG_TOKEN: preserve(),
      R2_ICEBERG_REST_URI: preserve(),
      R2_ICEBERG_WAREHOUSE: preserve(),
      R2_S3_ENDPOINT: preserve(),
      R2_SECRET_KEY: preserve(),
      SECRET_KEY: preserve(),
      SQLALCHEMY_DATABASE_URI: preserve(),
      SUPERSET_ENV: preserve(),
      SUPERSET_SECRET_KEY: preserve(),
    },
  });

  const sector2TrinoWorker = service("sector2-trino-worker", {
    source: github("neutrino-io/sector2-infra", {
      checkSuites: false,
      rootDirectory: "/services/trino",
    }),
    replicas: 1,
    networking: { privateNetworkEndpoint: "sector2-trino-worker" },
    env: {
      TRINO_ROLE: "worker",
      R2_ACCESS_KEY: sector2Trino.env.R2_ACCESS_KEY,
      R2_CATALOG_TOKEN: sector2Trino.env.R2_CATALOG_TOKEN,
      R2_ICEBERG_REST_URI: sector2Trino.env.R2_ICEBERG_REST_URI,
      R2_ICEBERG_WAREHOUSE: sector2Trino.env.R2_ICEBERG_WAREHOUSE,
      R2_S3_ENDPOINT: sector2Trino.env.R2_S3_ENDPOINT,
      R2_SECRET_KEY: sector2Trino.env.R2_SECRET_KEY,
      CLICKHOUSE_HOST: sector2Trino.env.CLICKHOUSE_HOST,
      CLICKHOUSE_PORT: sector2Trino.env.CLICKHOUSE_PORT,
      CLICKHOUSE_USER: sector2Trino.env.CLICKHOUSE_USER,
      CLICKHOUSE_PASSWORD: sector2Trino.env.CLICKHOUSE_PASSWORD,
      CLICKHOUSE_DATABASE: sector2Trino.env.CLICKHOUSE_DATABASE,
    },
  });

  // ============================================================================
  // sector2-superset (BI dashboard)
  // ============================================================================
  // Uses Railway's V3 builder with a custom Dockerfile. The newer
  // builder field is just a string like "Dockerfile" (when builder
  // is "DOCKERFILE") or the build command (when builder is NIXPACKS).
  // For multi-line build sequences, use a string array.
  // ============================================================================
  const sector2Superset = service("sector2-superset", {
    source: github("neutrino-io/sector2-infra", {
      checkSuites: false,
      rootDirectory: "/services/superset",
    }),
    build: {
      builder: "DOCKERFILE",
      dockerfilePath: "Dockerfile",
    },
    start: "./superset_init.sh",
    replicas: 1,
    deploy: {
      limitOverride: { containers: { cpu: 4, memoryBytes: 4000000000 } },
      restartPolicyMaxRetries: 3,
    },
    volumeMounts: { "/app/superset_home": apacheSupersetRailwayVolume },
    env: {
      ADMIN_EMAIL: preserve(),
      ADMIN_PASSWORD: preserve(),
      ADMIN_USERNAME: preserve(),
      MAPBOX_API_KEY: preserve(),
      PORT: preserve(),
      SECRET_KEY: preserve(),
      SQLALCHEMY_DATABASE_URI: preserve(),
      SUPERSET_SECRET_KEY: preserve(),
    },
  });

  // ============================================================================
  // Resource grouping
  // ============================================================================
  // Group the ClickHouse frontend (ch-ui) with its backend (ClickHouse)
  // for clearer dashboard navigation in the Railway UI.
  // ============================================================================
  const Clickhouse = group("Clickhouse", [chUi]);

  return project("sector2", {
    resources: [
      ClickHouse,
      sector2AppEcho,
      sector2Trino,
      sector2TrinoWorker,
      Postgres,
      sector2Superset,
      postgresVolume,
      apacheSupersetRailwayVolume,
      clickhouseVolume,
      Clickhouse,
    ],
  });
});