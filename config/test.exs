use Mix.Config

config :tus, Tus.Plug,
  upload_path: "test/fixtures",
  max_body_read: 2,
  body_read_len: 1

config :tus, Tus.Plug.Cache,
  persistence_path: "/tmp",
  ets_backend: :ets
