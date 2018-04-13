use Mix.Config

config :tus, Tus.Plug,
  upload_baseurl: "/files",
  upload_path: "/tmp",
  version: "1.0.0"

import_config "#{Mix.env()}.exs"
