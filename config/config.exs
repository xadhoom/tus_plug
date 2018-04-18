use Mix.Config

config :tus_plug, TusPlug,
  upload_baseurl: "/files",
  upload_path: "/tmp",
  version: "1.0.0",
  max_body_read: 8_000_000,
  body_read_len: 1_000_000,
  # 4GByte
  max_size: 4_294_967_296

config :tus_plug, TusPlug.Cache,
  persistence_path: "/tmp",
  ets_backend: PersistentEts

import_config "#{Mix.env()}.exs"
