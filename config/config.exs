use Mix.Config

config :tus, Tus.Plug,
  upload_baseurl: "/files",
  upload_path: "/tmp",
  version: "1.0.0",
  max_body_read: 8_000_000,
  body_read_len: 1_000_000

import_config "#{Mix.env()}.exs"
