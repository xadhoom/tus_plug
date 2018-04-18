use Mix.Config

config :tus_plug, TusPlug,
  upload_path: "test/fixtures",
  max_body_read: 2,
  body_read_len: 1

config :tus_plug, TusPlug.Cache,
  persistence_path: "/tmp",
  ets_backend: :ets
