use Mix.Config

config :tus, Tus.Plug,
  upload_baseurl: "/files",
  upload_path: "/tmp",
  version: "1.0.0",
  max_body_read: 8_000_000,
  body_read_len: 1_000_000

config :tus, Tus.Plug.Cache,
  persistence_path: "/tmp",
  ets_backend: PersistentEts

import_config "#{Mix.env()}.exs"
