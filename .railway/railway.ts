import { defineRailway, github, group, image, postgres, preserve, project, service, volume } from "railway/iac";

export default defineRailway(() => {
  const Postgres = postgres("Postgres", { region: "asia-southeast1-eqsg3a" });
  Postgres.deploy = { limitOverride: { containers: { cpu: 4, memoryBytes: 4000000000 } } };
  Postgres.networking = { privateNetworkEndpoint: "postgres", tcpProxies: { "5432": {} } };
  const postgresVolume = volume("postgres-volume", { alerts: { usage: { "100": {}, "80": {}, "95": {} } }, allowOnlineResize: true, region: "asia-southeast1-eqsg3a", sizeMB: 5000 });
  const apacheSupersetRailwayVolume = volume("apache-superset-railway-volume", { alerts: { usage: { "100": {}, "80": {}, "95": {} } }, allowOnlineResize: true, region: "asia-southeast1-eqsg3a", sizeMB: 50000 });
  const clickhouseVolume = volume("clickhouse-volume", { alerts: { usage: { "100": {}, "80": {}, "95": {} } }, allowOnlineResize: true, region: "sin", sizeMB: 10000 });
  const ClickHouse = service("ClickHouse", {
    source: image("clickhouse/clickhouse-server:25.8"),
    healthcheck: "/ping",
    replicas: { "sin": 1 },
    deploy: { limitOverride: { containers: { cpu: 4, memoryBytes: 4000000000 } } },
    networking: { privateNetworkEndpoint: "clickhouse" },
    volumeMounts: { "/var/lib/clickhouse": clickhouseVolume },
    env: { CLICKHOUSE_DB: preserve(), CLICKHOUSE_PASSWORD: preserve(), CLICKHOUSE_USER: preserve(), DATABASE_JDBC_URL: preserve(), DATABASE_URL: preserve(), HOST: preserve(), HOST_PORT: preserve(), PORT: preserve(), PUBLIC_DATABASE_JDBC_URL: preserve(), PUBLIC_DATABASE_URL: preserve(), PUBLIC_HOST: preserve(), PUBLIC_HOST_PORT: preserve(), PUBLIC_PORT: preserve() },
  });
  const chUi = service("ch-ui", {
    source: image("ghcr.io/caioricciuti/ch-ui:latest"),
    replicas: { "sin": 1 },
    env: { VITE_CLICKHOUSE_PASS: preserve(), VITE_CLICKHOUSE_URL: preserve(), VITE_CLICKHOUSE_USER: preserve() },
  });
  const sector2AppEcho = service("sector2-app-echo", {
    source: github("sector-two/sector2-app-echo", { checkSuites: false }),
    start: "pnpm start",
    replicas: { "sin": 1 },
    domains: ["aokmer.yp.org.my"],
    env: { VITE_AUTH_SECRET: preserve(), VITE_DIRECTUS_TOKEN: preserve(), VITE_DIRECTUS_URL: preserve(), VITE_FACEBOOK_CLIENT_ID: preserve(), VITE_FACEBOOK_CLIENT_SECRET: preserve(), VITE_GOOGLE_CLIENT_ID: preserve(), VITE_GOOGLE_CLIENT_SECRET: preserve(), VITE_PUBLIC_BUILDER_KEY: preserve(), VITE_WEBHOOK_SECRET: preserve() },
  });
  const sector2Trino = service("sector2-trino", {
    source: github("neutrino-io/sector2-infra", { checkSuites: false, rootDirectory: "/services/trino" }),
    replicas: { "asia-southeast1-eqsg3a": 1 },
    env: { TRINO_ROLE: "coordinator", ADMIN_EMAIL: preserve(), ADMIN_PASSWORD: preserve(), ADMIN_USERNAME: preserve(), CLICKHOUSE_DATABASE: preserve(), CLICKHOUSE_HOST: preserve(), CLICKHOUSE_PASSWORD: preserve(), CLICKHOUSE_PORT: preserve(), CLICKHOUSE_USER: preserve(), FLASK_APP: preserve(), FORCE_REBUILD_TEST: preserve(), R2_ACCESS_KEY: preserve(), R2_CATALOG_TOKEN: preserve(), R2_ICEBERG_REST_URI: preserve(), R2_ICEBERG_WAREHOUSE: preserve(), R2_S3_ENDPOINT: preserve(), R2_SECRET_KEY: preserve(), SECRET_KEY: preserve(), SQLALCHEMY_DATABASE_URI: preserve(), SUPERSET_ENV: preserve(), SUPERSET_SECRET_KEY: preserve() },
  });
  const sector2TrinoWorker = service("sector2-trino-worker", {
    source: github("neutrino-io/sector2-infra", { checkSuites: false, rootDirectory: "/services/trino" }),
    replicas: { "asia-southeast1-eqsg3a": 1 },
    env: { TRINO_ROLE: "worker", R2_ACCESS_KEY: sector2Trino.env.R2_ACCESS_KEY, R2_CATALOG_TOKEN: sector2Trino.env.R2_CATALOG_TOKEN, R2_ICEBERG_REST_URI: sector2Trino.env.R2_ICEBERG_REST_URI, R2_ICEBERG_WAREHOUSE: sector2Trino.env.R2_ICEBERG_WAREHOUSE, R2_S3_ENDPOINT: sector2Trino.env.R2_S3_ENDPOINT, R2_SECRET_KEY: sector2Trino.env.R2_SECRET_KEY, CLICKHOUSE_HOST: sector2Trino.env.CLICKHOUSE_HOST, CLICKHOUSE_PORT: sector2Trino.env.CLICKHOUSE_PORT, CLICKHOUSE_USER: sector2Trino.env.CLICKHOUSE_USER, CLICKHOUSE_PASSWORD: sector2Trino.env.CLICKHOUSE_PASSWORD, CLICKHOUSE_DATABASE: sector2Trino.env.CLICKHOUSE_DATABASE },
  });
  const sector2Superset = service("sector2-superset", {
    source: github("neutrino-io/sector2-infra", { checkSuites: false, rootDirectory: "/services/superset" }),
    build: { buildEnvironment: "V3", builder: "DOCKERFILE", dockerfilePath: "Dockerfile" },
    start: "./superset_init.sh",
    replicas: { "asia-southeast1-eqsg3a": 1 },
    deploy: { limitOverride: { containers: { cpu: 4, memoryBytes: 4000000000 } }, restartPolicyMaxRetries: 3 },
    volumeMounts: { "/app/superset_home": apacheSupersetRailwayVolume },
    env: { ADMIN_EMAIL: preserve(), ADMIN_PASSWORD: preserve(), ADMIN_USERNAME: preserve(), MAPBOX_API_KEY: preserve(), PORT: preserve(), SECRET_KEY: preserve(), SQLALCHEMY_DATABASE_URI: preserve(), SUPERSET_SECRET_KEY: preserve() },
  });
  const Clickhouse = group("Clickhouse", [chUi]);

  return project("sector2", {
    resources: [ClickHouse, sector2AppEcho, sector2Trino, sector2TrinoWorker, Postgres, sector2Superset, postgresVolume, apacheSupersetRailwayVolume, clickhouseVolume, Clickhouse],
  });
});
